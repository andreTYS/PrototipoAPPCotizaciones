/// <reference types="node" />
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { cargarReporte, chicaReporte, hojaReporte, nombreArchivo, totalesReporte, type FuenteDatos, type Reporte } from "./model";
import { generarCsv } from "./csv";
import { generarXlsx } from "./xlsx";
import type { Fila, Hoja, MovChica } from "../caja/types";
import type { State } from "../caja/store";

const OUT = process.env.REPORT_OUT; // si se define, deja los archivos ahí para revisarlos a mano

const f = (n: number, p: Partial<Fila>): Fila => ({
  id: `f${n}`, orden: n, tipo: "OTRO", descripcion: "x", responsable: "Adrián", comprobante: "NINGUNO", caja_ingreso_efectivo: 0, caja_ingreso_transf: 0, caja_salida_efectivo: 0, caja_salida_transf: 0,
  cta_cte_ingreso: 0, cta_cte_salida: 0, categoria: "", subcategoria: "", interno: false, adjuntos: [], updated_at: "", ...p,
});
const foto = (id: string) => ({ id, mime: "image/jpeg", bytes: 1200, synced: true });
const hoja = (ciudad: "AQP" | "MOQ", fecha: string, anterior: number, ctaAnt: number, filas: Fila[], extra: Partial<Hoja> = {}): Hoja => ({
  ciudad, fecha, responsable_caja: "Rosa Quispe", obras_realizadas: "", maletas: "", escaleras: "", encargado_obra: "", saldo_anterior_caja: anterior, saldo_anterior_cta_cte: ctaAnt, filas, updated_at: "", ...extra,
});

// Como las planillas de papel del 21 y 22 de octubre, más un día largo para forzar el salto de página.
const dia21 = hoja("AQP", "2026-10-21", 5890.5, 800, [
  f(1, { descripcion: "Depósito ICR AQP", responsable: "Adrián", caja_salida_efectivo: 5800, cta_cte_ingreso: 5800, interno: true }),
  f(2, { tipo: "VTA", descripcion: "Panel 650 W con inversor", responsable: "Carlos", comprobante: "BOLETA", caja_ingreso_transf: 1100 }),
  f(3, { descripcion: "Compra de plumón indeleble", responsable: "Adrián", caja_salida_efectivo: 3, categoria: "Oficina", adjuntos: [foto("a1")] }),
  f(4, { descripcion: "Carlos sacó 20 soles", responsable: "Carlos", caja_salida_efectivo: 20, categoria: "Movilidad" }),
], { obras_realizadas: "Instalación de paneles en la obra Torre Aurora, nivel 2; revisión de cableado.", maletas: "3", escaleras: "2", encargado_obra: "Luis Mamani Ñahui" });
const largo = Array.from({ length: 24 }, (_, i) => f(i + 1, i % 3 ? { tipo: "OBRA", descripcion: `Cobro valorización N° ${i + 1} — obra con nombre bastante largo para probar el ajuste de línea`, caja_ingreso_efectivo: 100 + i, comprobante: "FACTURA" } : { descripcion: `Gasto ${i + 1}`, caja_salida_efectivo: 7.5, categoria: "Gastos fijos", subcategoria: "Servicios" }));
const dia22 = hoja("AQP", "2026-10-22", 1417.75, 6600, largo);
const moq22 = hoja("MOQ", "2026-10-22", 50, 0, [f(1, { tipo: "VTA", descripcion: "Venta de módulos", caja_ingreso_efectivo: 250.1, caja_ingreso_transf: 0.2 })]);
const mov = (id: string, fecha: string, p: Partial<MovChica>): MovChica => ({ id, ciudad: "AQP", fecha, tipo: "EGRESO", descripcion: "x", persona: "Carlos", categoria: "Movilidad", subcategoria: "", monto: 1, origen: "MANUAL", adjuntos: [], updated_at: fecha, ...p });
const chicaMovs = [
  mov("m1", "2026-10-21", { tipo: "TRANSFERENCIA", descripcion: "Recibido de caja diaria · movilidad", monto: 200, categoria: "", origen: "TRANSFERENCIA", transferencia_id: "t1" }),
  mov("m2", "2026-10-22", { descripcion: "Pasajes a obra", monto: 12.5, adjuntos: [foto("a2")] }),
  mov("m3", "2026-10-22", { descripcion: "Recibo de luz", persona: "Rosa", categoria: "Gastos fijos", subcategoria: "Servicios", monto: 87.9 }),
];

const servidor: FuenteDatos = {
  hojas: async (c, d, h) => [dia21, dia22, moq22].filter((x) => x.ciudad === c && x.fecha >= d && x.fecha <= h),
  chica: async (c) => ({ saldo_anterior: c === "AQP" ? 50 : 0, movimientos: c === "AQP" ? chicaMovs : [] }),
};
const vacio = (): State => ({ v: 1, ciudad: "AQP", config: {}, hojas: {}, chica: { AQP: { saldoBase: 0, movs: [] }, MOQ: { saldoBase: 0, movs: [] } }, outbox: [], responsables: [], avisos: [] });

