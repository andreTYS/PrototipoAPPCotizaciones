/**
 * Motor de sincronización: manda al servidor lo que la persona acaba de hacer (en el orden en que ocurrió) y trae
 * lo que hayan hecho las demás personas. La app trabaja SIEMPRE conectada: los datos son los del servidor y varias
 * personas pueden usarla a la vez. Cada pocos segundos consulta una versión muy liviana (`/caja/version`) y solo
 * vuelve a bajar los datos cuando algo cambió.
 *
 * - Un corte de internet momentáneo → lo que se estaba enviando se reintenta al volver (mientras la pestaña siga
 *   abierta); mientras no hay conexión la pantalla no acepta cambios nuevos (ver store.puedeEscribir).
 * - El servidor rechaza una operación (4xx) → queda marcada con su mensaje, visible en esa fila, y las demás
 *   siguen. Si el motivo es que otra persona cambió o cerró lo mismo, se descarta el cambio y se muestra lo último.
 * - Sin dependencias de React Native (la API y las fotos se inyectan) para probarlo con Node contra la API real.
 */
import { isoDate, parseIso } from "../format";
import { fusionarHoja, fusionarMovs, type Pendientes } from "./calc";
import { conError, type Op, type Store } from "./store";
import { CIUDADES, hojaKey, type Cierre, type Ciudad, type Fila, type Hoja, type MovChica } from "./types";

export type SyncApi = {
  json<T = any>(method: string, path: string, body?: unknown): Promise<T>;
  subirFoto(path: string, blob: Blob): Promise<void>;
  bajarFoto(path: string): Promise<Blob>;
};
export type SyncDeps = { store: Store; api: SyncApi; blobFoto: (key: string) => Promise<Blob | null>; hoy: () => string; ventanaDias?: number };

/**
 * Rechazos que no se arreglan reintentando ni corrigiendo la fila: otra persona cambió lo mismo, el día se cerró o el
 * rol no alcanza. El cambio se descarta y la persona ve lo que quedó en el servidor, con el motivo.
 */
const CODIGOS_DESCARTE = new Set(["CAMBIO_CONCURRENTE", "DIA_CERRADO", "DIA_POSTERIOR_CERRADO", "SIN_PERMISO", "SIN_ACCESO"]);

export type Fase = "inactivo" | "sincronizando" | "sin-conexion" | "sesion-vencida";
export type EstadoSync = { fase: Fase; ultimoOk?: string };

type ErrorApi = { status?: number; code?: string; message?: string };
const esSinRed = (e: unknown) => {
  const x = e as ErrorApi;
  return x?.status === 0 || x?.code === "NETWORK" || (typeof x?.status === "number" && x.status >= 500);
};

