/**
 * Reglas de negocio de la Caja diaria y la Caja chica. Sin HTTP: recibe y devuelve objetos, así se prueba
 * directo y se puede reutilizar tal cual (o portar) dentro del ERP.
 */
import { randomUUID } from "node:crypto";
import type { Db } from "./db";
import { ApiError, type Usuario } from "./auth";
import { crearPermisos, type Permisos } from "./permisos";
import type { Storage } from "./storage";
import { payloadDeMovChica, payloadsDeFila, type ErpMirror } from "./erp";
import { r2, totalesHoja, validarFila } from "../../app/src/lib/caja/calc";
import { CIUDADES, COMPROBANTES, TIPOS_FILA, type Ciudad, type Fila } from "../../app/src/lib/caja/types";
import { CATS, SUBCATS } from "../../app/src/lib/data";

type Row = Record<string, any>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MIMES = ["image/jpeg", "image/png", "image/webp"];
const MAX_FOTO = 10 * 1024 * 1024;

const bad = (message: string, code = "DATOS_INVALIDOS") => new ApiError(400, code, message);

const uuid = (v: unknown, campo: string) => {
  if (typeof v !== "string" || !UUID.test(v)) throw bad(`${campo} debe ser un UUID.`);
  return v.toLowerCase();
};
const ciudadDe = (v: unknown): Ciudad => {
  if (!CIUDADES.includes(v as Ciudad)) throw bad(`ciudad debe ser ${CIUDADES.join(" o ")}.`);
  return v as Ciudad;
};
const fechaDe = (v: unknown, campo = "fecha") => {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v) || isNaN(Date.parse(v + "T00:00:00Z")) || new Date(v + "T00:00:00Z").toISOString().slice(0, 10) !== v)
    throw bad(`${campo} debe tener el formato AAAA-MM-DD.`);
  return v;
};
const importe = (v: unknown, campo: string, { positivo = false } = {}) => {
  const n = v == null || v === "" ? 0 : Number(v);
  if (!Number.isFinite(n) || n < 0 || n > 999_999_999) throw bad(`${campo} no es un importe válido.`);
  if (positivo && n <= 0) throw bad(`${campo} debe ser mayor a 0.`);
  return r2(n);
};
const texto = (v: unknown, max = 500) => (typeof v === "string" ? v.trim().slice(0, max) : "");

/** Fecha de hoy en Perú (UTC-5, sin horario de verano). */
export const hoyLima = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());

const iso = (d: unknown) => (d ? new Date(d as string).toISOString() : "");
const nullable = (v: unknown) => (v == null || v === "" ? null : String(v));

const COLS_FILA = `f.id, f.hoja_id, f.orden, f.tipo, f.descripcion, f.responsable, f.comprobante,
  f.caja_ingreso_efectivo::float8 AS caja_ingreso_efectivo, f.caja_ingreso_transf::float8 AS caja_ingreso_transf,
  f.caja_salida_efectivo::float8 AS caja_salida_efectivo, f.caja_salida_transf::float8 AS caja_salida_transf,
  f.cta_cte_ingreso::float8 AS cta_cte_ingreso, f.cta_cte_salida::float8 AS cta_cte_salida,
  f.categoria, f.subcategoria, f.interno, f.transferencia_id, f.ingreso_erp_id, f.gasto_erp_id, f.erp_pendiente, f.erp_error, f.updated_at, f.version`;

const COLS_MOV = `m.id, m.ciudad, m.fecha::text AS fecha, m.tipo, m.descripcion, m.persona, m.categoria, m.subcategoria,
  m.monto::float8 AS monto, m.origen, m.transferencia_id, m.gasto_erp_id, m.erp_pendiente, m.erp_error, m.updated_at, m.version`;

const adjuntoDe = (a: Row) => ({ id: a.id, mime: a.mime, bytes: a.bytes, nombre: a.nombre ?? undefined, synced: true });
const filaDe = (r: Row, adjuntos: Row[] = []) => ({
  id: r.id, hoja_id: r.hoja_id, orden: r.orden, tipo: r.tipo, descripcion: r.descripcion, responsable: r.responsable, comprobante: r.comprobante,
  caja_ingreso_efectivo: r.caja_ingreso_efectivo, caja_ingreso_transf: r.caja_ingreso_transf, caja_salida_efectivo: r.caja_salida_efectivo, caja_salida_transf: r.caja_salida_transf,
  cta_cte_ingreso: r.cta_cte_ingreso, cta_cte_salida: r.cta_cte_salida,
  categoria: r.categoria ?? "", subcategoria: r.subcategoria ?? "", interno: r.interno, transferencia_id: r.transferencia_id ?? null,
  erp_pendiente: !!r.erp_pendiente, erp_error: r.erp_error ?? null, updated_at: iso(r.updated_at), version: r.version,
  adjuntos: adjuntos.filter((a) => a.fila_id === r.id).map(adjuntoDe),
});
const movDe = (r: Row, adjuntos: Row[] = []) => ({
  id: r.id, ciudad: r.ciudad, fecha: r.fecha, tipo: r.tipo, descripcion: r.descripcion, persona: r.persona, categoria: r.categoria ?? "", subcategoria: r.subcategoria ?? "",
  monto: r.monto, origen: r.origen, transferencia_id: r.transferencia_id ?? null, erp_pendiente: !!r.erp_pendiente, erp_error: r.erp_error ?? null, updated_at: iso(r.updated_at), version: r.version,
  adjuntos: adjuntos.filter((a) => a.movimiento_id === r.id).map(adjuntoDe),
});

const CIUDAD_LABEL_SRV: Record<string, string> = { AQP: "Arequipa", MOQ: "Moquegua" };

/** Lo esencial de una hoja para el tablero. */
const resumenHoja = (h: any) => ({
  id: h.id, fecha: h.fecha as string, movimientos: h.filas.length as number,
  ingresos: h.totales.caja.ingreso as number, salidas: h.totales.caja.salida as number,
  saldo_final_caja: h.saldo_final_caja as number, saldo_final_cta_cte: h.saldo_final_cta_cte as number, cierre: h.cierre as null | { cerrada_por: string; diferencia: number },
});

export type Deps = { db: Db; storage: Storage; mirror: ErpMirror; env?: NodeJS.ProcessEnv; hoy?: () => string; permisos?: Permisos };

/** Los datos del negocio de una fila (lo que se compara en el historial de cambios). */
const NEGOCIO_FILA = ["tipo", "descripcion", "responsable", "comprobante", "caja_ingreso_efectivo", "caja_ingreso_transf", "caja_salida_efectivo", "caja_salida_transf", "cta_cte_ingreso", "cta_cte_salida", "categoria", "subcategoria", "interno"] as const;
const NEGOCIO_MOV = ["fecha", "descripcion", "persona", "categoria", "subcategoria", "monto", "origen"] as const;
const PIE_HOJA = ["responsable_caja", "obras_realizadas", "maletas", "escaleras", "encargado_obra"] as const;
const tomar = (r: Row | undefined, claves: readonly string[]) => (r ? Object.fromEntries(claves.map((k) => [k, r[k] ?? (typeof r[k] === "boolean" ? false : null)])) : null);
const igual = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

