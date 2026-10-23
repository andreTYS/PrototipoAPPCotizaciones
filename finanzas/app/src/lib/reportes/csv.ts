/** CSV (UTF-8 con BOM para que Excel respete las tildes). Un solo archivo; Caja diaria y Caja chica van en secciones. */
import { COMPROBANTE_LABEL, TIPO_FILA_LABEL, CIUDAD_LABEL } from "../caja/types";
import { categoriaTexto, nombreCiudades, periodoTexto, type Reporte } from "./model";

const celda = (v: string | number | boolean) => {
  const s = typeof v === "boolean" ? (v ? "Sí" : "No") : String(v);
  return /[",\n\r;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const linea = (xs: (string | number | boolean)[]) => xs.map(celda).join(",");
const imp = (n: number) => n.toFixed(2); // punto decimal, sin separador de miles: lo que espera cualquier hoja de cálculo

export function generarCsv(r: Reporte): Uint8Array {
  const L: string[] = [];
  L.push(linea(["ICR Finanzas - Reporte de caja"]));
  L.push(linea([`${nombreCiudades(r.ciudades)} · ${periodoTexto(r.desde, r.hasta)}`]));
  L.push("");
  if (r.diaria) {
    L.push(linea(["CAJA DIARIA"]));
    L.push(linea(["Fecha", "Ciudad", "N°", "Tipo", "Descripción", "Responsable", "Comprobante", "Ingreso efectivo", "Ingreso Yape/Transf.", "Salida efectivo", "Salida Yape/Transf.", "Cta. cte. ingreso", "Cta. cte. salida", "Categoría", "Movimiento interno", "Fotos"]));
    for (const h of r.hojas)
      h.filas.forEach((f, i) =>
        L.push(linea([h.fecha, CIUDAD_LABEL[h.ciudad], i + 1, TIPO_FILA_LABEL[f.tipo], f.descripcion, f.responsable, f.comprobante === "NINGUNO" ? "" : COMPROBANTE_LABEL[f.comprobante], imp(f.caja_ingreso_efectivo), imp(f.caja_ingreso_transf), imp(f.caja_salida_efectivo), imp(f.caja_salida_transf), imp(f.cta_cte_ingreso), imp(f.cta_cte_salida), categoriaTexto(f.categoria, f.subcategoria), f.interno, f.adjuntos.length])),
      );
    L.push("");
  }
  if (r.chica) {
    L.push(linea(["CAJA CHICA"]));
    L.push(linea(["Fecha", "Ciudad", "Tipo", "Descripción", "Persona", "Categoría", "Ingreso", "Egreso", "Saldo", "Fotos"]));
    for (const c of r.chicas)
      for (const m of c.movs) L.push(linea([m.fecha, CIUDAD_LABEL[m.ciudad], m.tipo === "TRANSFERENCIA" ? "Envío desde caja diaria" : "Egreso", m.descripcion, m.persona, categoriaTexto(m.categoria, m.subcategoria), m.tipo === "TRANSFERENCIA" ? imp(m.monto) : "", m.tipo === "EGRESO" ? imp(m.monto) : "", imp(m.saldo), m.adjuntos.length]));
  }
  return new TextEncoder().encode("﻿" + L.join("\r\n") + "\r\n");
}