export function crearSync({ store, api, blobFoto, hoy, ventanaDias = 45 }: SyncDeps) {
  let estado: EstadoSync = { fase: "inactivo" };
  const oyentes = new Set<() => void>();
  const poner = (e: Partial<EstadoSync>) => {
    estado = { ...estado, ...e };
    oyentes.forEach((f) => f());
  };
  let corriendo: Promise<void> | null = null;
  let otraVez = false;
  let forzarProximo = false;
  /** Versión de la caja en el servidor la última vez que se bajaron los datos. */
  let versionConocida: string | undefined;

  /** Id que el servidor le dio a la hoja; si todavía no la abrió, la abre ahora. */
  async function idDeHoja(ciudad: Ciudad, fecha: string): Promise<string> {
    const key = hojaKey(ciudad, fecha);
    const h = store.get().hojas[key];
    if (h?.id) return h.id;
    const r = await api.json<{ hoja: Hoja }>("POST", "/caja/hojas/abrir", { ciudad, fecha });
    aplicarApertura(key, r.hoja);
    return r.hoja.id!;
  }
  function aplicarApertura(key: string, sh: Hoja) {
    store.mutar((s) => {
      const local = s.hojas[key];
      if (!local) return;
      s.hojas[key] = { ...local, id: sh.id, saldo_anterior_caja: sh.saldo_anterior_caja, saldo_anterior_cta_cte: sh.saldo_anterior_cta_cte, estimado: false, version: sh.version, cierre: sh.cierre ?? null };
    });
  }
  const marcarServidor = (filaIds: string[], movIds: string[]) =>
    store.mutar((s) => {
      for (const [k, h] of Object.entries(s.hojas)) if (h.filas.some((f) => filaIds.includes(f.id))) s.hojas[k] = { ...h, filas: h.filas.map((f) => (filaIds.includes(f.id) ? { ...f, servidor: true } : f)) };
      for (const c of CIUDADES) if (s.chica[c].movs.some((m) => movIds.includes(m.id))) s.chica[c] = { ...s.chica[c], movs: s.chica[c].movs.map((m) => (movIds.includes(m.id) ? { ...m, servidor: true } : m)) };
    });

  const buscarFila = (ciudad: Ciudad, fecha: string, id: string): Fila | undefined => store.get().hojas[hojaKey(ciudad, fecha)]?.filas.find((f) => f.id === id);
  const buscarMov = (ciudad: Ciudad, id: string): MovChica | undefined => store.get().chica[ciudad].movs.find((m) => m.id === id);

  async function ejecutar(op: Op): Promise<void> {
    const d = op.data ?? {};
    switch (op.kind) {
      case "abrirHoja": {
        const h = store.get().hojas[op.ref];
        const r = await api.json<{ hoja: Hoja }>("POST", "/caja/hojas/abrir", { ciudad: d.ciudad, fecha: d.fecha, id: h?.id });
        return aplicarApertura(op.ref, r.hoja);
      }
      case "patchHoja": {
        const h = store.get().hojas[op.ref];
        if (!h) return;
        const id = await idDeHoja(d.ciudad, d.fecha);
        await api.json("PATCH", `/caja/hojas/${id}`, { responsable_caja: h.responsable_caja, obras_realizadas: h.obras_realizadas, maletas: h.maletas, escaleras: h.escaleras, encargado_obra: h.encargado_obra, version: h.version });
        return;
      }
      case "putFila": {
        const f = buscarFila(d.ciudad, d.fecha, op.ref);
        if (!f) return; // la borraron antes de que saliera
        const hojaId = await idDeHoja(d.ciudad, d.fecha);
        await api.json("PUT", `/caja/filas/${f.id}`, {
          hoja_id: hojaId, orden: f.orden, tipo: f.tipo, descripcion: f.descripcion, responsable: f.responsable, comprobante: f.comprobante,
          caja_ingreso_efectivo: f.caja_ingreso_efectivo, caja_ingreso_transf: f.caja_ingreso_transf, caja_salida_efectivo: f.caja_salida_efectivo, caja_salida_transf: f.caja_salida_transf,
          cta_cte_ingreso: f.cta_cte_ingreso, cta_cte_salida: f.cta_cte_salida, categoria: f.categoria, subcategoria: f.subcategoria, interno: f.interno,
          version: f.servidor ? f.version : undefined,
        });
        return marcarServidor([f.id], []);
      }
      case "delFila":
        return void (await api.json("DELETE", `/caja/filas/${op.ref}`));
      case "putMov": {
        const m = buscarMov(d.ciudad, op.ref);
        if (!m) return;
        await api.json("PUT", `/caja-chica/movimientos/${m.id}`, { ciudad: m.ciudad, fecha: m.fecha, descripcion: m.descripcion, persona: m.persona, categoria: m.categoria, subcategoria: m.subcategoria, monto: m.monto, origen: m.origen, version: m.servidor ? m.version : undefined });
        return marcarServidor([], [m.id]);
      }
      case "delMov":
        return void (await api.json("DELETE", `/caja-chica/movimientos/${op.ref}`));
      case "transfer":
        await api.json("POST", "/caja/transferencias", d);
        return marcarServidor([d.fila_id], [d.movimiento_id]);
      case "delTransfer":
        return void (await api.json("DELETE", `/caja/transferencias/${op.ref}`));
      case "putAdjunto": {
        const s = store.get();
        const lista = d.tipo === "fila" ? Object.values(s.hojas).flatMap((h) => h.filas) : CIUDADES.flatMap((c) => s.chica[c].movs);
        const adj = lista.find((x) => x.id === d.ownerId)?.adjuntos.find((a) => a.id === op.ref);
        if (!adj) return; // la quitaron antes de subirse
        const blob = adj.localKey ? await blobFoto(adj.localKey) : null;
        if (!blob) throw Object.assign(new Error("La foto ya no está en este dispositivo."), { status: 400, code: "FOTO_PERDIDA" });
        await api.subirFoto(`/caja/adjuntos/${adj.id}?${d.tipo === "fila" ? "fila_id" : "movimiento_id"}=${d.ownerId}`, blob);
        return store.mutar((st) => {
          for (const h of Object.values(st.hojas)) for (const f of h.filas) for (const a of f.adjuntos) if (a.id === adj.id) a.synced = true;
          for (const c of CIUDADES) for (const m of st.chica[c].movs) for (const a of m.adjuntos) if (a.id === adj.id) a.synced = true;
        });
      }
      case "delAdjunto":
        return void (await api.json("DELETE", `/caja/adjuntos/${op.ref}`));
      case "putConfig": {
        const c = store.get().config[d.ciudad as Ciudad];
        if (!c) return;
        await api.json("PUT", `/caja/config/${d.ciudad}`, c);
        return;
      }
    }
  }

  /** Manda la cola. Devuelve false si se cortó por falta de conexión. */
  async function enviar(): Promise<boolean> {
    const bloqueados = new Set<string>(); // lo que falló: sus fotos esperan en vez de fallar también
    for (const op of [...store.get().outbox]) {
      if (op.error) {
        bloqueados.add(op.ref);
        continue;
      }
      if ((op.kind === "putAdjunto" || op.kind === "delAdjunto") && bloqueados.has(op.data?.ownerId)) continue;
      try {
        await ejecutar(op);
        store.quitarOp(op.id);
      } catch (e) {
        const err = e as ErrorApi;
        if (err.status === 401) {
          poner({ fase: "sesion-vencida" });
          return false;
        }
        if (esSinRed(e)) {
          poner({ fase: "sin-conexion" });
          return false;
        }
        // El servidor dice que eso ya fue eliminado allá: se quita también aquí y se sigue.
        if (err.code === "FILA_ELIMINADA" || err.code === "MOVIMIENTO_ELIMINADO") {
          quitarLocal(op);
          store.quitarOp(op.id);
          continue;
        }
        // Otra persona cambió o cerró lo mismo (o el rol no alcanza): se descarta el cambio y se vuelve a bajar lo del servidor.
        if (err.code && CODIGOS_DESCARTE.has(err.code)) {
          quitarLocal(op);
          store.quitarOp(op.id);
          store.avisar(err.message ?? "El servidor no aceptó el cambio.");
          forzarProximo = true;
          continue;
        }
        // Una anulación o un borrado rechazado no se puede dejar "oculto": se quita de la cola, el siguiente
        // paso del ciclo vuelve a traer el elemento del servidor y se le explica a la persona por qué.
        if (op.kind === "delFila" || op.kind === "delMov" || op.kind === "delTransfer" || op.kind === "delAdjunto") {
          store.quitarOp(op.id);
          store.avisar(err.message ?? "El servidor no permitió borrar eso.");
          continue;
        }
        store.marcarError(op.id, err.message ?? "El servidor rechazó el cambio.");
        bloqueados.add(op.ref);
      }
    }
    return true;
  }

  /** Quita de la pantalla lo que se intentó guardar y el servidor no aceptó (si ya existía allá, vuelve al bajar los datos). */
  function quitarLocal(op: Op) {
    store.mutar((s) => {
      if (op.kind === "putFila") for (const [k, h] of Object.entries(s.hojas)) s.hojas[k] = { ...h, filas: h.filas.filter((f) => f.id !== op.ref || f.servidor) };
      if (op.kind === "putMov") for (const c of CIUDADES) s.chica[c] = { ...s.chica[c], movs: s.chica[c].movs.filter((m) => m.id !== op.ref || m.servidor) };
      if (op.kind === "putAdjunto") {
        for (const [k, h] of Object.entries(s.hojas)) s.hojas[k] = { ...h, filas: h.filas.map((f) => ({ ...f, adjuntos: f.adjuntos.filter((a) => a.id !== op.ref || a.synced) })) };
        for (const c of CIUDADES) s.chica[c] = { ...s.chica[c], movs: s.chica[c].movs.map((m) => ({ ...m, adjuntos: m.adjuntos.filter((a) => a.id !== op.ref || a.synced) })) };
      }
      if (op.kind === "transfer") {
        const d = op.data ?? {};
        for (const [k, h] of Object.entries(s.hojas)) s.hojas[k] = { ...h, filas: h.filas.filter((f) => f.id !== d.fila_id) };
        for (const c of CIUDADES) s.chica[c] = { ...s.chica[c], movs: s.chica[c].movs.filter((m) => m.id !== d.movimiento_id) };
      }
    });
  }

  const restarDias = (fecha: string, n: number) => {
    const d = parseIso(fecha);
    d.setDate(d.getDate() - n);
    return isoDate(d);
  };

  /** Trae del servidor las hojas y movimientos recientes de una ciudad y los une con lo local. */
  async function traer(ciudad: Ciudad) {
    const hasta = hoy();
    const desde = restarDias(hasta, ventanaDias);
    const q = `ciudad=${ciudad}&desde=${desde}&hasta=${hasta}`;
    const [hojasR, chicaR, estadoR] = await Promise.all([
      api.json<{ hojas: Hoja[] }>("GET", `/caja/hojas?${q}`),
      api.json<{ saldo_anterior: number; movimientos: MovChica[] }>("GET", `/caja-chica/movimientos?${q}`),
      api.json<{ config: any }>("GET", `/caja/estado?ciudad=${ciudad}`),
    ]);
    store.mutar((s) => {
      const ops = s.outbox;
      const refs = (k: Op["kind"]) => new Set(ops.filter((o) => o.kind === k).map((o) => o.ref));
      const transferenciasAnuladas = refs("delTransfer");
      const transferenciasNuevas = ops.filter((o) => o.kind === "transfer");
      const p: Pendientes = {
        filasPendientes: new Set([...refs("putFila"), ...transferenciasNuevas.map((o) => o.data!.fila_id as string)]),
        filasBorradas: refs("delFila"),
        adjuntosBorrados: refs("delAdjunto"),
        hojaSucia: false,
      };
      for (const sh of hojasR.hojas) {
        const key = hojaKey(ciudad, sh.fecha);
        const aBorrar = new Set(p.filasBorradas);
        for (const f of sh.filas) if (f.transferencia_id && transferenciasAnuladas.has(f.transferencia_id)) aBorrar.add(f.id);
        const fusion = fusionarHoja(s.hojas[key], sh, { ...p, filasBorradas: aBorrar, hojaSucia: ops.some((o) => o.kind === "patchHoja" && o.ref === key) });
        const enServidor = new Set(sh.filas.map((f) => f.id));
        s.hojas[key] = { ...fusion, filas: fusion.filas.map((f) => (enServidor.has(f.id) ? { ...f, servidor: true } : f)) };
      }
      const movsPend = new Set([...refs("putMov"), ...transferenciasNuevas.map((o) => o.data!.movimiento_id as string)]);
      const movsBorrados = refs("delMov");
      for (const m of chicaR.movimientos) if (m.transferencia_id && transferenciasAnuladas.has(m.transferencia_id)) movsBorrados.add(m.id);
      const movs = fusionarMovs(s.chica[ciudad].movs, chicaR.movimientos, movsPend, movsBorrados);
      const enServidorM = new Set(chicaR.movimientos.map((m) => m.id));
      s.chica[ciudad] = { saldoBase: chicaR.saldo_anterior, movs: movs.map((m) => (enServidorM.has(m.id) ? { ...m, servidor: true } : m)) };
      if (!ops.some((o) => o.kind === "putConfig" && o.ref === ciudad)) s.config[ciudad] = estadoR.config;
      s.ultimaSync = new Date().toISOString();
    });
  }

  async function ciclo(forzar: boolean) {
    poner({ fase: "sincronizando" });
    const habiaPendientes = store.get().outbox.length > 0;
    if (!(await enviar())) return;
    try {
      // ¿Cambió algo en el servidor? Una consulta muy liviana evita bajar todos los datos cada pocos segundos.
      const { version } = await api.json<{ version: string }>("GET", "/caja/version");
      if (forzar || forzarProximo || habiaPendientes || version !== versionConocida) {
        forzarProximo = false;
        for (const c of CIUDADES) await traer(c);
        // Se vuelve a consultar: si alguien escribió mientras se bajaba, la próxima vuelta lo trae.
        versionConocida = version;
      }
    } catch (e) {
      if ((e as ErrorApi).status === 401) return void poner({ fase: "sesion-vencida" });
      if (esSinRed(e)) return void poner({ fase: "sin-conexion" });
      throw e;
    }
    poner({ fase: "inactivo", ultimoOk: new Date().toISOString() });
  }

  return {
    estado: () => estado,
    subscribe(fn: () => void) {
      oyentes.add(fn);
      return () => void oyentes.delete(fn);
    },
    /**
     * Envía lo pendiente y trae lo nuevo (solo si cambió algo en el servidor; `forzar` baja todo igual).
     * Si ya hay una en curso, pide otra al terminar (no se pisan).
     */
    sincronizar(forzar = false): Promise<void> {
      if (corriendo) {
        otraVez = true;
        if (forzar) forzarProximo = true;
        return corriendo;
      }
      corriendo = (async () => {
        try {
          let primera = forzar;
          do {
            otraVez = false;
            await ciclo(primera);
            primera = false;
          } while (otraVez);
        } catch (e) {
          poner({ fase: "inactivo" });
          console.error("Error de sincronización:", e);
        } finally {
          corriendo = null;
        }
      })();
      return corriendo;
    },
    /**
     * Cierra el día: manda lo pendiente, y con el efectivo contado el servidor guarda la diferencia con el saldo
     * calculado y bloquea el día. Hace falta conexión y que no quede nada sin enviar (el cierre tiene que ser exacto).
     */
    async cerrarHoja(ciudad: Ciudad, fecha: string, efectivoContado: number, nota: string): Promise<Cierre> {
      await this.sincronizar(true);
      if (store.get().outbox.length) throw Object.assign(new Error("Hay cambios sin enviar o sin guardar en esta caja. Resuélvelos antes de cerrar el día."), { code: "PENDIENTES" });
      const key = hojaKey(ciudad, fecha);
      const id = await idDeHoja(ciudad, fecha);
      const r = await api.json<{ hoja: Hoja }>("POST", `/caja/hojas/${id}/cerrar`, { efectivo_contado: efectivoContado, nota });
      store.mutar((s) => {
        if (s.hojas[key]) s.hojas[key] = { ...s.hojas[key], version: r.hoja.version, cierre: r.hoja.cierre ?? null };
      });
      void this.sincronizar(true);
      return r.hoja.cierre!;
    },

    /** Reabre un día cerrado (solo administrador); el motivo queda en el historial de cambios. */
    async reabrirHoja(ciudad: Ciudad, fecha: string, motivo: string): Promise<void> {
      const key = hojaKey(ciudad, fecha);
      const id = await idDeHoja(ciudad, fecha);
      const r = await api.json<{ hoja: Hoja }>("POST", `/caja/hojas/${id}/reabrir`, { motivo });
      store.mutar((s) => {
        if (s.hojas[key]) s.hojas[key] = { ...s.hojas[key], version: r.hoja.version, cierre: null };
      });
      void this.sincronizar(true);
    },

    /** Reintenta también las operaciones que el servidor había rechazado (después de que la persona las corrigió). */
    reintentarTodo() {
      store.reintentarErrores();
      return this.sincronizar(true);
    },
    errores: () => conError(store.get()),
    /** Foto de otra persona (o de este dispositivo): URL lista para mostrar. */
    traerFotoRemota: (adjId: string) => api.bajarFoto(`/caja/adjuntos/${adjId}`),
  };
}

export type Sync = ReturnType<typeof crearSync>;
