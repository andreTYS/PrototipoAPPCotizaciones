/// <reference types="node" />
import { test } from "node:test";
import assert from "node:assert/strict";
import { findFecha, findMonto, parseAmount, parseComprobante, rowsFromLines } from "./parseComprobante";

const NOW = new Date(2026, 8, 28); // 28 sep 2026
const lines = (s: string) => s.trim().split("\n");

test("parseAmount handles Peruvian and European separators", () => {
  assert.equal(parseAmount("1,240.00"), 1240);
  assert.equal(parseAmount("1.240,00"), 1240);
  assert.equal(parseAmount("215,50"), 215.5);
  assert.equal(parseAmount("S/ 680"), 680);
  assert.equal(parseAmount("12 500.00"), 12500);
});

test("factura de ferretería", () => {
  const r = parseComprobante(
    lines(`
FERRETERIA EL CONSTRUCTOR S.A.C.
RUC 20512345678
AV. LOS HEROES 1234 - SAN JUAN DE MIRAFLORES - LIMA
FACTURA ELECTRONICA
F001-00012345
Fecha de emision: 26/09/2026
CANT DESCRIPCION P.UNIT IMPORTE
40 CEMENTO PORTLAND TIPO I 42.5KG 26.27 1,050.85
OP. GRAVADA S/ 1,050.85
IGV 18% S/ 189.15
IMPORTE TOTAL S/ 1,240.00
`),
    NOW,
  );
  assert.equal(r.monto, "1240.00");
  assert.equal(r.fecha, "2026-09-26");
  assert.equal(r.persona, "FERRETERIA EL CONSTRUCTOR S.A.C.");
  assert.equal(r.ciudad, "Lima");
  assert.equal(r.categoria, "Material");
  assert.equal(r.desc, "Cemento portland tipo i 42.5kg");
});

test("captura de Yape", () => {
  const r = parseComprobante(
    lines(`
¡Yapeaste!
S/ 215.50
Juan Pérez Quispe
27 set. 2026 - 10:15 am
Nro. de operación
03458921
`),
    NOW,
  );
  assert.equal(r.monto, "215.50");
  assert.equal(r.fecha, "2026-09-27");
  assert.equal(r.persona, "Juan Pérez Quispe");
  assert.equal(r.desc, "Transferencia a Juan Pérez Quispe");
});

test("ticket de grifo en Arequipa", () => {
  const r = parseComprobante(
    lines(`
GRIFO SANTA ROSA E.I.R.L.
Av. Ejercito 505 Cayma Arequipa
RUC: 20455667788
BOLETA DE VENTA ELECTRONICA B002-5566
FECHA: 25-09-2026 HORA: 08:12
DIESEL B5 S-50 12.35 GAL 17.45 215.50
SUBTOTAL 182.63
IGV 32.87
TOTAL: S/ 215.50
EFECTIVO 250.00
VUELTO 34.50
`),
    NOW,
  );
  assert.equal(r.monto, "215.50");
  assert.equal(r.fecha, "2026-09-25");
  assert.equal(r.persona, "GRIFO SANTA ROSA E.I.R.L.");
  assert.equal(r.ciudad, "Arequipa");
  assert.equal(r.categoria, "Movilidad");
});

test("boleta de restaurante con total en la línea siguiente", () => {
  const r = parseComprobante(
    lines(`
CEVICHERIA EL PESCADOR
Jr. Pizarro 455 Trujillo
BOLETA ELECTRONICA
Fecha: 24 de septiembre de 2026
2 MENU EJECUTIVO 18.00 36.00
TOTAL A PAGAR
S/ 36.00
`),
    NOW,
  );
  assert.equal(r.monto, "36.00");
  assert.equal(r.fecha, "2026-09-24");
  assert.equal(r.persona, "CEVICHERIA EL PESCADOR");
  assert.equal(r.ciudad, "Trujillo");
  assert.equal(r.categoria, "Viáticos");
});

test("fechas futuras o inválidas se ignoran y se usa hoy", () => {
  assert.equal(findFecha(["Vence: 31/02/2026"], NOW), "2026-09-28");
  assert.equal(findFecha(["Fecha 15/10/2027"], NOW), "2026-09-28");
});

test("sin etiqueta de total usa el mayor monto con S/", () => {
  assert.equal(findMonto(["Cemento S/ 26.00", "Arena S/ 120.50", "RUC 20512345678"]), 120.5);
});

test("texto sin datos útiles deja campos vacíos", () => {
  const r = parseComprobante(["Hola", "mundo"], NOW);
  assert.equal(r.monto, "");
  assert.equal(r.categoria, "");
  assert.equal(r.ciudad, "");
});

test("rowsFromLines une columnas de la misma fila", () => {
  const f = (left: number, top: number, w = 100) => ({ left, top, right: left + w, bottom: top + 20 });
  const rows = rowsFromLines([
    { text: "S/ 215.50", frame: f(300, 402) },
    { text: "GRIFO SANTA ROSA", frame: f(50, 10, 250) },
    { text: "TOTAL:", frame: f(40, 400) },
    { text: "SUBTOTAL", frame: f(40, 360) },
    { text: "182.63", frame: f(300, 358) },
  ]);
  assert.deepEqual(rows, ["GRIFO SANTA ROSA", "SUBTOTAL 182.63", "TOTAL: S/ 215.50"]);
});

test("gastos fijos: sueldos, alquiler y servicios", () => {
  const sueldo = parseComprobante(lines("PAGO DE PLANILLA QUINCENAL\nTOTAL S/ 6,200.00"), NOW);
  assert.equal(sueldo.categoria, "Gastos fijos");
  assert.equal(sueldo.subcategoria, "Sueldos");

  const luz = parseComprobante(lines("LUZ DEL SUR S.A.A.\nRecibo de luz setiembre\nTOTAL A PAGAR S/ 312.40"), NOW);
  assert.equal(luz.categoria, "Gastos fijos");
  assert.equal(luz.subcategoria, "Servicios");

  const local = parseComprobante(lines("RECIBO DE ALQUILER DE LOCAL\nMes de septiembre\nTOTAL S/ 1,500.00"), NOW);
  assert.equal(local.categoria, "Gastos fijos");
  assert.equal(local.subcategoria, "Alquiler");
});

test("alquiler de maquinaria sigue siendo Equipos y no tiene subcategoría", () => {
  const r = parseComprobante(lines("ALQUILER DE MEZCLADORA 3 DIAS\nTOTAL S/ 450.00"), NOW);
  assert.equal(r.categoria, "Equipos");
  assert.equal(r.subcategoria, "");
});
