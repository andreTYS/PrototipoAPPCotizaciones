/// <reference types="node" />
import { test } from "node:test";
import assert from "node:assert/strict";
import { aperturaEstimada, conSaldoAcumulado, fusionarHoja, fusionarMovs, montosParaErp, saldoChica, saldosHoja, totalesHoja, validarFila, r2, type Pendientes } from "./calc";
import type { Fila, Hoja, MovChica } from "./types";

const fila = (p: Partial<Fila> = {}): Fila => ({
  id: "f" + Math.random().toString(36).slice(2),
  orden: 1,
  tipo: "OTRO",
  descripcion: "x",
  responsable: "Adrian",
  comprobante: "NINGUNO",
  caja_ingreso_efectivo: 0,
  caja_ingreso_transf: 0,
  caja_salida_efectivo: 0,
  caja_salida_transf: 0,
  cta_cte_ingreso: 0,
  cta_cte_salida: 0,
  categoria: "",
  subcategoria: "",
  interno: false,
  adjuntos: [],
  updated_at: "2026-10-21T10:00:00Z",
  ...p,
});

const hoja = (p: Partial<Hoja> = {}): Hoja => ({
  ciudad: "AQP",
  fecha: "2026-10-21",
  responsable_caja: "",
  obras_realizadas: "",
  maletas: "",
  escaleras: "",
  encargado_obra: "",
  saldo_anterior_caja: 0,
  saldo_anterior_cta_cte: 0,
  filas: [],
  updated_at: "2026-10-21T10:00:00Z",
  ...p,
});

// Un día parecido a la planilla del 21 de octubre: depósito a la cuenta, un cobro por Yape y dos gastos chicos.
const DIA = hoja({
  saldo_anterior_caja: 5890.5,
  saldo_anterior_cta_cte: 800,
  filas: [
    fila({ id: "a", descripcion: "Depósito ICR AQP", caja_salida_efectivo: 5800, cta_cte_ingreso: 5800, interno: true }),
    fila({ id: "b", tipo: "VTA", descripcion: "Venta de panel", caja_ingreso_efectivo: 1100, caja_ingreso_transf: 250.25 }),
    fila({ id: "c", descripcion: "Compra de plumón indeleble", caja_salida_efectivo: 3, categoria: "Oficina" }),
    fila({ id: "d", descripcion: "Carlos sacó 20 soles", caja_salida_efectivo: 20, categoria: "Movilidad" }),
  ],
});

test("totales por columna, como el pie de la planilla", () => {
  const t = totalesHoja(DIA.filas);
  assert.deepEqual(t.efectivo, { ingreso: 1100, salida: 5823, total: -4723 });
  assert.deepEqual(t.transf, { ingreso: 250.25, salida: 0, total: 250.25 });
  assert.deepEqual(t.caja, { ingreso: 1350.25, salida: 5823, total: -4472.75 });
  assert.deepEqual(t.cta_cte, { ingreso: 5800, salida: 0, total: 5800 });
});

test("saldo final = saldo anterior + ingresos − salidas (caja y cuenta corriente por separado)", () => {
  const s = saldosHoja(DIA);
  assert.equal(s.saldo_final_caja, 1417.75); // 5890.50 + 1350.25 − 5823
  assert.equal(s.saldo_final_cta_cte, 6600);
});

test("los decimales no arrastran errores de punto flotante", () => {
  assert.equal(totalesHoja([fila({ caja_ingreso_efectivo: 0.1 }), fila({ caja_ingreso_efectivo: 0.2 })]).efectivo.ingreso, 0.3);
  assert.equal(r2(1.005 + 1.005), 2.01);
});

test("solo lo que es ingreso o gasto real va al ERP: el depósito al banco no", () => {
  assert.deepEqual(montosParaErp(DIA.filas[0]), { ingreso: 0, salida: 0 });
  assert.deepEqual(montosParaErp(DIA.filas[1]), { ingreso: 1350.25, salida: 0 });
  assert.deepEqual(montosParaErp(DIA.filas[2]), { ingreso: 0, salida: 3 });
  // un cobro directo a la cuenta corriente también es ingreso
  assert.equal(montosParaErp(fila({ cta_cte_ingreso: 900 })).ingreso, 900);
});

test("validación de una fila", () => {
  assert.deepEqual(validarFila(fila({ caja_ingreso_efectivo: 10 })), {});
  assert.ok(validarFila(fila({ descripcion: " " })).descripcion);
  assert.ok(validarFila(fila({ responsable: "" })).responsable);
  assert.ok(validarFila(fila()).montos, "sin ningún importe");
  assert.ok(validarFila(fila({ caja_salida_efectivo: -5 })).montos);
  // una salida real necesita categoría (el ERP la exige)…
  assert.ok(validarFila(fila({ caja_salida_efectivo: 5 })).categoria);
  assert.deepEqual(validarFila(fila({ caja_salida_efectivo: 5, categoria: "Material" })), {});
  // …salvo que sea un movimiento interno
  assert.deepEqual(validarFila(fila({ caja_salida_efectivo: 5, interno: true })), {});
  // Gastos fijos pide su subcategoría
  assert.ok(validarFila(fila({ caja_salida_efectivo: 5, categoria: "Gastos fijos" })).subcategoria);
  assert.deepEqual(validarFila(fila({ caja_salida_efectivo: 5, categoria: "Gastos fijos", subcategoria: "Servicios" })), {});
});

