/**
 * Almacén local de la Caja diaria y la Caja chica, con cola de envío ("outbox").
 *
 * Toda acción de la persona (guardar una fila, enviar a caja chica, subir una foto…) se aplica al instante
 * en el dispositivo y deja una operación en la cola; sync.ts las manda al servidor cuando hay conexión y
 * en el orden en que ocurrieron. Así la pantalla nunca espera a la red y nada se pierde si se corta.
 *
 * Es una fábrica sin dependencias de React Native (el almacenamiento, la fecha y los ids se inyectan) para
 * poder probarla con Node. La instancia real está en runtime.ts.
 */
import { aperturaEstimada, saldoChica, saldosHoja } from "./calc";
import { nuevoId } from "./ids";
import { CIUDADES, hojaKey, type Adjunto, type Ciudad, type Config, type Fila, type Hoja, type MovChica } from "./types";

export type OpKind = "abrirHoja" | "patchHoja" | "putFila" | "delFila" | "putAdjunto" | "delAdjunto" | "transfer" | "delTransfer" | "putMov" | "delMov" | "putConfig";
/** `ref` es el id de la cosa sobre la que actúa (fila, movimiento, adjunto, transferencia) o la clave de la hoja. */
export type Op = { id: string; kind: OpKind; ref: string; data?: Record<string, any>; error?: string; ts: string };

export type CajaChica = { saldoBase: number; movs: MovChica[] };
export type State = {
  v: 1;
  ciudad: Ciudad;
  config: Partial<Record<Ciudad, Config>>;
  hojas: Record<string, Hoja>;
  chica: Record<Ciudad, CajaChica>;
  outbox: Op[];
  /** Nombres usados antes como responsable: se sugieren al escribir. */
  responsables: string[];
  /** Mensajes para la persona (p. ej. "no se pudo anular"); la pantalla los muestra y los descarta. */
  avisos: { id: string; texto: string }[];
  ultimaSync?: string;
};

export type FotoRef = { key: string; mime: string; bytes: number };
export type KV = { get<T>(k: string): Promise<T | undefined>; set(k: string, v: unknown): Promise<void> };
export type StoreDeps = {
  /** Almacenamiento del dispositivo. La app NO lo usa: trabaja siempre contra el servidor y no guarda datos propios. Solo las pruebas lo usan. */
  kv?: KV;
  hoy: () => string;
  ahora?: () => string;
  borrarFoto?: (key: string) => Promise<void>;
  /** ¿Hay conexión para guardar? Sin ella la app no acepta cambios nuevos (no hay modo sin internet). */
  puedeEscribir?: () => boolean;
};

export const SIN_CONEXION = "Sin conexión: no se pudo guardar. Revisa tu internet e inténtalo de nuevo.";

const KEY = "caja.v1";

const vacio = (): State => ({
  v: 1,
  ciudad: "AQP",
  config: {},
  hojas: {},
  chica: { AQP: { saldoBase: 0, movs: [] }, MOQ: { saldoBase: 0, movs: [] } },
  outbox: [],
  responsables: [],
  avisos: [],
});

export type NuevaFila = Omit<Fila, "updated_at" | "orden" | "adjuntos"> & { orden?: number; adjuntos?: Adjunto[] };
export type NuevoMov = Omit<MovChica, "updated_at" | "adjuntos" | "tipo" | "transferencia_id"> & { adjuntos?: Adjunto[] };

