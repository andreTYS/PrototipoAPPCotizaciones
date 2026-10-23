/**
 * Reflejo de la caja en el ERP (Contabilidad → Flujo de caja).
 *
 * Cada fila de la hoja del día y cada egreso de caja chica que sea un ingreso o gasto REAL genera un
 * registro en el ERP. Lo que no lo es (depósitos al banco, retiros, envíos a caja chica) no se refleja.
 *
 * Los valores de `tipo` y `categoria` son los mismos que ya usaba la app con POST /income y POST /expenses
 * (OBRA_PROYECTO, VENTA, EQUIPOS_OBRA, SUELDO, …). `channel` también: usamos "web", que sabemos que el ERP
 * acepta; si el ERP tiene un canal propio para esto, se cambia en `CHANNEL`.
 */
import { montosParaErp } from "../../app/src/lib/caja/calc";
import type { Fila, MovChica } from "../../app/src/lib/caja/types";
import { CIUDAD_LABEL, type Ciudad } from "../../app/src/lib/caja/types";
import type { Usuario } from "./auth";

const CHANNEL = "web";

export type PayloadIngreso = { tipo: string; detalle: string; monto: number; fecha: string; channel: string };
export type PayloadGasto = { categoria: string; descripcion: string; monto: number; fecha: string; persona_texto: string | null; ciudad: string | null; channel: string };

const TIPO_INGRESO: Record<string, string> = { VTA: "VENTA", OBRA: "OBRA_PROYECTO", OTRO: "OTRO" };
const CATEGORIA: Record<string, string> = {
  Equipos: "EQUIPOS_OBRA",
  "Caja chica": "OTROS",
  Movilidad: "MOVILIDAD",
  Material: "MATERIAL",
  Oficina: "OFICINA",
  Fletes: "FLETES",
  Viáticos: "VIATICOS",
  Proveedores: "OTROS",
  "Gastos fijos": "OTROS",
};
const SUBCATEGORIA: Record<string, string> = { Sueldos: "SUELDO", Alquiler: "ALQUILER", Servicios: "SERVICIOS" };

export const categoriaErp = (categoria: string, subcategoria: string) =>
  categoria === "Gastos fijos" && subcategoria ? SUBCATEGORIA[subcategoria] ?? "OTROS" : CATEGORIA[categoria] ?? "OTROS";

/** Lo que una fila manda al ERP: como mucho un ingreso y un gasto (null = no corresponde). */
export function payloadsDeFila(f: Fila, ciudad: Ciudad, fecha: string): { ingreso: PayloadIngreso | null; gasto: PayloadGasto | null } {
  const { ingreso, salida } = montosParaErp(f);
  return {
    ingreso: ingreso > 0 ? { tipo: TIPO_INGRESO[f.tipo] ?? "OTRO", detalle: f.descripcion, monto: ingreso, fecha, channel: CHANNEL } : null,
    gasto:
      salida > 0
        ? { categoria: categoriaErp(f.categoria, f.subcategoria), descripcion: f.descripcion, monto: salida, fecha, persona_texto: f.responsable || null, ciudad: CIUDAD_LABEL[ciudad], channel: CHANNEL }
        : null,
  };
}

/** Un egreso de caja chica es siempre un gasto; las transferencias recibidas no se reflejan. */
export function payloadDeMovChica(m: Pick<MovChica, "tipo" | "descripcion" | "monto" | "fecha" | "persona" | "categoria" | "subcategoria" | "ciudad">): PayloadGasto | null {
  if (m.tipo !== "EGRESO") return null;
  return { categoria: categoriaErp(m.categoria, m.subcategoria), descripcion: m.descripcion, monto: m.monto, fecha: m.fecha, persona_texto: m.persona || null, ciudad: CIUDAD_LABEL[m.ciudad], channel: CHANNEL };
}

export interface ErpMirror {
  crearIngreso(p: PayloadIngreso, u: Usuario): Promise<string>;
  actualizarIngreso(id: string, p: PayloadIngreso, u: Usuario): Promise<void>;
  anularIngreso(id: string, u: Usuario): Promise<void>;
  crearGasto(p: PayloadGasto, u: Usuario): Promise<string>;
  actualizarGasto(id: string, p: PayloadGasto, u: Usuario): Promise<void>;
  anularGasto(id: string, u: Usuario): Promise<void>;
}

/** Sin reflejo: la caja funciona sola y no manda nada al ERP. */
export const sinEspejo: ErpMirror = {
  crearIngreso: async () => "",
  actualizarIngreso: async () => {},
  anularIngreso: async () => {},
  crearGasto: async () => "",
  actualizarGasto: async () => {},
  anularGasto: async () => {},
};

/**
 * Reflejo por HTTP contra la API del ERP, reenviando el token de la persona que registró (igual que hacía
 * la app): el ERP ve el movimiento a nombre de esa persona y aplica sus permisos.
 *
 * ⚠ SUPUESTOS A VERIFICAR: crear usa POST /income y POST /expenses y devuelve el id en
 * data.ingreso.ingreso_id / data.gasto.gasto_id (así lo hace la app hoy, verificado). Actualizar y anular
 * usan PUT/DELETE /income/:id y /expenses/:id: NO sabemos si el ERP los tiene. Si esta API vive dentro del
 * ERP, lo correcto es escribir directo en sus tablas y no pasar por HTTP.
 */
export function espejoHttp(baseUrl: string, fetchFn: typeof fetch = fetch): ErpMirror {
  const base = baseUrl.replace(/\/+$/, "");
  const llamar = async (metodo: string, ruta: string, u: Usuario, cuerpo?: unknown) => {
    const res = await fetchFn(`${base}${ruta}`, {
      method: metodo,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${u.token ?? ""}` },
      body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
    });
    const body = (await res.json().catch(() => null)) as { status?: string; data?: any; error?: { message?: string } } | null;
    if (!res.ok || (body && body.status && body.status !== "success")) throw new Error(body?.error?.message || `El ERP respondió ${res.status} en ${metodo} ${ruta}`);
    return body?.data;
  };
  return {
    crearIngreso: async (p, u) => String((await llamar("POST", "/income", u, p)).ingreso.ingreso_id),
    actualizarIngreso: async (id, p, u) => void (await llamar("PUT", `/income/${encodeURIComponent(id)}`, u, p)),
    anularIngreso: async (id, u) => void (await llamar("DELETE", `/income/${encodeURIComponent(id)}`, u)),
    crearGasto: async (p, u) => String((await llamar("POST", "/expenses", u, p)).gasto.gasto_id),
    actualizarGasto: async (id, p, u) => void (await llamar("PUT", `/expenses/${encodeURIComponent(id)}`, u, p)),
    anularGasto: async (id, u) => void (await llamar("DELETE", `/expenses/${encodeURIComponent(id)}`, u)),
  };
}
