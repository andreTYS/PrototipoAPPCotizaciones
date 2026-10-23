/**
 * Lo que las personas con permiso de revisar consultan al servidor: alertas de descuadre e historial de cambios.
 * Sin React ni red propia (la función de llamada se inyecta) para poder probarlo con Node.
 */
import { CATS } from "../data";
import type { Ciudad } from "./types";

export type Nivel = "alta" | "media" | "info";
export type Alerta = { id: string; tipo: string; nivel: Nivel; ciudad: Ciudad | null; fecha: string | null; titulo: string; detalle: string; monto?: number };
export type RespuestaAlertas = { alertas: Alerta[]; resumen: Record<Nivel, number>; desde: string; hasta: string };

export type Cambio = {
  id: number;
  creado_en: string;
  usuario: string | null;
  rol: string | null;
  accion: "crear" | "editar" | "eliminar" | "cerrar" | "reabrir" | "anular" | "config" | "subir_foto" | "quitar_foto";
  entidad: "fila" | "hoja" | "mov_chica" | "transferencia" | "config" | "adjunto";
  entidad_id: string | null;
  ciudad: Ciudad | null;
  fecha_dia: string | null;
  antes: Record<string, unknown> | null;
  despues: Record<string, unknown> | null;
  motivo: string | null;
};

type Llamar = <T = any>(method: string, path: string) => Promise<T>;

export const pedirAlertas = (json: Llamar, ciudad?: Ciudad) => json<RespuestaAlertas>("GET", `/caja/alertas${ciudad ? `?ciudad=${ciudad}` : ""}`);
export const pedirCambios = (json: Llamar, q: { ciudad?: Ciudad; fecha?: string; limite?: number }) => {
  const p = new URLSearchParams();
  if (q.ciudad) p.set("ciudad", q.ciudad);
  if (q.fecha) p.set("fecha", q.fecha);
  if (q.limite) p.set("limite", String(q.limite));
  return json<{ cambios: Cambio[] }>("GET", `/caja/auditoria?${p}`).then((r) => r.cambios);
};

// ---- texto para las personas ---------------------------------------------------------------------

const CAMPOS: Record<string, string> = {
  tipo: "tipo", descripcion: "descripción", responsable: "responsable", comprobante: "comprobante",
  caja_ingreso_efectivo: "ingreso en efectivo", caja_ingreso_transf: "ingreso Yape/transf.", caja_salida_efectivo: "salida en efectivo", caja_salida_transf: "salida Yape/transf.",
  cta_cte_ingreso: "ingreso cta. cte.", cta_cte_salida: "salida cta. cte.", categoria: "categoría", subcategoria: "subcategoría", interno: "movimiento interno",
  fecha: "fecha", persona: "persona", monto: "monto", origen: "origen",
  responsable_caja: "responsable de caja", obras_realizadas: "obras del día", maletas: "maletas", escaleras: "escaleras", encargado_obra: "encargado de obra",
  saldo_inicial_caja: "saldo inicial de caja", saldo_inicial_cta_cte: "saldo inicial cta. cte.", saldo_inicial_caja_chica: "saldo inicial caja chica",
  efectivo_contado: "efectivo contado", saldo_calculado: "saldo calculado", diferencia: "diferencia",
};
const IMPORTES = new Set(["caja_ingreso_efectivo", "caja_ingreso_transf", "caja_salida_efectivo", "caja_salida_transf", "cta_cte_ingreso", "cta_cte_salida", "monto", "saldo_inicial_caja", "saldo_inicial_cta_cte", "saldo_inicial_caja_chica", "efectivo_contado", "saldo_calculado", "diferencia"]);
const COMPROBANTES: Record<string, string> = { FACTURA: "Factura", BOLETA: "Boleta", RECIBO: "Recibo", CONTRATO_TICKET: "Contrato / Ticket", NINGUNO: "Sin comprobante" };
const TIPOS: Record<string, string> = { VTA: "Venta", OBRA: "Obra", OTRO: "Otro" };

