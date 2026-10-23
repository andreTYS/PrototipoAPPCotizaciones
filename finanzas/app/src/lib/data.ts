/**
 * Categorías de gasto (las mismas en Caja diaria y Caja chica) y el tipo `Egreso` que produce el OCR de
 * comprobantes. Los datos de la caja en sí (hojas, filas, movimientos) están en lib/caja/.
 * Sin dependencias de React Native: también lo importa la API de referencia.
 */

export const CATS = ["Equipos", "Caja chica", "Movilidad", "Material", "Oficina", "Fletes", "Viáticos", "Proveedores", "Gastos fijos"] as const;
/** Categorías que abren un segundo selector. */
export const SUBCATS = { "Gastos fijos": ["Sueldos", "Alquiler", "Servicios"] } as const;

export type Categoria = (typeof CATS)[number];
export type Subcategoria = (typeof SUBCATS)["Gastos fijos"][number];

/** Texto guardado en un movimiento y mostrado en las listas: "Gastos fijos · Sueldos". */
export const catLabel = (categoria: string, subcategoria?: string) => (subcategoria ? `${categoria} · ${subcategoria}` : categoria);

/** Lo que el OCR lee de un comprobante (los importes van como texto, tal cual se escriben en el formulario). */
export type Egreso = { fecha: string; persona: string; desc: string; ciudad: string; categoria: Categoria | ""; subcategoria: Subcategoria | ""; monto: string };