test("caja chica: las transferencias suman y los egresos restan", () => {
  const movs = [
    { tipo: "TRANSFERENCIA", monto: 500 },
    { tipo: "EGRESO", monto: 120.5 },
    { tipo: "EGRESO", monto: 30 },
  ] as MovChica[];
  assert.equal(saldoChica(100, movs), 449.5);
  assert.deepEqual(conSaldoAcumulado(100, movs).map((m) => m.saldo), [600, 479.5, 449.5]);
});

test("una hoja nueva abre con el cierre de la anterior más reciente (o con el saldo inicial)", () => {
  const cfg = { saldo_inicial_caja: 100, saldo_inicial_cta_cte: 50 };
  assert.deepEqual(aperturaEstimada([], "2026-10-22", cfg), { saldo_anterior_caja: 100, saldo_anterior_cta_cte: 50 });
  const ayer = DIA;
  const antiayer = hoja({ fecha: "2026-10-19", saldo_anterior_caja: 1, filas: [fila({ caja_ingreso_efectivo: 1 })] });
  assert.deepEqual(aperturaEstimada([antiayer, ayer], "2026-10-22", cfg), { saldo_anterior_caja: 1417.75, saldo_anterior_cta_cte: 6600 });
  // un día que ya pasó solo mira hacia atrás: parte del cierre del 19 (caja 1 + 1; la cuenta corriente de esa hoja abrió en 0)
  assert.deepEqual(aperturaEstimada([antiayer, ayer], "2026-10-20", cfg), { saldo_anterior_caja: 2, saldo_anterior_cta_cte: 0 });
});

const sinPend = (): Pendientes => ({ filasPendientes: new Set(), filasBorradas: new Set(), adjuntosBorrados: new Set(), hojaSucia: false });

test("sincronizar: lo del servidor manda, pero nunca se pierde lo pendiente", () => {
  const local = hoja({
    responsable_caja: "Local",
    filas: [fila({ id: "a", descripcion: "editada aquí" }), fila({ id: "nueva", orden: 5, descripcion: "creada sin conexión" }), fila({ id: "b", descripcion: "borrada aquí" })],
  });
  const servidor = hoja({
    id: "H1",
    responsable_caja: "Servidor",
    saldo_anterior_caja: 99,
    filas: [fila({ id: "a", descripcion: "versión vieja" }), fila({ id: "b", descripcion: "borrada aquí" }), fila({ id: "otro", orden: 2, descripcion: "de otro dispositivo" })],
  });
  const p = sinPend();
  p.filasPendientes.add("a");
  p.filasPendientes.add("nueva");
  p.filasBorradas.add("b");
  p.hojaSucia = true;
  const r = fusionarHoja(local, servidor, p);
  assert.equal(r.id, "H1");
  assert.equal(r.saldo_anterior_caja, 99, "los saldos de apertura siempre vienen del servidor");
  assert.equal(r.responsable_caja, "Local", "encabezado editado y sin enviar");
  assert.deepEqual(r.filas.map((f) => [f.id, f.descripcion]), [
    ["a", "editada aquí"],
    ["otro", "de otro dispositivo"],
    ["nueva", "creada sin conexión"],
  ]);
  // sin pendientes, el servidor gana en todo
  const limpio = fusionarHoja(local, servidor, sinPend());
  assert.equal(limpio.responsable_caja, "Servidor");
  assert.deepEqual(limpio.filas.map((f) => f.id).sort(), ["a", "b", "otro"]);
});

test("sincronizar: conserva la copia local de las fotos y las que aún no subieron", () => {
  const foto = (id: string, synced: boolean, localKey?: string) => ({ id, mime: "image/jpeg", bytes: 10, synced, localKey });
  const local = hoja({ filas: [fila({ id: "a", adjuntos: [foto("f1", true, "k1"), foto("f2", false, "k2")] })] });
  const servidor = hoja({ filas: [fila({ id: "a", adjuntos: [foto("f1", true)] })] });
  const [f] = fusionarHoja(local, servidor, sinPend()).filas;
  assert.deepEqual(f.adjuntos.map((a) => [a.id, a.localKey, a.synced]), [["f1", "k1", true], ["f2", "k2", false]]);
});

test("sincronizar caja chica", () => {
  const m = (id: string, fecha: string, extra: Partial<MovChica> = {}): MovChica => ({
    id, ciudad: "AQP", fecha, tipo: "EGRESO", descripcion: id, persona: "", categoria: "Material", subcategoria: "", monto: 10, origen: "MANUAL", adjuntos: [], updated_at: fecha, ...extra,
  });
  const local = [m("a", "2026-10-20", { descripcion: "local" }), m("n", "2026-10-22"), m("x", "2026-10-21")];
  const servidor = [m("a", "2026-10-20", { descripcion: "servidor" }), m("x", "2026-10-21"), m("z", "2026-10-19")];
  const r = fusionarMovs(local, servidor, new Set(["a", "n"]), new Set(["x"]));
  assert.deepEqual(r.map((x) => [x.id, x.descripcion]), [["z", "z"], ["a", "local"], ["n", "n"]]);
});