async function reporte(over: Partial<{ ciudades: ("AQP" | "MOQ")[]; diaria: boolean; chica: boolean; desde: string; hasta: string }> = {}): Promise<Reporte> {
  return cargarReporte({ ciudades: ["AQP", "MOQ"], desde: "2026-10-21", hasta: "2026-10-22", diaria: true, chica: true, usuario: "Rosa Quispe", ...over }, servidor, vacio(), () => "2026-10-22T20:30:00.000Z");
}
const guardar = (n: string, b: Uint8Array) => OUT && (fs.mkdirSync(OUT, { recursive: true }), fs.writeFileSync(path.join(OUT, n), b));

test("el reporte junta hojas y caja chica de ambas ciudades y calcula los saldos", async () => {
  const r = await reporte();
  assert.equal(r.hojas.length, 3);
  assert.deepEqual(r.hojas.map((h) => `${h.fecha} ${h.ciudad}`), ["2026-10-21 AQP", "2026-10-22 AQP", "2026-10-22 MOQ"]);
  const h21 = r.hojas[0];
  assert.equal(h21.saldo_final_caja, 5890.5 + 1100 - 5800 - 3 - 20); // 1167.50
  assert.equal(h21.saldo_final_cta_cte, 6600);
  const c = r.chicas.find((x) => x.ciudad === "AQP")!;
  assert.equal(c.saldoAnterior, 50);
  assert.equal(c.recibido, 200);
  assert.equal(c.gastado, 100.4);
  assert.equal(c.saldoFinal, 149.6);
  assert.deepEqual(c.movs.map((m) => m.saldo), [250, 237.5, 149.6]);
  assert.equal(totalesReporte(r).movimientos, 4 + 24 + 1);
  assert.equal(nombreArchivo(r), "caja_AQP-MOQ_2026-10-21_a_2026-10-22");
  assert.equal(nombreArchivo({ ...r, chica: false, ciudades: ["MOQ"], desde: "2026-10-22", hasta: "2026-10-22" }), "caja-diaria_MOQ_2026-10-22");
});

test("sin conexión, el reporte se arma con lo del dispositivo y lo avisa", async () => {
  const sinRed: FuenteDatos = { hojas: async () => Promise.reject(Object.assign(new Error("x"), { status: 0 })), chica: async () => Promise.reject(Object.assign(new Error("x"), { status: 0 })) };
  const local = vacio();
  local.hojas["AQP:2026-10-22"] = dia22;
  local.hojas["AQP:2026-09-01"] = dia21; // fuera del periodo
  local.chica.AQP = { saldoBase: 10, movs: chicaMovs };
  const r = await cargarReporte({ ciudades: ["AQP"], desde: "2026-10-22", hasta: "2026-10-22", diaria: true, chica: true, usuario: "x" }, sinRed, local);
  assert.equal(r.desdeLocal, true);
  assert.equal(r.hojas.length, 1, "solo el día pedido");
  // el saldo anterior de la ventana incluye lo previo (el envío de 200 del día 21): 10 + 200
  assert.equal(r.chicas[0].saldoAnterior, 210);
  assert.equal(r.chicas[0].saldoFinal, 210 - 12.5 - 87.9);
  // un error que no es de red NO se esconde detrás de los datos locales
  await assert.rejects(() => cargarReporte({ ciudades: ["AQP"], desde: "a", hasta: "b", diaria: true, chica: false, usuario: "x" }, { ...servidor, hojas: async () => Promise.reject(Object.assign(new Error("fecha inválida"), { status: 400 })) }, vacio()), /fecha inválida/);
});

test("CSV: tildes y ñ intactas, comillas y comas bien escapadas, importes con punto decimal", async () => {
  const r = await reporte();
  const bytes = generarCsv(r);
  guardar("reporte.csv", bytes);
  const txt = new TextDecoder().decode(bytes);
  assert.deepEqual([...bytes.slice(0, 3)], [0xef, 0xbb, 0xbf], "BOM UTF-8 para que Excel respete las tildes");
  assert.match(txt, /Instalación|Depósito ICR AQP/);
  assert.match(txt, /Luis|CAJA DIARIA/);
  assert.match(txt, /2026-10-21,Arequipa,1,Otro,Depósito ICR AQP,Adrián,,0\.00,0\.00,5800\.00,0\.00,5800\.00,0\.00,,Sí,0/);
  assert.match(txt, /Gastos fijos · Servicios/);
  assert.match(txt, /\r\nCAJA CHICA\r\n/);
  const conComa = structuredClone(await reporte()); // copia: el ejemplo es compartido con las demás pruebas
  conComa.hojas[0].filas[0].descripcion = 'Compra de "cemento", 40 bolsas';
  assert.match(new TextDecoder().decode(generarCsv(conComa)), /"Compra de ""cemento"", 40 bolsas"/);
});