export function crearServicio({ db, storage, mirror, env = {}, hoy = hoyLima, permisos = crearPermisos(env) }: Deps) {
  // ---- reglas comunes: permisos, días cerrados e historial de cambios ---------------------------

  /**
   * ¿Se puede escribir en ese día? Lo decide el servidor (no la app):
   *  - un día anterior a hoy solo lo corrige quien tiene permiso (Finanzas / administrador);
   *  - un día cerrado queda bloqueado para todos hasta que un administrador lo reabra;
   *  - si hay un día posterior ya cerrado, tampoco se toca este (cambiaría los saldos de un cierre ya hecho).
   * `soloPermiso` es para la caja chica, que no se cierra con el día.
   */
  async function guardiaDia(q: Db, ciudad: string, fecha: string, u: Usuario, { soloPermiso = false } = {}) {
    if (fecha < hoy() && !permisos.corregirPasado(u))
      throw new ApiError(403, "SIN_PERMISO", "Solo Finanzas o un administrador pueden corregir días anteriores.");
    if (soloPermiso) return;
    const [h] = await q.query<Row>(`SELECT 1 AS x FROM caja_hoja WHERE ciudad = $1 AND fecha = $2::date AND cerrada_en IS NOT NULL`, [ciudad, fecha]);
    if (h) throw new ApiError(409, "DIA_CERRADO", `El ${fecha} ya está cerrado. Un administrador debe reabrirlo para corregirlo.`);
    const [post] = await q.query<Row>(`SELECT fecha::text AS fecha FROM caja_hoja WHERE ciudad = $1 AND fecha > $2::date AND cerrada_en IS NOT NULL ORDER BY fecha LIMIT 1`, [ciudad, fecha]);
    if (post) throw new ApiError(409, "DIA_POSTERIOR_CERRADO", `El día ${post.fecha} ya está cerrado, así que este no se puede cambiar. Un administrador debe reabrir primero ese día.`);
  }

  type Cambio = { accion: string; entidad: string; entidad_id?: string | null; ciudad?: string | null; fecha_dia?: string | null; antes?: unknown; despues?: unknown; motivo?: string | null };
  /** Anota en el historial quién cambió qué y cómo estaba antes. */
  async function auditar(q: Db, u: Usuario, c: Cambio) {
    await q.query(
      `INSERT INTO caja_auditoria (usuario_id, usuario, rol, accion, entidad, entidad_id, ciudad, fecha_dia, antes, despues, motivo)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::date, $9::jsonb, $10::jsonb, $11)`,
      [u.id, u.nombre || u.email || u.id, u.rol, c.accion, c.entidad, c.entidad_id ?? null, c.ciudad ?? null, c.fecha_dia ?? null,
       c.antes == null ? null : JSON.stringify(c.antes), c.despues == null ? null : JSON.stringify(c.despues), c.motivo ?? null],
    );
  }

  /** Día y ciudad al que pertenece una foto (de su fila o de su gasto de caja chica). */
  async function duenoDeFoto(q: Db, filaId: string | null, movId: string | null) {
    const [d] = filaId
      ? await q.query<Row>(`SELECT h.ciudad, h.fecha::text AS fecha FROM caja_fila f JOIN caja_hoja h ON h.id = f.hoja_id WHERE f.id = $1::uuid AND f.deleted_at IS NULL`, [filaId])
      : await q.query<Row>(`SELECT ciudad, fecha::text AS fecha FROM caja_chica_mov WHERE id = $1::uuid AND deleted_at IS NULL`, [movId]);
    return d as { ciudad: string; fecha: string } | undefined;
  }

  const conflicto = (version: unknown, actual: number, que: string) => {
    if (version == null) return;
    if (!Number.isInteger(version)) throw bad("version debe ser un número entero.");
    if (version !== actual) throw new ApiError(409, "CAMBIO_CONCURRENTE", `Otra persona modificó ${que} mientras lo editabas. Se actualizó con lo último: revisa y vuelve a hacer tu cambio.`);
  };

  // ---- lecturas ---------------------------------------------------------------------------------

  async function cargarHojas(q: Db, where: string, params: unknown[]) {
    const hojas = await q.query<Row>(
      `SELECT h.id, h.ciudad, h.fecha::text AS fecha, h.responsable_caja, h.obras_realizadas, h.maletas, h.escaleras, h.encargado_obra, h.updated_at, h.version,
              h.cerrada_en, h.cerrada_por, h.efectivo_contado::float8 AS efectivo_contado, h.saldo_calculado::float8 AS saldo_calculado, h.diferencia::float8 AS diferencia, h.nota_cierre,
              r.saldo_anterior_caja::float8 AS saldo_anterior_caja, r.saldo_anterior_cta_cte::float8 AS saldo_anterior_cta_cte,
              r.saldo_final_caja::float8 AS saldo_final_caja, r.saldo_final_cta_cte::float8 AS saldo_final_cta_cte
         FROM caja_hoja h JOIN v_caja_hoja_resumen r ON r.id = h.id
        WHERE ${where} ORDER BY h.ciudad, h.fecha`,
      params,
    );
    if (!hojas.length) return [];
    const ids = hojas.map((h) => h.id);
    const filas = await q.query<Row>(`SELECT ${COLS_FILA} FROM caja_fila f WHERE f.hoja_id = ANY($1::uuid[]) AND f.deleted_at IS NULL ORDER BY f.hoja_id, f.orden, f.created_at, f.id`, [ids]);
    const adj = filas.length
      ? await q.query<Row>(`SELECT id, fila_id, movimiento_id, mime, bytes, nombre FROM caja_adjunto WHERE fila_id = ANY($1::uuid[]) ORDER BY created_at, id`, [filas.map((f) => f.id)])
      : [];
    return hojas.map((h) => {
      const fs = filas.filter((f) => f.hoja_id === h.id).map((f) => filaDe(f, adj));
      return {
        id: h.id, ciudad: h.ciudad, fecha: h.fecha, responsable_caja: h.responsable_caja, obras_realizadas: h.obras_realizadas, maletas: h.maletas, escaleras: h.escaleras, encargado_obra: h.encargado_obra,
        saldo_anterior_caja: h.saldo_anterior_caja, saldo_anterior_cta_cte: h.saldo_anterior_cta_cte, saldo_final_caja: h.saldo_final_caja, saldo_final_cta_cte: h.saldo_final_cta_cte,
        totales: totalesHoja(fs), updated_at: iso(h.updated_at), version: h.version,
        cierre: h.cerrada_en
          ? { cerrada_en: iso(h.cerrada_en), cerrada_por: h.cerrada_por ?? "", efectivo_contado: h.efectivo_contado, saldo_calculado: h.saldo_calculado, diferencia: h.diferencia, nota: h.nota_cierre ?? "" }
          : null,
        filas: fs,
      };
    });
  }

  async function hojaPorId(q: Db, id: string) {
    const [h] = await cargarHojas(q, "h.id = $1::uuid", [id]);
    if (!h) throw new ApiError(404, "HOJA_NO_ENCONTRADA", "No existe esa hoja.");
    return h;
  }

  async function asegurarHoja(q: Db, ciudad: Ciudad, fecha: string, u: Usuario, id?: string) {
    const limite = new Date(hoy() + "T00:00:00Z");
    limite.setUTCDate(limite.getUTCDate() + 1);
    if (new Date(fecha + "T00:00:00Z") > limite) throw bad("No se puede abrir una hoja de una fecha futura.");
    await q.query(
      `INSERT INTO caja_hoja (id, ciudad, fecha, created_by, updated_by) VALUES (COALESCE($1::uuid, gen_random_uuid()), $2, $3::date, $4, $4) ON CONFLICT (ciudad, fecha) DO NOTHING`,
      [id ?? null, ciudad, fecha, u.id],
    );
    const [h] = await q.query<Row>(`SELECT id FROM caja_hoja WHERE ciudad = $1 AND fecha = $2::date`, [ciudad, fecha]);
    return h.id as string;
  }

  // ---- reflejo en el ERP ------------------------------------------------------------------------

  /** Deja el ERP igual a lo que dice la fila ahora: crea, actualiza o anula. Si falla, la fila queda marcada para reintentar. */
  async function reflejarFila(filaId: string, u: Usuario) {
    const [r] = await db.query<Row>(`SELECT ${COLS_FILA}, f.deleted_at, h.ciudad, h.fecha::text AS fecha FROM caja_fila f JOIN caja_hoja h ON h.id = f.hoja_id WHERE f.id = $1::uuid`, [filaId]);
    if (!r) return;
    const want = r.deleted_at ? { ingreso: null, gasto: null } : payloadsDeFila(filaDe(r) as unknown as Fila, r.ciudad, r.fecha);
    let ingId: string | null = nullable(r.ingreso_erp_id);
    let gasId: string | null = nullable(r.gasto_erp_id);
    try {
      if (want.ingreso && ingId) await mirror.actualizarIngreso(ingId, want.ingreso, u);
      else if (want.ingreso) ingId = nullable(await mirror.crearIngreso(want.ingreso, u));
      else if (ingId) {
        await mirror.anularIngreso(ingId, u);
        ingId = null;
      }
      await db.query(`UPDATE caja_fila SET ingreso_erp_id = $2 WHERE id = $1::uuid`, [filaId, ingId]);
      if (want.gasto && gasId) await mirror.actualizarGasto(gasId, want.gasto, u);
      else if (want.gasto) gasId = nullable(await mirror.crearGasto(want.gasto, u));
      else if (gasId) {
        await mirror.anularGasto(gasId, u);
        gasId = null;
      }
      await db.query(`UPDATE caja_fila SET gasto_erp_id = $2, erp_pendiente = false, erp_error = NULL WHERE id = $1::uuid`, [filaId, gasId]);
    } catch (e) {
      await db.query(`UPDATE caja_fila SET ingreso_erp_id = $2, gasto_erp_id = $3, erp_pendiente = true, erp_error = $4 WHERE id = $1::uuid`, [filaId, ingId, gasId, String((e as Error).message).slice(0, 300)]);
    }
  }

  async function reflejarMov(movId: string, u: Usuario) {
    const [r] = await db.query<Row>(`SELECT ${COLS_MOV}, m.deleted_at FROM caja_chica_mov m WHERE m.id = $1::uuid`, [movId]);
    if (!r) return;
    const want = r.deleted_at ? null : payloadDeMovChica(r as any);
    let gasId: string | null = nullable(r.gasto_erp_id);
    try {
      if (want && gasId) await mirror.actualizarGasto(gasId, want, u);
      else if (want) gasId = nullable(await mirror.crearGasto(want, u));
      else if (gasId) {
        await mirror.anularGasto(gasId, u);
        gasId = null;
      }
      await db.query(`UPDATE caja_chica_mov SET gasto_erp_id = $2, erp_pendiente = false, erp_error = NULL WHERE id = $1::uuid`, [movId, gasId]);
    } catch (e) {
      await db.query(`UPDATE caja_chica_mov SET gasto_erp_id = $2, erp_pendiente = true, erp_error = $3 WHERE id = $1::uuid`, [movId, gasId, String((e as Error).message).slice(0, 300)]);
    }
  }

  // ---- API --------------------------------------------------------------------------------------

  return {
    async estado(ciudadIn: unknown) {
      const ciudad = ciudadDe(ciudadIn);
      const [cfg] = await db.query<Row>(`SELECT saldo_inicial_caja::float8 AS caja, saldo_inicial_cta_cte::float8 AS cta, saldo_inicial_caja_chica::float8 AS chica FROM caja_config WHERE ciudad = $1`, [ciudad]);
      const [ult] = await db.query<Row>(`SELECT fecha::text AS fecha, saldo_final_caja::float8 AS caja, saldo_final_cta_cte::float8 AS cta FROM v_caja_hoja_resumen WHERE ciudad = $1 ORDER BY fecha DESC LIMIT 1`, [ciudad]);
      const [chica] = await db.query<Row>(`SELECT saldo::float8 AS saldo FROM v_caja_chica_saldo WHERE ciudad = $1`, [ciudad]);
      return {
        ciudad,
        config: { saldo_inicial_caja: cfg.caja, saldo_inicial_cta_cte: cfg.cta, saldo_inicial_caja_chica: cfg.chica },
        caja: { saldo: ult ? ult.caja : cfg.caja, fecha_ultima_hoja: ult?.fecha ?? null },
        cta_cte: { saldo: ult ? ult.cta : cfg.cta },
        caja_chica: { saldo: chica.saldo },
      };
    },

    async putConfig(ciudadIn: unknown, b: Row, u: Usuario) {
      if (!permisos.configurar(u)) throw new ApiError(403, "SIN_PERMISO", "Solo un administrador puede cambiar los saldos iniciales.");
      const ciudad = ciudadDe(ciudadIn);
      const saldo = (v: unknown, c: string) => {
        const n = Number(v);
        if (!Number.isFinite(n) || Math.abs(n) > 999_999_999) throw bad(`${c} no es un importe válido.`);
        return r2(n);
      };
      const nuevo = { saldo_inicial_caja: saldo(b.saldo_inicial_caja, "saldo_inicial_caja"), saldo_inicial_cta_cte: saldo(b.saldo_inicial_cta_cte, "saldo_inicial_cta_cte"), saldo_inicial_caja_chica: saldo(b.saldo_inicial_caja_chica, "saldo_inicial_caja_chica") };
      await db.tx(async (t) => {
        const [antes] = await t.query<Row>(`SELECT saldo_inicial_caja::float8 AS saldo_inicial_caja, saldo_inicial_cta_cte::float8 AS saldo_inicial_cta_cte, saldo_inicial_caja_chica::float8 AS saldo_inicial_caja_chica FROM caja_config WHERE ciudad = $1 FOR UPDATE`, [ciudad]);
        await t.query(
          `UPDATE caja_config SET saldo_inicial_caja = $2, saldo_inicial_cta_cte = $3, saldo_inicial_caja_chica = $4, updated_by = $5, updated_at = now() WHERE ciudad = $1`,
          [ciudad, nuevo.saldo_inicial_caja, nuevo.saldo_inicial_cta_cte, nuevo.saldo_inicial_caja_chica, u.id],
        );
        if (!igual(antes, nuevo)) await auditar(t, u, { accion: "config", entidad: "config", entidad_id: ciudad, ciudad, antes, despues: nuevo });
      });
      return this.estado(ciudad);
    },

    async abrirHoja(b: Row, u: Usuario) {
      const ciudad = ciudadDe(b.ciudad);
      const fecha = fechaDe(b.fecha);
      const id = await asegurarHoja(db, ciudad, fecha, u, b.id ? uuid(b.id, "id") : undefined);
      return { hoja: await hojaPorId(db, id) };
    },

    async hojas(q: Row) {
      const desde = fechaDe(q.desde, "desde");
      const hasta = fechaDe(q.hasta, "hasta");
      if (desde > hasta) throw bad("desde no puede ser posterior a hasta.");
      const ciudad = q.ciudad ? ciudadDe(q.ciudad) : null;
      return { hojas: await cargarHojas(db, "($1::text IS NULL OR h.ciudad = $1) AND h.fecha >= $2::date AND h.fecha <= $3::date", [ciudad, desde, hasta]) };
    },

    async patchHoja(id: string, b: Row, u: Usuario) {
      uuid(id, "id");
      await db.tx(async (t) => {
        const [h] = await t.query<Row>(`SELECT id, ciudad, fecha::text AS fecha, version, responsable_caja, obras_realizadas, maletas, escaleras, encargado_obra FROM caja_hoja WHERE id = $1::uuid FOR UPDATE`, [id]);
        if (!h) throw new ApiError(404, "HOJA_NO_ENCONTRADA", "No existe esa hoja.");
        await guardiaDia(t, h.ciudad, h.fecha, u);
        const sets: string[] = [];
        const params: unknown[] = [id, u.id];
        const despues: Row = { ...tomar(h, PIE_HOJA) };
        for (const c of PIE_HOJA) if (c in b) (params.push(texto(b[c], 2000)), sets.push(`${c} = $${params.length}`), (despues[c] = texto(b[c], 2000)));
        const antes = tomar(h, PIE_HOJA);
        if (!sets.length || igual(antes, despues)) return; // nada cambió: no se anota ni se sube la versión
        conflicto(b.version, h.version, "las observaciones de este día");
        await t.query(`UPDATE caja_hoja SET ${sets.join(", ")}, version = version + 1, updated_by = $2, updated_at = now() WHERE id = $1::uuid`, params);
        await auditar(t, u, { accion: "editar", entidad: "hoja", entidad_id: id, ciudad: h.ciudad, fecha_dia: h.fecha, antes, despues });
      });
      return { hoja: await hojaPorId(db, id) };
    },

    async putFila(idIn: string, b: Row, u: Usuario) {
      const id = uuid(idIn, "id");
      const hojaId = uuid(b.hoja_id, "hoja_id");
      if (!TIPOS_FILA.includes(b.tipo)) throw bad(`tipo debe ser ${TIPOS_FILA.join(", ")}.`);
      const comprobante = b.comprobante ?? "NINGUNO";
      if (!COMPROBANTES.includes(comprobante)) throw bad(`comprobante debe ser ${COMPROBANTES.join(", ")}.`);
      const f = {
        tipo: b.tipo, descripcion: texto(b.descripcion), responsable: texto(b.responsable, 120), comprobante,
        caja_ingreso_efectivo: importe(b.caja_ingreso_efectivo, "caja_ingreso_efectivo"), caja_ingreso_transf: importe(b.caja_ingreso_transf, "caja_ingreso_transf"),
        caja_salida_efectivo: importe(b.caja_salida_efectivo, "caja_salida_efectivo"), caja_salida_transf: importe(b.caja_salida_transf, "caja_salida_transf"),
        cta_cte_ingreso: importe(b.cta_cte_ingreso, "cta_cte_ingreso"), cta_cte_salida: importe(b.cta_cte_salida, "cta_cte_salida"),
        categoria: texto(b.categoria, 60), subcategoria: texto(b.subcategoria, 60), interno: b.interno === true,
      };
      if (f.categoria && !CATS.includes(f.categoria as never)) throw bad("categoria no es válida.");
      if (f.subcategoria && !(SUBCATS["Gastos fijos"] as readonly string[]).includes(f.subcategoria)) throw bad("subcategoria no es válida.");
      // Mismas reglas que valida la app (calc.validarFila): descripción, responsable, algún importe, categoría si hay gasto real.
      const errores = validarFila({ ...f, id, orden: 0, adjuntos: [], updated_at: "" } as unknown as Fila);
      const primero = Object.values(errores)[0];
      if (primero) throw bad(primero);

      const hecho = await db.tx(async (t) => {
        const [hoja] = await t.query<Row>(`SELECT id, ciudad, fecha::text AS fecha FROM caja_hoja WHERE id = $1::uuid`, [hojaId]);
        if (!hoja) throw new ApiError(404, "HOJA_NO_ENCONTRADA", "La hoja de esta fila no existe.");
        const [ya] = await t.query<Row>(`SELECT ${COLS_FILA}, f.deleted_at FROM caja_fila f WHERE f.id = $1::uuid FOR UPDATE`, [id]);
        if (ya?.deleted_at) throw new ApiError(409, "FILA_ELIMINADA", "Esta fila ya fue eliminada.");
        if (ya?.transferencia_id) throw new ApiError(409, "FILA_DE_TRANSFERENCIA", "Esta fila es un envío a caja chica; anula la transferencia en lugar de editarla.");
        if (ya && ya.hoja_id !== hojaId) throw new ApiError(409, "HOJA_DISTINTA", "Una fila no puede cambiar de hoja.");
        const antes = tomar(ya, NEGOCIO_FILA);
        const despues = { ...f, categoria: f.categoria || null, subcategoria: f.subcategoria || null };
        // Reenviar lo mismo (un reintento) no cambia nada: ni versión ni historial.
        if (ya && igual(antes, despues) && (!Number.isInteger(b.orden) || b.orden === ya.orden)) return false;
        await guardiaDia(t, hoja.ciudad, hoja.fecha, u);
        if (ya) conflicto(b.version, ya.version, "este movimiento");
        await t.query(
          `INSERT INTO caja_fila (id, hoja_id, orden, tipo, descripcion, responsable, comprobante, caja_ingreso_efectivo, caja_ingreso_transf, caja_salida_efectivo, caja_salida_transf,
                                  cta_cte_ingreso, cta_cte_salida, categoria, subcategoria, interno, created_by, updated_by)
           VALUES ($1::uuid, $2::uuid, COALESCE($3::int, (SELECT COALESCE(MAX(orden), 0) + 1 FROM caja_fila WHERE hoja_id = $2::uuid)), $4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$17)
           ON CONFLICT (id) DO UPDATE SET orden = COALESCE($3::int, caja_fila.orden), tipo = EXCLUDED.tipo, descripcion = EXCLUDED.descripcion, responsable = EXCLUDED.responsable,
             comprobante = EXCLUDED.comprobante, caja_ingreso_efectivo = EXCLUDED.caja_ingreso_efectivo, caja_ingreso_transf = EXCLUDED.caja_ingreso_transf,
             caja_salida_efectivo = EXCLUDED.caja_salida_efectivo, caja_salida_transf = EXCLUDED.caja_salida_transf, cta_cte_ingreso = EXCLUDED.cta_cte_ingreso,
             cta_cte_salida = EXCLUDED.cta_cte_salida, categoria = EXCLUDED.categoria, subcategoria = EXCLUDED.subcategoria, interno = EXCLUDED.interno,
             version = caja_fila.version + 1, updated_by = EXCLUDED.updated_by, updated_at = now()`,
          [id, hojaId, Number.isInteger(b.orden) ? b.orden : null, f.tipo, f.descripcion, f.responsable, f.comprobante, f.caja_ingreso_efectivo, f.caja_ingreso_transf, f.caja_salida_efectivo,
           f.caja_salida_transf, f.cta_cte_ingreso, f.cta_cte_salida, f.categoria || null, f.subcategoria || null, f.interno, u.id],
        );
        await auditar(t, u, { accion: ya ? "editar" : "crear", entidad: "fila", entidad_id: id, ciudad: hoja.ciudad, fecha_dia: hoja.fecha, antes, despues });
        return true;
      });
      if (hecho) await reflejarFila(id, u);
      const [r] = await db.query<Row>(`SELECT ${COLS_FILA} FROM caja_fila f WHERE f.id = $1::uuid`, [id]);
      const adj = await db.query<Row>(`SELECT id, fila_id, movimiento_id, mime, bytes, nombre FROM caja_adjunto WHERE fila_id = $1::uuid`, [id]);
      return { fila: filaDe(r, adj) };
    },

    async deleteFila(idIn: string, u: Usuario) {
      const id = uuid(idIn, "id");
      const hecho = await db.tx(async (t) => {
        const [r] = await t.query<Row>(`SELECT ${COLS_FILA}, f.deleted_at, h.ciudad, h.fecha::text AS fecha FROM caja_fila f JOIN caja_hoja h ON h.id = f.hoja_id WHERE f.id = $1::uuid FOR UPDATE OF f`, [id]);
        if (!r || r.deleted_at) return false; // borrar dos veces es lo mismo que borrar una
        if (r.transferencia_id) throw new ApiError(409, "FILA_DE_TRANSFERENCIA", "Esta fila es un envío a caja chica; anula la transferencia.");
        await guardiaDia(t, r.ciudad, r.fecha, u);
        await t.query(`UPDATE caja_fila SET deleted_at = now(), deleted_by = $2, version = version + 1 WHERE id = $1::uuid`, [id, u.id]);
        await auditar(t, u, { accion: "eliminar", entidad: "fila", entidad_id: id, ciudad: r.ciudad, fecha_dia: r.fecha, antes: tomar(r, NEGOCIO_FILA) });
        return true;
      });
      if (hecho) await reflejarFila(id, u);
      return { ok: true };
    },

    async crearTransferencia(b: Row, u: Usuario) {
      const id = uuid(b.id, "id");
      const filaId = uuid(b.fila_id, "fila_id");
      const movId = uuid(b.movimiento_id, "movimiento_id");
      const ciudad = ciudadDe(b.ciudad);
      const fecha = fechaDe(b.fecha);
      const monto = importe(b.monto, "monto", { positivo: true });
      const nota = texto(b.nota, 200);
      await db.tx(async (t) => {
        const [ya] = await t.query<Row>(`SELECT 1 AS x FROM caja_transferencia WHERE id = $1::uuid`, [id]);
        if (ya) return; // reintento del mismo envío: ya está hecho
        await guardiaDia(t, ciudad, fecha, u);
        const hojaId = await asegurarHoja(t, ciudad, fecha, u);
        const [{ saldo }] = await t.query<Row>(`SELECT saldo_final_caja::float8 AS saldo FROM v_caja_hoja_resumen WHERE id = $1::uuid`, [hojaId]);
        if (monto > r2(saldo))
          throw new ApiError(422, "SALDO_INSUFICIENTE", `La caja diaria tiene S/ ${saldo.toFixed(2)} y quieres enviar S/ ${monto.toFixed(2)}.`);
        await t.query(`INSERT INTO caja_transferencia (id, ciudad, fecha, monto, nota, created_by) VALUES ($1::uuid, $2, $3::date, $4, $5, $6)`, [id, ciudad, fecha, monto, nota, u.id]);
        await t.query(
          `INSERT INTO caja_fila (id, hoja_id, orden, tipo, descripcion, responsable, caja_salida_efectivo, interno, transferencia_id, created_by, updated_by)
           VALUES ($1::uuid, $2::uuid, (SELECT COALESCE(MAX(orden), 0) + 1 FROM caja_fila WHERE hoja_id = $2::uuid), 'OTRO', $3, $4, $5, true, $6::uuid, $7, $7)`,
          [filaId, hojaId, nota ? `Envío a caja chica · ${nota}` : "Envío a caja chica", u.nombre || u.id, monto, id, u.id],
        );
        await t.query(
          `INSERT INTO caja_chica_mov (id, ciudad, fecha, tipo, descripcion, persona, monto, origen, transferencia_id, created_by, updated_by)
           VALUES ($1::uuid, $2, $3::date, 'TRANSFERENCIA', $4, $5, $6, 'TRANSFERENCIA', $7::uuid, $8, $8)`,
          [movId, ciudad, fecha, nota ? `Recibido de caja diaria · ${nota}` : "Recibido de caja diaria", u.nombre || u.id, monto, id, u.id],
        );
        await auditar(t, u, { accion: "crear", entidad: "transferencia", entidad_id: id, ciudad, fecha_dia: fecha, despues: { monto, nota } });
      });
      const [f] = await db.query<Row>(`SELECT ${COLS_FILA} FROM caja_fila f WHERE f.transferencia_id = $1::uuid`, [id]);
      const [m] = await db.query<Row>(`SELECT ${COLS_MOV} FROM caja_chica_mov m WHERE m.transferencia_id = $1::uuid`, [id]);
      return { transferencia: { id, ciudad, fecha, monto, nota }, fila: filaDe(f), movimiento: movDe(m) };
    },

    async anularTransferencia(idIn: string, u: Usuario) {
      const id = uuid(idIn, "id");
      await db.tx(async (t) => {
        const [tr] = await t.query<Row>(`SELECT ciudad, fecha::text AS fecha, monto::float8 AS monto, nota, deleted_at FROM caja_transferencia WHERE id = $1::uuid FOR UPDATE`, [id]);
        if (!tr || tr.deleted_at) return;
        await guardiaDia(t, tr.ciudad, tr.fecha, u);
        const [{ saldo }] = await t.query<Row>(`SELECT saldo::float8 AS saldo FROM v_caja_chica_saldo WHERE ciudad = $1`, [tr.ciudad]);
        if (r2(saldo - tr.monto) < 0)
          throw new ApiError(409, "SALDO_CHICA_INSUFICIENTE", `No se puede anular: la caja chica tiene S/ ${saldo.toFixed(2)} y ya gastó parte de este envío.`);
        await t.query(`UPDATE caja_transferencia SET deleted_at = now(), deleted_by = $2 WHERE id = $1::uuid`, [id, u.id]);
        await t.query(`UPDATE caja_fila SET deleted_at = now(), deleted_by = $2, version = version + 1 WHERE transferencia_id = $1::uuid`, [id, u.id]);
        await t.query(`UPDATE caja_chica_mov SET deleted_at = now(), deleted_by = $2, version = version + 1 WHERE transferencia_id = $1::uuid`, [id, u.id]);
        await auditar(t, u, { accion: "anular", entidad: "transferencia", entidad_id: id, ciudad: tr.ciudad, fecha_dia: tr.fecha, antes: { monto: tr.monto, nota: tr.nota } });
      });
      return { ok: true };
    },

    async movimientosChica(q: Row) {
      const ciudad = ciudadDe(q.ciudad);
      const desde = fechaDe(q.desde, "desde");
      const hasta = fechaDe(q.hasta, "hasta");
      if (desde > hasta) throw bad("desde no puede ser posterior a hasta.");
      const [{ anterior }] = await db.query<Row>(
        `SELECT (c.saldo_inicial_caja_chica + COALESCE((SELECT SUM(CASE m.tipo WHEN 'TRANSFERENCIA' THEN m.monto ELSE -m.monto END) FROM caja_chica_mov m
                  WHERE m.ciudad = c.ciudad AND m.deleted_at IS NULL AND m.fecha < $2::date), 0))::float8 AS anterior FROM caja_config c WHERE c.ciudad = $1`,
        [ciudad, desde],
      );
      const [{ saldo }] = await db.query<Row>(`SELECT saldo::float8 AS saldo FROM v_caja_chica_saldo WHERE ciudad = $1`, [ciudad]);
      const movs = await db.query<Row>(`SELECT ${COLS_MOV} FROM caja_chica_mov m WHERE m.ciudad = $1 AND m.deleted_at IS NULL AND m.fecha >= $2::date AND m.fecha <= $3::date ORDER BY m.fecha, m.created_at, m.id`, [ciudad, desde, hasta]);
      const adj = movs.length ? await db.query<Row>(`SELECT id, fila_id, movimiento_id, mime, bytes, nombre FROM caja_adjunto WHERE movimiento_id = ANY($1::uuid[]) ORDER BY created_at, id`, [movs.map((m) => m.id)]) : [];
      return { saldo_anterior: anterior, saldo, movimientos: movs.map((m) => movDe(m, adj)) };
    },

    async putMovChica(idIn: string, b: Row, u: Usuario) {
      const id = uuid(idIn, "id");
      const ciudad = ciudadDe(b.ciudad);
      const fecha = fechaDe(b.fecha);
      const descripcion = texto(b.descripcion);
      if (!descripcion) throw bad("Escribe la descripción.");
      const categoria = texto(b.categoria, 60);
      if (!CATS.includes(categoria as never)) throw bad("Elige una categoría válida.");
      const subcategoria = texto(b.subcategoria, 60);
      if (categoria === "Gastos fijos" && !(SUBCATS["Gastos fijos"] as readonly string[]).includes(subcategoria)) throw bad("Elige el tipo de gasto fijo.");
      const origen = b.origen === "CAPTURA" ? "CAPTURA" : "MANUAL";
      const monto = importe(b.monto, "monto", { positivo: true });
      const hecho = await db.tx(async (t) => {
        const [ya] = await t.query<Row>(`SELECT ${COLS_MOV}, m.deleted_at FROM caja_chica_mov m WHERE m.id = $1::uuid FOR UPDATE`, [id]);
        if (ya?.deleted_at) throw new ApiError(409, "MOVIMIENTO_ELIMINADO", "Este movimiento ya fue eliminado.");
        if (ya && ya.tipo !== "EGRESO") throw new ApiError(409, "MOVIMIENTO_DE_TRANSFERENCIA", "Este movimiento es un envío desde caja diaria; anula la transferencia.");
        if (ya && ya.ciudad !== ciudad) throw new ApiError(409, "CIUDAD_DISTINTA", "Un movimiento no puede cambiar de ciudad.");
        const antes = tomar(ya, NEGOCIO_MOV);
        const despues = { fecha, descripcion, persona: texto(b.persona, 120), categoria, subcategoria: subcategoria || null, monto, origen };
        if (ya && igual({ ...antes, subcategoria: antes?.subcategoria || null }, despues)) return false; // reintento idéntico
        await guardiaDia(t, ciudad, fecha, u, { soloPermiso: true });
        if (ya) await guardiaDia(t, ciudad, ya.fecha, u, { soloPermiso: true });
        if (ya) conflicto(b.version, ya.version, "este gasto de caja chica");
        await t.query(
          `INSERT INTO caja_chica_mov (id, ciudad, fecha, tipo, descripcion, persona, categoria, subcategoria, monto, origen, created_by, updated_by)
           VALUES ($1::uuid, $2, $3::date, 'EGRESO', $4, $5, $6, $7, $8, $9, $10, $10)
           ON CONFLICT (id) DO UPDATE SET fecha = EXCLUDED.fecha, descripcion = EXCLUDED.descripcion, persona = EXCLUDED.persona, categoria = EXCLUDED.categoria,
             subcategoria = EXCLUDED.subcategoria, monto = EXCLUDED.monto, origen = EXCLUDED.origen, version = caja_chica_mov.version + 1, updated_by = EXCLUDED.updated_by, updated_at = now()`,
          [id, ciudad, fecha, descripcion, despues.persona, categoria, subcategoria || null, monto, origen, u.id],
        );
        await auditar(t, u, { accion: ya ? "editar" : "crear", entidad: "mov_chica", entidad_id: id, ciudad, fecha_dia: fecha, antes, despues });
        return true;
      });
      if (hecho) await reflejarMov(id, u);
      const [r] = await db.query<Row>(`SELECT ${COLS_MOV} FROM caja_chica_mov m WHERE m.id = $1::uuid`, [id]);
      const adj = await db.query<Row>(`SELECT id, fila_id, movimiento_id, mime, bytes, nombre FROM caja_adjunto WHERE movimiento_id = $1::uuid`, [id]);
      return { movimiento: movDe(r, adj) };
    },

    async deleteMovChica(idIn: string, u: Usuario) {
      const id = uuid(idIn, "id");
      const hecho = await db.tx(async (t) => {
        const [r] = await t.query<Row>(`SELECT ${COLS_MOV}, m.deleted_at FROM caja_chica_mov m WHERE m.id = $1::uuid FOR UPDATE`, [id]);
        if (!r || r.deleted_at) return false;
        if (r.tipo !== "EGRESO") throw new ApiError(409, "MOVIMIENTO_DE_TRANSFERENCIA", "Este movimiento es un envío desde caja diaria; anula la transferencia.");
        await guardiaDia(t, r.ciudad, r.fecha, u, { soloPermiso: true });
        await t.query(`UPDATE caja_chica_mov SET deleted_at = now(), deleted_by = $2, version = version + 1 WHERE id = $1::uuid`, [id, u.id]);
        await auditar(t, u, { accion: "eliminar", entidad: "mov_chica", entidad_id: id, ciudad: r.ciudad, fecha_dia: r.fecha, antes: tomar(r, NEGOCIO_MOV) });
        return true;
      });
      if (hecho) await reflejarMov(id, u);
      return { ok: true };
    },

    // ---- fotos ----------------------------------------------------------------------------------

    async putAdjunto(idIn: string, q: Row, mime: string, bytes: Buffer, u: Usuario) {
      const id = uuid(idIn, "id");
      const filaId = q.fila_id ? uuid(q.fila_id, "fila_id") : null;
      const movId = q.movimiento_id ? uuid(q.movimiento_id, "movimiento_id") : null;
      if (!!filaId === !!movId) throw bad("Indica fila_id o movimiento_id (uno solo).");
      const tipo = mime.split(";")[0].trim().toLowerCase();
      if (!MIMES.includes(tipo)) throw new ApiError(415, "TIPO_NO_PERMITIDO", "Solo se aceptan fotos JPG, PNG o WebP.");
      if (!bytes.length) throw bad("La foto está vacía.");
      if (bytes.length > MAX_FOTO) throw new ApiError(413, "FOTO_MUY_GRANDE", "La foto pesa más de 10 MB.");
      const dueno = await duenoDeFoto(db, filaId, movId);
      if (!dueno) throw new ApiError(404, "DUENO_NO_ENCONTRADO", "El registro al que pertenece la foto no existe.");
      const [ya] = await db.query<Row>(`SELECT 1 AS x FROM caja_adjunto WHERE id = $1::uuid`, [id]);
      if (!ya) {
        await guardiaDia(db, dueno.ciudad, dueno.fecha, u, { soloPermiso: !filaId });
        await storage.put(id, bytes);
        await db.tx(async (t) => {
          await t.query(`INSERT INTO caja_adjunto (id, fila_id, movimiento_id, archivo, mime, bytes, nombre, created_by) VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8)`, [id, filaId, movId, id, tipo, bytes.length, texto(q.nombre, 120) || null, u.id]);
          await auditar(t, u, { accion: "subir_foto", entidad: "adjunto", entidad_id: id, ciudad: dueno.ciudad, fecha_dia: dueno.fecha, despues: { de: filaId ? "fila" : "mov_chica", dueno_id: filaId ?? movId, mime: tipo, bytes: bytes.length } });
        });
      }
      return { adjunto: { id, mime: tipo, bytes: bytes.length, synced: true } };
    },

    async getAdjunto(idIn: string) {
      const id = uuid(idIn, "id");
      const [a] = await db.query<Row>(`SELECT archivo, mime FROM caja_adjunto WHERE id = $1::uuid`, [id]);
      const bytes = a ? await storage.get(a.archivo) : null;
      if (!a || !bytes) throw new ApiError(404, "ADJUNTO_NO_ENCONTRADO", "No existe esa foto.");
      return { mime: a.mime as string, bytes };
    },

    async deleteAdjunto(idIn: string, u: Usuario) {
      const id = uuid(idIn, "id");
      const [a] = await db.query<Row>(`SELECT archivo, fila_id, movimiento_id, mime, bytes FROM caja_adjunto WHERE id = $1::uuid`, [id]);
      if (a) {
        const dueno = await duenoDeFoto(db, a.fila_id, a.movimiento_id);
        await db.tx(async (t) => {
          if (dueno) await guardiaDia(t, dueno.ciudad, dueno.fecha, u, { soloPermiso: !a.fila_id });
          await t.query(`DELETE FROM caja_adjunto WHERE id = $1::uuid`, [id]);
          await auditar(t, u, { accion: "quitar_foto", entidad: "adjunto", entidad_id: id, ciudad: dueno?.ciudad, fecha_dia: dueno?.fecha, antes: { de: a.fila_id ? "fila" : "mov_chica", dueno_id: a.fila_id ?? a.movimiento_id, mime: a.mime, bytes: a.bytes } });
        });
        await storage.del(a.archivo);
      }
      return { ok: true };
    },

    /** Reintenta el reflejo en el ERP de todo lo que quedó pendiente (ERP caído, rechazo). */
    async reintentarErp(u: Usuario) {
      const filas = await db.query<Row>(`SELECT id FROM caja_fila WHERE erp_pendiente`);
      const movs = await db.query<Row>(`SELECT id FROM caja_chica_mov WHERE erp_pendiente`);
      for (const f of filas) await reflejarFila(f.id, u);
      for (const m of movs) await reflejarMov(m.id, u);
      const [{ n }] = await db.query<Row>(`SELECT ((SELECT COUNT(*) FROM caja_fila WHERE erp_pendiente) + (SELECT COUNT(*) FROM caja_chica_mov WHERE erp_pendiente))::int AS n`);
      return { reintentados: filas.length + movs.length, pendientes: n };
    },

    // ---- cierre del día (arqueo) ----------------------------------------------------------------

    /**
     * Cierra el día: la persona cuenta el efectivo y el sistema guarda la diferencia con el saldo calculado.
     * Desde ese momento el día queda bloqueado. Se cierran en orden: no se puede cerrar un día si uno anterior
     * con movimientos sigue abierto.
     */
    async cerrarHoja(idIn: string, b: Row, u: Usuario) {
      const id = uuid(idIn, "id");
      if (!permisos.cerrar(u)) throw new ApiError(403, "SIN_PERMISO", "Solo Finanzas o un administrador pueden cerrar la caja.");
      const contado = b.efectivo_contado == null || b.efectivo_contado === "" ? NaN : Number(b.efectivo_contado);
      if (!Number.isFinite(contado) || contado < 0 || contado > 999_999_999) throw bad("Escribe el efectivo contado (puede ser 0).");
      const nota = texto(b.nota, 500);
      await db.tx(async (t) => {
        const [h] = await t.query<Row>(`SELECT h.id, h.ciudad, h.fecha::text AS fecha, h.cerrada_en, r.saldo_final_caja::float8 AS saldo FROM caja_hoja h JOIN v_caja_hoja_resumen r ON r.id = h.id WHERE h.id = $1::uuid FOR UPDATE OF h`, [id]);
        if (!h) throw new ApiError(404, "HOJA_NO_ENCONTRADA", "No existe esa hoja.");
        if (h.cerrada_en) throw new ApiError(409, "DIA_CERRADO", `El ${h.fecha} ya estaba cerrado.`);
        if (h.fecha > hoy()) throw bad("No se puede cerrar un día que todavía no llegó.");
        const [previo] = await t.query<Row>(
          `SELECT h2.fecha::text AS fecha FROM caja_hoja h2
            WHERE h2.ciudad = $1 AND h2.fecha < $2::date AND h2.cerrada_en IS NULL
              AND EXISTS (SELECT 1 FROM caja_fila f WHERE f.hoja_id = h2.id AND f.deleted_at IS NULL)
            ORDER BY h2.fecha LIMIT 1`,
          [h.ciudad, h.fecha],
        );
        if (previo) throw new ApiError(409, "DIA_ANTERIOR_ABIERTO", `Primero hay que cerrar el día ${previo.fecha}: los días se cierran en orden.`);
        const diferencia = r2(contado - r2(h.saldo));
        if (diferencia !== 0 && !nota) throw bad(`No cuadra: ${diferencia > 0 ? "sobran" : "faltan"} S/ ${Math.abs(diferencia).toFixed(2)}. Explica la diferencia en la nota para poder cerrar.`);
        await t.query(
          `UPDATE caja_hoja SET cerrada_en = now(), cerrada_por = $2, cerrada_por_id = $3, efectivo_contado = $4, saldo_calculado = $5, diferencia = $6, nota_cierre = $7,
                  version = version + 1, updated_by = $3, updated_at = now() WHERE id = $1::uuid`,
          [id, u.nombre || u.email || u.id, u.id, r2(contado), r2(h.saldo), diferencia, nota || null],
        );
        await auditar(t, u, { accion: "cerrar", entidad: "hoja", entidad_id: id, ciudad: h.ciudad, fecha_dia: h.fecha, despues: { efectivo_contado: r2(contado), saldo_calculado: r2(h.saldo), diferencia, nota }, motivo: nota || null });
      });
      return { hoja: await hojaPorId(db, id) };
    },

    /** Solo un administrador puede reabrir un día cerrado, y queda anotado con el motivo. Se reabre de atrás hacia adelante. */
    async reabrirHoja(idIn: string, b: Row, u: Usuario) {
      const id = uuid(idIn, "id");
      if (!permisos.reabrir(u)) throw new ApiError(403, "SIN_PERMISO", "Solo un administrador puede reabrir un día cerrado.");
      const motivo = texto(b.motivo, 500);
      if (motivo.length < 5) throw bad("Escribe el motivo para reabrir el día (al menos 5 letras).");
      await db.tx(async (t) => {
        const [h] = await t.query<Row>(`SELECT id, ciudad, fecha::text AS fecha, cerrada_en, cerrada_por, efectivo_contado::float8 AS efectivo_contado, saldo_calculado::float8 AS saldo_calculado, diferencia::float8 AS diferencia, nota_cierre FROM caja_hoja WHERE id = $1::uuid FOR UPDATE`, [id]);
        if (!h) throw new ApiError(404, "HOJA_NO_ENCONTRADA", "No existe esa hoja.");
        if (!h.cerrada_en) throw new ApiError(409, "DIA_ABIERTO", "Ese día no está cerrado.");
        const [post] = await t.query<Row>(`SELECT fecha::text AS fecha FROM caja_hoja WHERE ciudad = $1 AND fecha > $2::date AND cerrada_en IS NOT NULL ORDER BY fecha DESC LIMIT 1`, [h.ciudad, h.fecha]);
        if (post) throw new ApiError(409, "DIA_POSTERIOR_CERRADO", `Primero hay que reabrir el día ${post.fecha}: se reabre de atrás hacia adelante.`);
        await t.query(
          `UPDATE caja_hoja SET cerrada_en = NULL, cerrada_por = NULL, cerrada_por_id = NULL, efectivo_contado = NULL, saldo_calculado = NULL, diferencia = NULL, nota_cierre = NULL,
                  version = version + 1, updated_by = $2, updated_at = now() WHERE id = $1::uuid`,
          [id, u.id],
        );
        await auditar(t, u, {
          accion: "reabrir", entidad: "hoja", entidad_id: id, ciudad: h.ciudad, fecha_dia: h.fecha, motivo,
          antes: { cerrada_por: h.cerrada_por, efectivo_contado: h.efectivo_contado, saldo_calculado: h.saldo_calculado, diferencia: h.diferencia, nota: h.nota_cierre },
        });
      });
      return { hoja: await hojaPorId(db, id) };
    },

    // ---- control y revisión -----------------------------------------------------------------------

    /** Cambios hechos en la caja: qué, quién, cuándo y el valor anterior. */
    async auditoria(q: Row, u: Usuario) {
      if (!permisos.revisar(u)) throw new ApiError(403, "SIN_PERMISO", "Tu rol no puede ver el historial de cambios.");
      const ciudad = q.ciudad ? ciudadDe(q.ciudad) : null;
      const fecha = q.fecha ? fechaDe(q.fecha) : null;
      const desde = q.desde ? fechaDe(q.desde, "desde") : null;
      const hasta = q.hasta ? fechaDe(q.hasta, "hasta") : null;
      const limite = Math.min(Math.max(Number.parseInt(String(q.limite ?? "100"), 10) || 100, 1), 500);
      const filas = await db.query<Row>(
        `SELECT id, creado_en, usuario_id, usuario, rol, accion, entidad, entidad_id, ciudad, fecha_dia::text AS fecha_dia, antes, despues, motivo
           FROM caja_auditoria
          WHERE ($1::text IS NULL OR ciudad = $1) AND ($2::date IS NULL OR fecha_dia = $2::date)
            AND ($3::date IS NULL OR fecha_dia >= $3::date) AND ($4::date IS NULL OR fecha_dia <= $4::date)
          ORDER BY id DESC LIMIT $5`,
        [ciudad, fecha, desde, hasta, limite],
      );
      return { cambios: filas.map((r) => ({ ...r, id: Number(r.id), creado_en: iso(r.creado_en) })) };
    },

    /**
     * Alertas de descuadre de los últimos días: cajas en negativo, movimientos sin comprobante, días sin cerrar
     * y cierres con diferencia. `nivel`: alta (revisar ya), media (pendiente), info.
     */
    async alertas(q: Row, u: Usuario) {
      if (!permisos.revisar(u)) throw new ApiError(403, "SIN_PERMISO", "Tu rol no puede ver las alertas.");
      const ciudad = q.ciudad ? ciudadDe(q.ciudad) : null;
      const dias = Math.min(Math.max(Number.parseInt(String(q.dias ?? "60"), 10) || 60, 1), 365);
      const limite = new Date(hoy() + "T00:00:00Z");
      limite.setUTCDate(limite.getUTCDate() - dias);
      const desde = limite.toISOString().slice(0, 10);
      const hoyStr = hoy();
      const alertas: { id: string; tipo: string; nivel: "alta" | "media" | "info"; ciudad: string | null; fecha: string | null; titulo: string; detalle: string; monto?: number }[] = [];
      const nombre = (c: string) => CIUDAD_LABEL_SRV[c] ?? c;

      for (const r of await db.query<Row>(
        `SELECT ciudad, fecha::text AS fecha, saldo_final_caja::float8 AS caja, saldo_final_cta_cte::float8 AS cta FROM v_caja_hoja_resumen
          WHERE fecha >= $1::date AND ($2::text IS NULL OR ciudad = $2) AND (saldo_final_caja < 0 OR saldo_final_cta_cte < 0) ORDER BY fecha DESC`, [desde, ciudad])) {
        if (r.caja < 0) alertas.push({ id: `CAJA_NEGATIVA:${r.ciudad}:${r.fecha}`, tipo: "CAJA_NEGATIVA", nivel: "alta", ciudad: r.ciudad, fecha: r.fecha, titulo: "Caja diaria en negativo", detalle: `${nombre(r.ciudad)} cerró el ${r.fecha} con S/ ${r.caja.toFixed(2)}.`, monto: r.caja });
        if (r.cta < 0) alertas.push({ id: `CTA_NEGATIVA:${r.ciudad}:${r.fecha}`, tipo: "CTA_CTE_NEGATIVA", nivel: "alta", ciudad: r.ciudad, fecha: r.fecha, titulo: "Cuenta corriente en negativo", detalle: `${nombre(r.ciudad)} cerró el ${r.fecha} con S/ ${r.cta.toFixed(2)} en cuenta corriente.`, monto: r.cta });
      }

      for (const r of await db.query<Row>(
        `WITH corrida AS (
           SELECT m.ciudad, m.fecha, c.saldo_inicial_caja_chica
                  + SUM(CASE m.tipo WHEN 'TRANSFERENCIA' THEN m.monto ELSE -m.monto END) OVER (PARTITION BY m.ciudad ORDER BY m.fecha, m.created_at, m.id) AS saldo
             FROM caja_chica_mov m JOIN caja_config c ON c.ciudad = m.ciudad WHERE m.deleted_at IS NULL)
         SELECT ciudad, fecha::text AS fecha, MIN(saldo)::float8 AS minimo FROM corrida
          WHERE saldo < 0 AND fecha >= $1::date AND ($2::text IS NULL OR ciudad = $2) GROUP BY ciudad, fecha ORDER BY fecha DESC`, [desde, ciudad]))
        alertas.push({ id: `CHICA_NEGATIVA:${r.ciudad}:${r.fecha}`, tipo: "CAJA_CHICA_NEGATIVA", nivel: "alta", ciudad: r.ciudad, fecha: r.fecha, titulo: "Caja chica en negativo", detalle: `La caja chica de ${nombre(r.ciudad)} llegó a S/ ${r.minimo.toFixed(2)} el ${r.fecha}.`, monto: r.minimo });

      for (const r of await db.query<Row>(
        `SELECT ciudad, fecha::text AS fecha, efectivo_contado::float8 AS contado, saldo_calculado::float8 AS calculado, diferencia::float8 AS diferencia, cerrada_por
           FROM caja_hoja WHERE cerrada_en IS NOT NULL AND diferencia <> 0 AND fecha >= $1::date AND ($2::text IS NULL OR ciudad = $2) ORDER BY fecha DESC`, [desde, ciudad]))
        alertas.push({ id: `DESCUADRE:${r.ciudad}:${r.fecha}`, tipo: "DIFERENCIA_EN_CIERRE", nivel: "alta", ciudad: r.ciudad, fecha: r.fecha, titulo: r.diferencia > 0 ? "Sobrante al cerrar" : "Faltante al cerrar", detalle: `${nombre(r.ciudad)} · ${r.fecha}: contado S/ ${r.contado.toFixed(2)} contra S/ ${r.calculado.toFixed(2)} calculado (${r.diferencia > 0 ? "+" : "−"}S/ ${Math.abs(r.diferencia).toFixed(2)}).`, monto: r.diferencia });

      for (const r of await db.query<Row>(
        `SELECT h.ciudad, h.fecha::text AS fecha, COUNT(f.id)::int AS n FROM caja_hoja h JOIN caja_fila f ON f.hoja_id = h.id AND f.deleted_at IS NULL
          WHERE h.cerrada_en IS NULL AND h.fecha < $1::date AND h.fecha >= $2::date AND ($3::text IS NULL OR h.ciudad = $3) GROUP BY h.ciudad, h.fecha ORDER BY h.fecha DESC`, [hoyStr, desde, ciudad]))
        alertas.push({ id: `SIN_CERRAR:${r.ciudad}:${r.fecha}`, tipo: "DIA_SIN_CERRAR", nivel: "media", ciudad: r.ciudad, fecha: r.fecha, titulo: "Día sin cerrar", detalle: `${nombre(r.ciudad)} · ${r.fecha} tiene ${r.n} ${r.n === 1 ? "movimiento" : "movimientos"} y no se hizo el cierre.` });

      for (const r of await db.query<Row>(
        `SELECT h.ciudad, h.fecha::text AS fecha, COUNT(*)::int AS n,
                SUM(f.caja_ingreso_efectivo + f.caja_ingreso_transf + f.cta_cte_ingreso + f.caja_salida_efectivo + f.caja_salida_transf + f.cta_cte_salida)::float8 AS total
           FROM caja_fila f JOIN caja_hoja h ON h.id = f.hoja_id
          WHERE f.deleted_at IS NULL AND NOT f.interno AND f.comprobante = 'NINGUNO'
            AND NOT EXISTS (SELECT 1 FROM caja_adjunto a WHERE a.fila_id = f.id)
            AND h.fecha >= $1::date AND ($2::text IS NULL OR h.ciudad = $2) GROUP BY h.ciudad, h.fecha ORDER BY h.fecha DESC`, [desde, ciudad]))
        alertas.push({ id: `SIN_COMPROBANTE:${r.ciudad}:${r.fecha}`, tipo: "FILAS_SIN_COMPROBANTE", nivel: "media", ciudad: r.ciudad, fecha: r.fecha, titulo: "Movimientos sin comprobante", detalle: `${nombre(r.ciudad)} · ${r.fecha}: ${r.n} ${r.n === 1 ? "movimiento" : "movimientos"} (S/ ${r.total.toFixed(2)}) sin comprobante ni foto.`, monto: r.total });

      for (const r of await db.query<Row>(
        `SELECT m.ciudad, m.fecha::text AS fecha, COUNT(*)::int AS n, SUM(m.monto)::float8 AS total FROM caja_chica_mov m
          WHERE m.deleted_at IS NULL AND m.tipo = 'EGRESO' AND NOT EXISTS (SELECT 1 FROM caja_adjunto a WHERE a.movimiento_id = m.id)
            AND m.fecha >= $1::date AND m.fecha < $2::date AND ($3::text IS NULL OR m.ciudad = $3) GROUP BY m.ciudad, m.fecha ORDER BY m.fecha DESC`, [desde, hoyStr, ciudad]))
        alertas.push({ id: `GASTO_SIN_FOTO:${r.ciudad}:${r.fecha}`, tipo: "GASTOS_CHICA_SIN_FOTO", nivel: "media", ciudad: r.ciudad, fecha: r.fecha, titulo: "Gastos de caja chica sin foto", detalle: `${nombre(r.ciudad)} · ${r.fecha}: ${r.n} ${r.n === 1 ? "gasto" : "gastos"} (S/ ${r.total.toFixed(2)}) sin foto del recibo.`, monto: r.total });

      const [pend] = await db.query<Row>(`SELECT ((SELECT COUNT(*) FROM caja_fila WHERE erp_pendiente AND deleted_at IS NULL) + (SELECT COUNT(*) FROM caja_chica_mov WHERE erp_pendiente AND deleted_at IS NULL))::int AS n`);
      if (pend.n > 0) alertas.push({ id: "ERP_PENDIENTE", tipo: "ERP_PENDIENTE", nivel: "info", ciudad: null, fecha: null, titulo: "Pendientes de reflejar en el ERP", detalle: `${pend.n} ${pend.n === 1 ? "registro quedó" : "registros quedaron"} sin reflejar en el ERP.` });

      const orden = { alta: 0, media: 1, info: 2 } as const;
      alertas.sort((a, b) => orden[a.nivel] - orden[b.nivel] || (b.fecha ?? "").localeCompare(a.fecha ?? ""));
      const resumen = { alta: 0, media: 0, info: 0 };
      for (const a of alertas) resumen[a.nivel]++;
      return { alertas, resumen, desde, hasta: hoyStr };
    },

    /** Para el tablero general: saldos por ciudad, el día de hoy, los últimos días y las alertas. */
    async resumen(u: Usuario) {
      if (!permisos.revisar(u)) throw new ApiError(403, "SIN_PERMISO", "Tu rol no puede ver el resumen de Finanzas.");
      const hoyStr = hoy();
      const hace7 = new Date(hoyStr + "T00:00:00Z");
      hace7.setUTCDate(hace7.getUTCDate() - 6);
      const desde = hace7.toISOString().slice(0, 10);
      const ciudades: Record<string, unknown> = {};
      for (const c of CIUDADES) {
        const est = await this.estado(c);
        const hojas = await cargarHojas(db, "h.ciudad = $1 AND h.fecha >= $2::date AND h.fecha <= $3::date", [c, desde, hoyStr]);
        ciudades[c] = {
          ...est,
          hoy: hojas.find((h) => h.fecha === hoyStr) ? resumenHoja(hojas.find((h) => h.fecha === hoyStr)!) : null,
          ultimos_dias: hojas.filter((h) => h.filas.length > 0 || h.cierre).map(resumenHoja).sort((a, b) => b.fecha.localeCompare(a.fecha)),
        };
      }
      const al = await this.alertas({}, u);
      const recientes = await this.auditoria({ limite: "15" }, u);
      return { fecha: hoyStr, ciudades, alertas: al.resumen, alertas_principales: al.alertas.slice(0, 8), cambios_recientes: recientes.cambios };
    },

    /** Cambia cada vez que algo de la caja cambia: las pantallas lo consultan seguido y solo recargan si es distinto. */
    async version() {
      const [r] = await db.query<Row>(
        `SELECT md5(concat_ws('|',
           (SELECT count(*)::text || coalesce(max(updated_at)::text, '') FROM caja_hoja),
           (SELECT count(*)::text || coalesce(max(updated_at)::text, '') || coalesce(max(deleted_at)::text, '') FROM caja_fila),
           (SELECT count(*)::text || coalesce(max(updated_at)::text, '') || coalesce(max(deleted_at)::text, '') FROM caja_chica_mov),
           (SELECT count(*)::text || coalesce(max(created_at)::text, '') FROM caja_adjunto),
           (SELECT coalesce(max(updated_at)::text, '') FROM caja_config),
           (SELECT count(*)::text || coalesce(max(deleted_at)::text, '') FROM caja_transferencia))) AS v`,
      );
      return { version: r.v as string };
    },

    permisos: (u: Usuario) => ({ usuario: { id: u.id, nombre: u.nombre, email: u.email, rol: u.rol }, permisos: permisos.de(u) }),


    nuevoId: () => randomUUID(),
  };
}

export type Servicio = ReturnType<typeof crearServicio>;