export function crearStore({ kv, hoy, ahora = () => new Date().toISOString(), borrarFoto = async () => {}, puedeEscribir = () => true }: StoreDeps) {
  let state: State = vacio();
  const oyentes = new Set<() => void>();
  let temporizador: ReturnType<typeof setTimeout> | null = null;
  let guardando: Promise<void> = Promise.resolve();

  const guardar = () => {
    const snapshot = state;
    guardando = guardando.then(() => kv?.set(KEY, snapshot)).catch(() => {});
    return guardando;
  };
  /** Aplica un cambio, avisa a la pantalla y guarda en el dispositivo (con una pequeña espera para juntar cambios seguidos). */
  function commit(fn: (s: State) => void) {
    const copia: State = { ...state, hojas: { ...state.hojas }, chica: { AQP: { ...state.chica.AQP }, MOQ: { ...state.chica.MOQ } }, outbox: [...state.outbox], config: { ...state.config } };
    fn(copia);
    state = copia;
    oyentes.forEach((f) => f());
    if (temporizador) clearTimeout(temporizador);
    if (kv) temporizador = setTimeout(() => void guardar(), 150);
  }

  /** Sin conexión no se aceptan cambios nuevos: se avisa y no se toca nada. */
  const sinConexion = () => {
    if (puedeEscribir()) return false;
    commit((s) => void (s.avisos = [...s.avisos.filter((a) => a.texto !== SIN_CONEXION), { id: nuevoId(), texto: SIN_CONEXION }].slice(-5)));
    return true;
  };

  const encolar = (s: State, kind: OpKind, ref: string, data?: Op["data"], { reemplazar = false } = {}) => {
    if (reemplazar) {
      const i = s.outbox.findIndex((o) => o.kind === kind && o.ref === ref && !o.error);
      if (i >= 0) return void (s.outbox[i] = { ...s.outbox[i], data, ts: ahora() });
    }
    s.outbox.push({ id: nuevoId(), kind, ref, data, ts: ahora() });
  };
  const quitarOps = (s: State, pred: (o: Op) => boolean) => void (s.outbox = s.outbox.filter((o) => !pred(o)));
  const recordar = (s: State, nombre: string) => {
    const n = nombre.trim();
    if (n && !s.responsables.includes(n)) s.responsables = [n, ...s.responsables].slice(0, 30);
  };

  /** La hoja de ese día; si no existe la crea (abierta con el cierre del día anterior) y avisa al servidor. */
  function asegurarHoja(s: State, ciudad: Ciudad, fecha: string): Hoja {
    const key = hojaKey(ciudad, fecha);
    const ya = s.hojas[key];
    if (ya) return ya;
    const deLaCiudad = Object.values(s.hojas).filter((h) => h.ciudad === ciudad);
    const cfg = s.config[ciudad] ?? { saldo_inicial_caja: 0, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 };
    const previa = [...deLaCiudad].sort((a, b) => (a.fecha < b.fecha ? 1 : -1)).find((h) => h.fecha < fecha);
    const h: Hoja = {
      ciudad, fecha,
      responsable_caja: previa?.responsable_caja ?? "", // el responsable de ayer suele seguir siéndolo hoy
      obras_realizadas: "", maletas: "", escaleras: "", encargado_obra: "",
      ...aperturaEstimada(deLaCiudad, fecha, cfg),
      estimado: true,
      filas: [],
      updated_at: ahora(),
    };
    s.hojas[key] = h;
    encolar(s, "abrirHoja", key, { ciudad, fecha });
    return h;
  }

  function dueno(s: State, tipo: "fila" | "mov", id: string): { adjuntos: Adjunto[] } | undefined {
    if (tipo === "mov") return CIUDADES.flatMap((c) => s.chica[c].movs).find((m) => m.id === id);
    return Object.values(s.hojas).flatMap((h) => h.filas).find((f) => f.id === id);
  }

  const api = {
    // ---- lectura -----------------------------------------------------------------------------
    get: () => state,
    subscribe(fn: () => void) {
      oyentes.add(fn);
      return () => void oyentes.delete(fn);
    },
    hoja: (ciudad: Ciudad, fecha: string) => state.hojas[hojaKey(ciudad, fecha)],

    // ---- ciclo de vida -----------------------------------------------------------------------
    async init() {
      const guardado = await kv?.get<State>(KEY);
      if (guardado?.v === 1) state = { ...vacio(), ...guardado, chica: { ...vacio().chica, ...guardado.chica } };
      oyentes.forEach((f) => f());
    },
    /** Espera a que lo último quede escrito en el dispositivo (para las pruebas y antes de cerrar). */
    async vaciar() {
      if (temporizador) {
        clearTimeout(temporizador);
        temporizador = null;
        await guardar();
      }
      await guardando;
    },
    /** Cierre de sesión: borra todo lo del dispositivo (lo pendiente de enviar se pierde, por eso la pantalla avisa antes). */
    async reiniciar() {
      state = vacio();
      oyentes.forEach((f) => f());
      await kv?.set(KEY, state);
    },

    /** ¿Hay conexión para guardar cambios? (las pantallas lo usan para avisar antes de dejar escribir) */
    puedeEscribir: () => puedeEscribir(),
    setCiudad: (ciudad: Ciudad) => commit((s) => void (s.ciudad = ciudad)),
    abrirHoja: (ciudad: Ciudad, fecha: string) => commit((s) => void asegurarHoja(s, ciudad, fecha)),

    // ---- hoja del día ------------------------------------------------------------------------
    patchHoja(ciudad: Ciudad, fecha: string, patch: Partial<Pick<Hoja, "responsable_caja" | "obras_realizadas" | "maletas" | "escaleras" | "encargado_obra">>) {
      if (sinConexion()) return;
      commit((s) => {
        const h = asegurarHoja(s, ciudad, fecha);
        const key = hojaKey(ciudad, fecha);
        s.hojas[key] = { ...h, ...patch, updated_at: ahora() };
        if (patch.responsable_caja) recordar(s, patch.responsable_caja);
        encolar(s, "patchHoja", key, { ciudad, fecha }, { reemplazar: true });
      });
    },

    guardarFila(ciudad: Ciudad, fecha: string, f: NuevaFila) {
      if (sinConexion()) return;
      commit((s) => {
        const h = asegurarHoja(s, ciudad, fecha);
        const key = hojaKey(ciudad, fecha);
        const existente = h.filas.find((x) => x.id === f.id);
        const orden = f.orden ?? existente?.orden ?? Math.max(0, ...h.filas.map((x) => x.orden)) + 1;
        const fila: Fila = { ...f, orden, adjuntos: f.adjuntos ?? existente?.adjuntos ?? [], transferencia_id: f.transferencia_id ?? existente?.transferencia_id ?? null, updated_at: ahora(), version: existente?.version };
        s.hojas[key] = { ...h, filas: existente ? h.filas.map((x) => (x.id === f.id ? { ...fila, servidor: x.servidor } : x)) : [...h.filas, fila] };
        recordar(s, f.responsable);
        quitarOps(s, (o) => o.kind === "putFila" && o.ref === f.id && !!o.error); // al corregirla, desaparece el error anterior
        encolar(s, "putFila", f.id, { ciudad, fecha }, { reemplazar: true });
      });
    },

    borrarFila(ciudad: Ciudad, fecha: string, id: string) {
      if (sinConexion()) return;
      commit((s) => {
        const key = hojaKey(ciudad, fecha);
        const h = s.hojas[key];
        const fila = h?.filas.find((f) => f.id === id);
        if (!h || !fila) return;
        s.hojas[key] = { ...h, filas: h.filas.filter((f) => f.id !== id) };
        const nuncaLlego = !fila.servidor && s.outbox.some((o) => o.kind === "putFila" && o.ref === id);
        const fotos = new Set(fila.adjuntos.map((a) => a.id));
        quitarOps(s, (o) => (o.kind === "putFila" && o.ref === id) || ((o.kind === "putAdjunto" || o.kind === "delAdjunto") && fotos.has(o.ref)));
        if (!nuncaLlego) encolar(s, "delFila", id, { ciudad, fecha });
        for (const a of fila.adjuntos) if (a.localKey) void borrarFoto(a.localKey);
      });
    },

    // ---- fotos de recibos --------------------------------------------------------------------
    agregarAdjunto(tipo: "fila" | "mov", ownerId: string, foto: FotoRef, nombre?: string): string | null {
      if (sinConexion()) return null;
      let id: string | null = null;
      commit((s) => {
        const d = dueno(s, tipo, ownerId);
        if (!d) return;
        id = nuevoId();
        d.adjuntos.push({ id, mime: foto.mime, bytes: foto.bytes, nombre, localKey: foto.key, synced: false });
        encolar(s, "putAdjunto", id, { tipo, ownerId });
      });
      return id;
    },
    quitarAdjunto(tipo: "fila" | "mov", ownerId: string, adjId: string) {
      if (sinConexion()) return;
      commit((s) => {
        const d = dueno(s, tipo, ownerId);
        const a = d?.adjuntos.find((x) => x.id === adjId);
        if (!d || !a) return;
        d.adjuntos.splice(d.adjuntos.indexOf(a), 1);
        quitarOps(s, (o) => o.kind === "putAdjunto" && o.ref === adjId);
        if (a.synced) encolar(s, "delAdjunto", adjId);
        if (a.localKey) void borrarFoto(a.localKey);
      });
    },

    // ---- caja chica --------------------------------------------------------------------------
    guardarMov(m: NuevoMov) {
      if (sinConexion()) return;
      commit((s) => {
        const lista = s.chica[m.ciudad].movs;
        const existente = lista.find((x) => x.id === m.id);
        const mov: MovChica = { ...m, tipo: "EGRESO", transferencia_id: null, adjuntos: m.adjuntos ?? existente?.adjuntos ?? [], updated_at: ahora(), version: existente?.version };
        s.chica[m.ciudad] = { ...s.chica[m.ciudad], movs: existente ? lista.map((x) => (x.id === m.id ? { ...mov, servidor: x.servidor } : x)) : [...lista, mov] };
        recordar(s, m.persona);
        quitarOps(s, (o) => o.kind === "putMov" && o.ref === m.id && !!o.error);
        encolar(s, "putMov", m.id, { ciudad: m.ciudad }, { reemplazar: true });
      });
    },
    borrarMov(ciudad: Ciudad, id: string) {
      if (sinConexion()) return;
      commit((s) => {
        const m = s.chica[ciudad].movs.find((x) => x.id === id);
        if (!m || m.tipo !== "EGRESO") return;
        s.chica[ciudad] = { ...s.chica[ciudad], movs: s.chica[ciudad].movs.filter((x) => x.id !== id) };
        const nuncaLlego = !m.servidor && s.outbox.some((o) => o.kind === "putMov" && o.ref === id);
        const fotos = new Set(m.adjuntos.map((a) => a.id));
        quitarOps(s, (o) => (o.kind === "putMov" && o.ref === id) || ((o.kind === "putAdjunto" || o.kind === "delAdjunto") && fotos.has(o.ref)));
        if (!nuncaLlego) encolar(s, "delMov", id, { ciudad });
        for (const a of m.adjuntos) if (a.localKey) void borrarFoto(a.localKey);
      });
    },

    // ---- de la caja diaria a la caja chica ---------------------------------------------------
    enviarACajaChica(p: { ciudad: Ciudad; fecha: string; monto: number; nota: string; responsable: string }) {
      if (sinConexion()) return "";
      const id = nuevoId();
      const filaId = nuevoId();
      const movId = nuevoId();
      commit((s) => {
        const h = asegurarHoja(s, p.ciudad, p.fecha);
        const key = hojaKey(p.ciudad, p.fecha);
        const fila: Fila = {
          id: filaId, orden: Math.max(0, ...h.filas.map((x) => x.orden)) + 1, tipo: "OTRO",
          descripcion: p.nota ? `Envío a caja chica · ${p.nota}` : "Envío a caja chica", responsable: p.responsable, comprobante: "NINGUNO",
          caja_ingreso_efectivo: 0, caja_ingreso_transf: 0, caja_salida_efectivo: p.monto, caja_salida_transf: 0, cta_cte_ingreso: 0, cta_cte_salida: 0,
          categoria: "", subcategoria: "", interno: true, transferencia_id: id, adjuntos: [], updated_at: ahora(),
        };
        s.hojas[key] = { ...h, filas: [...h.filas, fila] };
        const mov: MovChica = {
          id: movId, ciudad: p.ciudad, fecha: p.fecha, tipo: "TRANSFERENCIA", descripcion: p.nota ? `Recibido de caja diaria · ${p.nota}` : "Recibido de caja diaria", persona: p.responsable,
          categoria: "", subcategoria: "", monto: p.monto, origen: "TRANSFERENCIA", transferencia_id: id, adjuntos: [], updated_at: ahora(),
        };
        s.chica[p.ciudad] = { ...s.chica[p.ciudad], movs: [...s.chica[p.ciudad].movs, mov] };
        encolar(s, "transfer", id, { id, fila_id: filaId, movimiento_id: movId, ciudad: p.ciudad, fecha: p.fecha, monto: p.monto, nota: p.nota });
      });
      return id;
    },
    anularTransferencia(ciudad: Ciudad, fecha: string, id: string) {
      if (sinConexion()) return;
      commit((s) => {
        const key = hojaKey(ciudad, fecha);
        const h = s.hojas[key];
        if (h) s.hojas[key] = { ...h, filas: h.filas.filter((f) => f.transferencia_id !== id) };
        s.chica[ciudad] = { ...s.chica[ciudad], movs: s.chica[ciudad].movs.filter((m) => m.transferencia_id !== id) };
        const nuncaLlego = s.outbox.some((o) => o.kind === "transfer" && o.ref === id);
        quitarOps(s, (o) => o.kind === "transfer" && o.ref === id);
        if (!nuncaLlego) encolar(s, "delTransfer", id, { ciudad, fecha });
      });
    },

    setConfig(ciudad: Ciudad, cfg: Config) {
      if (sinConexion()) return;
      commit((s) => {
        s.config[ciudad] = cfg;
        encolar(s, "putConfig", ciudad, { ciudad }, { reemplazar: true });
      });
    },

    // ---- usados por sync.ts ------------------------------------------------------------------
    /** Aplica un cambio de estado hecho por el motor de sincronización (no genera operaciones nuevas). */
    mutar: commit,
    avisar: (texto: string) => commit((s) => void (s.avisos = [...s.avisos, { id: nuevoId(), texto }].slice(-5))),
    quitarAviso: (id: string) => commit((s) => void (s.avisos = s.avisos.filter((a) => a.id !== id))),
    quitarOp: (opId: string) => commit((s) => void (s.outbox = s.outbox.filter((o) => o.id !== opId))),
    marcarError: (opId: string, error: string) => commit((s) => void (s.outbox = s.outbox.map((o) => (o.id === opId ? { ...o, error } : o)))),
    reintentarErrores: () => commit((s) => void (s.outbox = s.outbox.map((o) => (o.error ? { ...o, error: undefined } : o)))),
  };
  return api;
}