const soles = (n: number) => `S/ ${n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
function valor(campo: string, v: unknown): string {
  if (v === null || v === undefined || v === "") return "vacío";
  if (typeof v === "boolean") return v ? "sí" : "no";
  if (IMPORTES.has(campo) && typeof v === "number") return soles(v);
  if (campo === "comprobante") return COMPROBANTES[String(v)] ?? String(v);
  if (campo === "tipo") return TIPOS[String(v)] ?? String(v);
  return String(v);
}

/** Qué cambió entre `antes` y `despues`: "salida en efectivo: S/ 20.00 → S/ 25.00". */
export function diferencias(antes: Record<string, unknown> | null, despues: Record<string, unknown> | null): string[] {
  if (!antes || !despues) return [];
  const claves = [...new Set([...Object.keys(antes), ...Object.keys(despues)])];
  const out: string[] = [];
  for (const k of claves) {
    const a = antes[k] ?? null;
    const d = despues[k] ?? null;
    if (JSON.stringify(a) === JSON.stringify(d)) continue;
    out.push(`${CAMPOS[k] ?? k}: ${valor(k, a)} → ${valor(k, d)}`);
  }
  return out;
}

const ENTIDAD: Record<Cambio["entidad"], string> = { fila: "movimiento", hoja: "día", mov_chica: "gasto de caja chica", transferencia: "envío a caja chica", config: "saldos iniciales", adjunto: "foto" };

/** Una línea legible por cada cambio del historial. */
export function describirCambio(c: Pick<Cambio, "accion" | "entidad" | "antes" | "despues" | "motivo">): { titulo: string; detalle: string[] } {
  const d = (c.despues ?? c.antes ?? {}) as Record<string, unknown>;
  const nombre = typeof d.descripcion === "string" && d.descripcion ? ` «${d.descripcion}»` : "";
  const que = ENTIDAD[c.entidad];
  switch (c.accion) {
    case "crear":
      return { titulo: c.entidad === "transferencia" ? `Envió ${soles(Number(d.monto))} a caja chica` : `Registró ${que}${nombre}`, detalle: c.entidad === "fila" || c.entidad === "mov_chica" ? resumenNuevo(c.despues) : [] };
    case "editar":
      return { titulo: `Modificó ${que}${nombre}`, detalle: diferencias(c.antes, c.despues) };
    case "eliminar":
      return { titulo: `Eliminó ${que}${nombre}`, detalle: resumenNuevo(c.antes) };
    case "anular":
      return { titulo: `Anuló el envío de ${soles(Number(d.monto))} a caja chica`, detalle: [] };
    case "cerrar": {
      const dif = Number(d.diferencia ?? 0);
      return { titulo: dif === 0 ? "Cerró la caja del día (cuadra)" : `Cerró la caja del día (${dif > 0 ? "sobra" : "falta"} ${soles(Math.abs(dif))})`, detalle: [`efectivo contado: ${soles(Number(d.efectivo_contado))}`, `saldo calculado: ${soles(Number(d.saldo_calculado))}`, ...(c.motivo ? [`nota: ${c.motivo}`] : [])] };
    }
    case "reabrir":
      return { titulo: "Reabrió el día", detalle: [`motivo: ${c.motivo ?? "—"}`] };
    case "config":
      return { titulo: "Cambió los saldos iniciales", detalle: diferencias(c.antes, c.despues) };
    case "subir_foto":
      return { titulo: "Agregó una foto de recibo", detalle: [] };
    case "quitar_foto":
      return { titulo: "Quitó una foto de recibo", detalle: [] };
    default:
      return { titulo: String(c.accion), detalle: [] };
  }
}

function resumenNuevo(v: Record<string, unknown> | null): string[] {
  if (!v) return [];
  const partes: string[] = [];
  for (const k of ["caja_ingreso_efectivo", "caja_ingreso_transf", "caja_salida_efectivo", "caja_salida_transf", "cta_cte_ingreso", "cta_cte_salida", "monto"]) {
    const n = v[k];
    if (typeof n === "number" && n > 0) partes.push(`${CAMPOS[k]}: ${soles(n)}`);
  }
  if (typeof v.categoria === "string" && (CATS as readonly string[]).includes(v.categoria)) partes.push(`categoría: ${v.categoria}`);
  return partes;
}