test("Excel: hojas, valores numéricos reales, formatos, filtros, fila congelada y totales con fórmula", async () => {
  const r = await reporte();
  const bytes = await generarXlsx(r);
  guardar("reporte.xlsx", bytes);
  const ExcelJS = (await import("exceljs")).default;
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(bytes as unknown as ArrayBuffer);
  assert.deepEqual(wb.worksheets.map((w) => w.name), ["Resumen", "Caja diaria", "Responsable de caja", "Caja chica"]);

  const cd = wb.getWorksheet("Caja diaria")!;
  assert.equal(cd.views[0].state, "frozen", "los títulos quedan fijos al bajar");
  assert.ok(cd.autoFilter, "tiene filtros");
  const h = cd.getRow(4).values as unknown[];
  assert.equal(h[1], "Fecha");
  assert.equal(h[8], "Ingreso efectivo");
  const fila1 = cd.getRow(5);
  assert.equal(fila1.getCell(5).value, "Depósito ICR AQP");
  assert.equal(fila1.getCell(10).value, 5800, "los importes son NÚMEROS, no texto (se pueden sumar)");
  assert.equal(typeof fila1.getCell(10).value, "number");
  assert.equal(fila1.getCell(10).numFmt?.includes("#,##0.00"), true);
  assert.equal(fila1.getCell(15).value, "Sí", "movimiento interno marcado");
  assert.ok(fila1.getCell(1).value instanceof Date, "la fecha es una fecha real de Excel");
  const ultima = cd.getRow(5 + 4 + 24 + 1); // 29 movimientos + la fila de total
  const totalIng = ultima.getCell(8).value as { formula: string; result: number };
  assert.match(totalIng.formula, /^SUBTOTAL\(109,H5:H33\)$/);
  const esperado = r.hojas.flatMap((x) => x.filas).reduce((a, x) => a + x.caja_ingreso_efectivo, 0);
  assert.equal(totalIng.result, Math.round(esperado * 100) / 100);

  const res = wb.getWorksheet("Resumen")!;
  const dias: unknown[][] = [];
  res.eachRow((row) => { const v = row.values as unknown[]; if (v[2] === "Arequipa" || v[2] === "Moquegua") dias.push(v); });
  assert.equal(dias.length, 3, "un renglón por día y ciudad");
  assert.equal(dias[0][6], 5890.5 + 1100 - 5800 - 3 - 20, "saldo final del día 21");

  const ch = wb.getWorksheet("Caja chica")!;
  assert.equal(ch.getRow(5).getCell(9).value, 250, "saldo acumulado tras el primer movimiento");
  const ob = wb.getWorksheet("Responsable de caja")!;
  assert.equal(ob.getRow(5).getCell(3).value, "Rosa Quispe");
  assert.equal(ob.getRow(4).getCell(4).value, null, "ya no hay columnas de obras, maletas, escaleras ni encargado");

  // elegir solo un libro deja solo esa hoja
  const solo = new ExcelJS.Workbook();
  await solo.xlsx.load((await generarXlsx(await reporte({ diaria: false }))) as unknown as ArrayBuffer);
  assert.deepEqual(solo.worksheets.map((w) => w.name), ["Resumen", "Caja chica"]);
});

import { diasDeRango, errorDeRango, rangoPreset } from "./periodo";

test("períodos rápidos: semana desde el lunes, mes y mes pasado", () => {
  // 2026-10-22 es jueves
  assert.deepEqual(rangoPreset("hoy", "2026-10-22"), { desde: "2026-10-22", hasta: "2026-10-22" });
  assert.deepEqual(rangoPreset("ayer", "2026-10-22"), { desde: "2026-10-21", hasta: "2026-10-21" });
  assert.deepEqual(rangoPreset("semana", "2026-10-22"), { desde: "2026-10-19", hasta: "2026-10-22" });
  assert.deepEqual(rangoPreset("semana", "2026-10-19"), { desde: "2026-10-19", hasta: "2026-10-19" }); // lunes
  assert.deepEqual(rangoPreset("semana", "2026-10-25"), { desde: "2026-10-19", hasta: "2026-10-25" }); // domingo
  assert.deepEqual(rangoPreset("mes", "2026-10-22"), { desde: "2026-10-01", hasta: "2026-10-22" });
  assert.deepEqual(rangoPreset("mes-pasado", "2026-10-22"), { desde: "2026-09-01", hasta: "2026-09-30" });
  assert.deepEqual(rangoPreset("mes-pasado", "2026-01-15"), { desde: "2025-12-01", hasta: "2025-12-31" }); // cruza de año
  assert.deepEqual(rangoPreset("mes-pasado", "2026-03-31"), { desde: "2026-02-01", hasta: "2026-02-28" });
});

test("rango: días y errores", () => {
  assert.equal(diasDeRango("2026-10-01", "2026-10-01"), 1);
  assert.equal(diasDeRango("2026-10-01", "2026-10-22"), 22);
  assert.equal(diasDeRango("2026-03-01", "2026-04-01"), 32); // cambio de hora no cuenta como día
  assert.equal(errorDeRango("2026-10-01", "2026-10-22"), "");
  assert.match(errorDeRango("2026-10-22", "2026-10-01"), /posterior/);
  assert.match(errorDeRango("", "2026-10-01"), /dos fechas/);
  assert.match(errorDeRango("2025-01-01", "2026-10-01"), /hasta 366/);
});