export type Store = ReturnType<typeof crearStore>;

// ---- consultas sobre el estado (puras) --------------------------------------------------------

export const pendientes = (s: State) => s.outbox.filter((o) => !o.error).length;
export const conError = (s: State) => s.outbox.filter((o) => !!o.error);
/** ¿Esta fila/movimiento/foto todavía no llegó al servidor? */
export const sinEnviar = (s: State, id: string) => s.outbox.some((o) => o.ref === id && !o.error);
export const errorDe = (s: State, id: string) => s.outbox.find((o) => o.ref === id && o.error)?.error;

export const saldosDe = (h: Hoja) => saldosHoja(h);
export const saldoCajaChica = (s: State, ciudad: Ciudad) => saldoChica(s.chica[ciudad].saldoBase, s.chica[ciudad].movs);
/** Saldo de la caja diaria "ahora": el cierre de la hoja más reciente (o el inicial de la ciudad). */
export function saldoCaja(s: State, ciudad: Ciudad) {
  const ult = Object.values(s.hojas).filter((h) => h.ciudad === ciudad).sort((a, b) => (a.fecha < b.fecha ? 1 : -1))[0];
  const cfg = s.config[ciudad];
  if (!ult) return { caja: cfg?.saldo_inicial_caja ?? 0, cta_cte: cfg?.saldo_inicial_cta_cte ?? 0 };
  const x = saldosHoja(ult);
  return { caja: x.saldo_final_caja, cta_cte: x.saldo_final_cta_cte };
}
