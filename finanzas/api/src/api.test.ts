/// <reference types="node" />
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { applyMigrations, pgliteDb, type Db } from "./db";
import { authDesdeEntorno } from "./auth";
import { memoryStorage } from "./storage";
import type { ErpMirror } from "./erp";
import { crearServicio } from "./service";
import { crearServidor } from "./server";

// Espejo falso del ERP: anota cada llamada y puede fallar a pedido.
type Llamada = { op: string; id?: string; p?: any };
const llamadas: Llamada[] = [];
const ultimaLlamada = () => llamadas[llamadas.length - 1];
let erpCaido = false;
let seq = 0;
const falla = () => {
  if (erpCaido) throw new Error("ERP caído (simulado)");
};
const espejo: ErpMirror = {
  crearIngreso: async (p) => (falla(), llamadas.push({ op: "crearIngreso", p }), `ING-${++seq}`),
  actualizarIngreso: async (id, p) => (falla(), void llamadas.push({ op: "actualizarIngreso", id, p })),
  anularIngreso: async (id) => (falla(), void llamadas.push({ op: "anularIngreso", id })),
  crearGasto: async (p) => (falla(), llamadas.push({ op: "crearGasto", p }), `GAS-${++seq}`),
  actualizarGasto: async (id, p) => (falla(), void llamadas.push({ op: "actualizarGasto", id, p })),
  anularGasto: async (id) => (falla(), void llamadas.push({ op: "anularGasto", id })),
};

let db: Db;
let base = "";
let server: ReturnType<typeof crearServidor>;
const storage = memoryStorage();

before(async () => {
  db = await pgliteDb();
  await applyMigrations(db);
  const env = { AUTH_MODE: "dev", ADMIN_ROLES: "ADMIN" } as NodeJS.ProcessEnv;
  server = crearServidor({ auth: authDesdeEntorno(env), svc: crearServicio({ db, storage, mirror: espejo, env, hoy: () => "2026-10-22" }) });
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(async () => {
  server.close();
  await db.close();
});

type R = { status: number; data?: any; error?: { code: string; message: string } };
async function call(method: string, path: string, body?: unknown, user = "dev:ana:ADMIN", raw?: { mime: string; bytes: Buffer }): Promise<R> {
  const res = await fetch(base + path, {
    method,
    headers: { ...(user ? { Authorization: `Bearer ${user}` } : {}), ...(raw ? { "Content-Type": raw.mime } : body ? { "Content-Type": "application/json" } : {}) },
    body: raw ? new Uint8Array(raw.bytes) : body ? JSON.stringify(body) : undefined,
  });
  const j = (await res.json().catch(() => ({}))) as any;
  return { status: res.status, data: j.data, error: j.error };
}

let n = 0;
const uid = () => `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;
const fila = (hoja_id: string, p: Record<string, unknown> = {}) => ({ hoja_id, tipo: "VTA", descripcion: "Venta de panel", responsable: "Adrian", comprobante: "BOLETA", caja_ingreso_efectivo: 100, ...p });
const abrir = async (ciudad: string, fecha: string) => (await call("POST", "/caja/hojas/abrir", { ciudad, fecha })).data.hoja;
const putFila = (id: string, body: unknown) => call("PUT", `/caja/filas/${id}`, body);
const hojas = async (ciudad: string, desde: string, hasta: string) => (await call("GET", `/caja/hojas?ciudad=${ciudad}&desde=${desde}&hasta=${hasta}`)).data.hojas as any[];
const estado = async (ciudad: string) => (await call("GET", `/caja/estado?ciudad=${ciudad}`)).data;

test("sin sesión no se entra a nada", async () => {
  assert.equal((await call("GET", "/caja/estado?ciudad=AQP", undefined, "")).status, 401);
  assert.equal((await call("GET", "/caja/estado?ciudad=AQP", undefined, "x")).status, 401);
  assert.equal((await call("GET", "/nope")).status, 404);
});

test("cada día nuevo abre con el cierre del día anterior; corregir un día pasado actualiza los siguientes", async () => {
  await call("PUT", "/caja/config/AQP", { saldo_inicial_caja: 1000, saldo_inicial_cta_cte: 200, saldo_inicial_caja_chica: 0 });
  const d1 = await abrir("AQP", "2026-10-19");
  assert.equal(d1.saldo_anterior_caja, 1000);
  assert.equal(d1.saldo_anterior_cta_cte, 200);
  const f1 = uid();
  await putFila(f1, fila(d1.id, { caja_ingreso_efectivo: 500, caja_ingreso_transf: 50.5 }));
  await putFila(uid(), fila(d1.id, { tipo: "OTRO", descripcion: "Compra", caja_ingreso_efectivo: 0, caja_salida_efectivo: 120.25, categoria: "Material" }));
  await putFila(uid(), fila(d1.id, { tipo: "OTRO", descripcion: "Depósito", caja_ingreso_efectivo: 0, caja_salida_efectivo: 300, cta_cte_ingreso: 300, interno: true }));

  const [h1] = await hojas("AQP", "2026-10-19", "2026-10-19");
  assert.equal(h1.saldo_final_caja, 1130.25); // 1000 + 550.50 − 120.25 − 300
  assert.equal(h1.saldo_final_cta_cte, 500);
  assert.deepEqual(h1.totales.efectivo, { ingreso: 500, salida: 420.25, total: 79.75 });

  const d2 = await abrir("AQP", "2026-10-21"); // saltó un día: abre con el cierre del 19
  assert.equal(d2.saldo_anterior_caja, 1130.25);
  assert.equal(d2.saldo_anterior_cta_cte, 500);
  assert.equal(d2.filas.length, 0, "el día nuevo arranca limpio");

  // corrijo el monto del día 19 → el día 21 se recalcula solo
  await putFila(f1, fila(d1.id, { caja_ingreso_efectivo: 600, caja_ingreso_transf: 50.5 }));
  assert.equal((await hojas("AQP", "2026-10-21", "2026-10-21"))[0].saldo_anterior_caja, 1230.25);
  assert.equal((await estado("AQP")).caja.saldo, 1230.25);
});

test("abrir la misma hoja dos veces devuelve la misma; no se abren hojas del futuro", async () => {
  const a = await abrir("MOQ", "2026-10-22");
  const b = await abrir("MOQ", "2026-10-22");
  assert.equal(a.id, b.id);
  const f = await call("POST", "/caja/hojas/abrir", { ciudad: "MOQ", fecha: "2026-12-25" });
  assert.equal(f.status, 400);
  assert.equal((await call("POST", "/caja/hojas/abrir", { ciudad: "LIM", fecha: "2026-10-22" })).status, 400);
  assert.equal((await call("POST", "/caja/hojas/abrir", { ciudad: "AQP", fecha: "2026-02-31" })).status, 400);
});

test("las ciudades llevan cajas separadas", async () => {
  await call("PUT", "/caja/config/MOQ", { saldo_inicial_caja: 50, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 });
  const m = await abrir("MOQ", "2026-10-20");
  assert.equal(m.saldo_anterior_caja, 50);
  await putFila(uid(), fila(m.id, { caja_ingreso_efectivo: 10 }));
  assert.equal((await estado("MOQ")).caja.saldo, 60);
  assert.equal((await estado("AQP")).caja.saldo, 1230.25);
});

test("validación de filas: lo que el ERP necesita se exige aquí", async () => {
  const h = await abrir("AQP", "2026-10-22");
  const malo = async (body: unknown, texto: RegExp) => {
    const r = await putFila(uid(), body);
    assert.equal(r.status, 400, JSON.stringify(r));
    assert.match(r.error!.message, texto);
  };
  await malo(fila(h.id, { descripcion: "  " }), /descripción/i);
  await malo(fila(h.id, { responsable: "" }), /responsable/i);
  await malo(fila(h.id, { caja_ingreso_efectivo: 0 }), /importe/i);
  await malo(fila(h.id, { caja_ingreso_efectivo: -5 }), /importe/i);
  await malo(fila(h.id, { caja_ingreso_efectivo: 0, caja_salida_efectivo: 5 }), /categor/i); // gasto real sin categoría
  await malo(fila(h.id, { caja_ingreso_efectivo: 0, caja_salida_efectivo: 5, categoria: "Gastos fijos" }), /gasto fijo/i);
  await malo(fila(h.id, { tipo: "XX" }), /tipo/);
  await malo(fila(h.id, { comprobante: "CONTRATO_TICKET" }), /comprobante/);
  await malo(fila(h.id, { categoria: "Inventada" }), /categor/i);
  assert.equal((await call("PUT", "/caja/filas/no-uuid", fila(h.id))).status, 400);
  assert.equal((await putFila(uid(), fila(uid()))).error?.code, "HOJA_NO_ENCONTRADA");
  // un movimiento interno no necesita categoría aunque tenga salida
  assert.equal((await putFila(uid(), fila(h.id, { caja_ingreso_efectivo: 0, caja_salida_efectivo: 5, interno: true }))).status, 200);
});

test("guardar dos veces lo mismo no duplica; borrar es idempotente; lo borrado no resucita", async () => {
  const h = await abrir("AQP", "2026-10-22");
  const id = uid();
  await putFila(id, fila(h.id, { descripcion: "uno" }));
  await putFila(id, fila(h.id, { descripcion: "uno editado" }));
  const antes = (await hojas("AQP", "2026-10-22", "2026-10-22"))[0].filas.filter((f: any) => f.id === id);
  assert.equal(antes.length, 1);
  assert.equal(antes[0].descripcion, "uno editado");
  assert.equal((await call("DELETE", `/caja/filas/${id}`)).status, 200);
  assert.equal((await call("DELETE", `/caja/filas/${id}`)).status, 200);
  assert.equal((await hojas("AQP", "2026-10-22", "2026-10-22"))[0].filas.some((f: any) => f.id === id), false);
  assert.equal((await putFila(id, fila(h.id))).error?.code, "FILA_ELIMINADA");
});

test("enviar a caja chica: baja la caja diaria, sube la caja chica, en una sola operación", async () => {
  const antes = (await estado("AQP")).caja.saldo; // 1230.25
  const t = { id: uid(), fila_id: uid(), movimiento_id: uid(), ciudad: "AQP", fecha: "2026-10-22", monto: 200, nota: "para movilidad" };
  const r = await call("POST", "/caja/transferencias", t);
  assert.equal(r.status, 200, JSON.stringify(r));
  assert.equal(r.data.fila.interno, true);
  assert.equal(r.data.fila.caja_salida_efectivo, 200);
  assert.equal(r.data.movimiento.tipo, "TRANSFERENCIA");
  const e = await estado("AQP");
  assert.equal(e.caja.saldo, antes - 200);
  assert.equal(e.caja_chica.saldo, 200);

  // reintentar el mismo envío (ej. se cortó la red al responder) no lo duplica
  assert.equal((await call("POST", "/caja/transferencias", t)).status, 200);
  assert.equal((await estado("AQP")).caja_chica.saldo, 200);

  // sus filas no se editan ni borran sueltas
  assert.equal((await putFila(t.fila_id, fila(r.data.fila.hoja_id))).error?.code, "FILA_DE_TRANSFERENCIA");
  assert.equal((await call("DELETE", `/caja/filas/${t.fila_id}`)).error?.code, "FILA_DE_TRANSFERENCIA");
  assert.equal((await call("DELETE", `/caja-chica/movimientos/${t.movimiento_id}`)).error?.code, "MOVIMIENTO_DE_TRANSFERENCIA");
});

test("no se puede enviar más de lo que hay en caja", async () => {
  const saldo = (await estado("AQP")).caja.saldo;
  const r = await call("POST", "/caja/transferencias", { id: uid(), fila_id: uid(), movimiento_id: uid(), ciudad: "AQP", fecha: "2026-10-22", monto: saldo + 0.01, nota: "" });
  assert.equal(r.status, 422);
  assert.equal(r.error?.code, "SALDO_INSUFICIENTE");
  assert.equal((await estado("AQP")).caja.saldo, saldo, "no cambió nada");
  assert.equal((await call("POST", "/caja/transferencias", { id: uid(), fila_id: uid(), movimiento_id: uid(), ciudad: "AQP", fecha: "2026-10-22", monto: 0 })).status, 400);
});

test("gastos de caja chica: validación, saldo y ventana de consulta", async () => {
  const mov = (extra: Record<string, unknown> = {}) => ({ ciudad: "AQP", fecha: "2026-10-22", descripcion: "Plumón", persona: "Carlos", categoria: "Oficina", monto: 3, origen: "MANUAL", ...extra });
  const id = uid();
  assert.equal((await call("PUT", `/caja-chica/movimientos/${id}`, mov({ categoria: "" }))).status, 400);
  assert.equal((await call("PUT", `/caja-chica/movimientos/${id}`, mov({ monto: 0 }))).status, 400);
  assert.equal((await call("PUT", `/caja-chica/movimientos/${id}`, mov({ categoria: "Gastos fijos" }))).status, 400);
  assert.equal((await call("PUT", `/caja-chica/movimientos/${id}`, mov())).status, 200);
  assert.equal((await call("PUT", `/caja-chica/movimientos/${id}`, mov({ monto: 4.5 }))).status, 200); // editar
  const lista = (await call("GET", "/caja-chica/movimientos?ciudad=AQP&desde=2026-10-22&hasta=2026-10-22")).data;
  assert.equal(lista.saldo, 195.5); // 200 recibidos − 4.50
  assert.equal(lista.saldo_anterior, 0, "antes del 22 no había movimientos");
  const sinVentana = (await call("GET", "/caja-chica/movimientos?ciudad=AQP&desde=2026-10-23&hasta=2026-10-30")).data;
  assert.equal(sinVentana.saldo_anterior, 195.5, "el saldo anterior incluye todo lo previo a la ventana");
  assert.equal((await call("DELETE", `/caja-chica/movimientos/${id}`)).status, 200);
  assert.equal((await estado("AQP")).caja_chica.saldo, 200);
  assert.equal((await call("PUT", `/caja-chica/movimientos/${id}`, mov())).error?.code, "MOVIMIENTO_ELIMINADO");
});

test("anular un envío: solo si la caja chica no gastó ya ese dinero", async () => {
  const t = { id: uid(), fila_id: uid(), movimiento_id: uid(), ciudad: "MOQ", fecha: "2026-10-22", monto: 40, nota: "" };
  assert.equal((await call("POST", "/caja/transferencias", t)).status, 200);
  const g = uid();
  await call("PUT", `/caja-chica/movimientos/${g}`, { ciudad: "MOQ", fecha: "2026-10-22", descripcion: "Pasajes", categoria: "Movilidad", monto: 30 });
  const r = await call("DELETE", `/caja/transferencias/${t.id}`);
  assert.equal(r.status, 409);
  assert.equal(r.error?.code, "SALDO_CHICA_INSUFICIENTE");
  await call("DELETE", `/caja-chica/movimientos/${g}`);
  const antes = (await estado("MOQ")).caja.saldo;
  assert.equal((await call("DELETE", `/caja/transferencias/${t.id}`)).status, 200);
  const e = await estado("MOQ");
  assert.equal(e.caja.saldo, antes + 40, "la caja diaria recupera el dinero");
  assert.equal(e.caja_chica.saldo, 0);
  assert.equal((await call("DELETE", `/caja/transferencias/${t.id}`)).status, 200, "anular dos veces es lo mismo que una");
});

test("fotos: se suben, se bajan idénticas, y se rechaza lo que no es una foto", async () => {
  const h = await abrir("AQP", "2026-10-22");
  const f = uid();
  await putFila(f, fila(h.id));
  const jpg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 0xff, 0xd9]);
  const a = uid();
  const ok = await call("PUT", `/caja/adjuntos/${a}?fila_id=${f}`, undefined, "dev:ana:ADMIN", { mime: "image/jpeg", bytes: jpg });
  assert.equal(ok.status, 200, JSON.stringify(ok));
  assert.equal((await call("PUT", `/caja/adjuntos/${a}?fila_id=${f}`, undefined, "dev:ana:ADMIN", { mime: "image/jpeg", bytes: jpg })).status, 200, "idempotente");
  const bajada = await fetch(`${base}/caja/adjuntos/${a}`, { headers: { Authorization: "Bearer dev:ana" } });
  assert.equal(bajada.headers.get("content-type"), "image/jpeg");
  assert.deepEqual(Buffer.from(await bajada.arrayBuffer()), jpg);
  assert.equal((await fetch(`${base}/caja/adjuntos/${a}`)).status, 401, "las fotos también piden sesión");
  const fs = (await hojas("AQP", "2026-10-22", "2026-10-22"))[0].filas.find((x: any) => x.id === f);
  assert.deepEqual(fs.adjuntos.map((x: any) => [x.id, x.mime, x.bytes]), [[a, "image/jpeg", jpg.length]]);

  const sube = (id: string, q: string, mime: string, bytes: Buffer) => call("PUT", `/caja/adjuntos/${id}?${q}`, undefined, "dev:ana:ADMIN", { mime, bytes });
  assert.equal((await sube(uid(), `fila_id=${f}`, "application/pdf", jpg)).status, 415);
  assert.equal((await sube(uid(), `fila_id=${f}`, "image/png", Buffer.alloc(0))).status, 400);
  assert.equal((await sube(uid(), `fila_id=${f}`, "image/png", Buffer.alloc(10 * 1024 * 1024 + 1))).status, 413);
  assert.equal((await sube(uid(), `fila_id=${uid()}`, "image/png", jpg)).status, 404);
  assert.equal((await sube(uid(), "", "image/png", jpg)).status, 400);
  assert.equal((await sube(uid(), `fila_id=${f}&movimiento_id=${uid()}`, "image/png", jpg)).status, 400);

  assert.equal((await call("DELETE", `/caja/adjuntos/${a}`)).status, 200);
  assert.equal((await fetch(`${base}/caja/adjuntos/${a}`, { headers: { Authorization: "Bearer dev:ana" } })).status, 404);
  assert.equal(storage.size() >= 0, true);
});

test("reflejo en el ERP: crea, actualiza y anula; lo interno no se refleja", async () => {
  llamadas.length = 0;
  const h = await abrir("MOQ", "2026-10-21");
  const id = uid();
  // un cobro (VTA) por 150 y, en la misma fila, un gasto de 20
  await putFila(id, fila(h.id, { caja_ingreso_efectivo: 100, caja_ingreso_transf: 50, caja_salida_efectivo: 20, categoria: "Movilidad", responsable: "Carlos" }));
  assert.deepEqual(llamadas.map((c) => c.op), ["crearIngreso", "crearGasto"]);
  assert.deepEqual(llamadas[0].p, { tipo: "VENTA", detalle: "Venta de panel", monto: 150, fecha: "2026-10-21", channel: "web" });
  assert.deepEqual(llamadas[1].p, { categoria: "MOVILIDAD", descripcion: "Venta de panel", monto: 20, fecha: "2026-10-21", persona_texto: "Carlos", ciudad: "Moquegua", channel: "web" });

  llamadas.length = 0;
  await putFila(id, fila(h.id, { caja_ingreso_efectivo: 100, caja_ingreso_transf: 70, caja_salida_efectivo: 20, categoria: "Movilidad" })); // editar
  assert.deepEqual(llamadas.map((c) => c.op), ["actualizarIngreso", "actualizarGasto"]);
  const idIngreso = llamadas[0].id!;
  const idGasto = llamadas[1].id!;
  assert.match(idIngreso, /^ING-\d+$/);
  assert.match(idGasto, /^GAS-\d+$/);
  assert.equal(llamadas[0].p.monto, 170);

  llamadas.length = 0;
  await putFila(id, fila(h.id, { caja_ingreso_efectivo: 100, caja_ingreso_transf: 70 })); // ya no hay salida → se anula el gasto
  assert.deepEqual(llamadas.map((c) => c.op), ["actualizarIngreso", "anularGasto"]);
  assert.equal(llamadas[0].id, idIngreso, "actualiza el MISMO registro del ERP, no crea otro");
  assert.equal(llamadas[1].id, idGasto, "anula el gasto que se había creado");

  llamadas.length = 0;
  await call("DELETE", `/caja/filas/${id}`); // borrar la fila anula lo que quedaba
  assert.deepEqual(llamadas.map((c) => c.op), ["anularIngreso"]);
  assert.equal(llamadas[0].id, idIngreso);

  llamadas.length = 0;
  await putFila(uid(), fila(h.id, { tipo: "OTRO", descripcion: "Depósito ICR", caja_ingreso_efectivo: 0, caja_salida_efectivo: 500, cta_cte_ingreso: 500, interno: true }));
  assert.deepEqual(llamadas, [], "un depósito al banco no es ni ingreso ni gasto");

  await call("POST", "/caja/transferencias", { id: uid(), fila_id: uid(), movimiento_id: uid(), ciudad: "MOQ", fecha: "2026-10-21", monto: 5, nota: "" });
  assert.deepEqual(llamadas, [], "enviar a caja chica tampoco");

  await call("PUT", `/caja-chica/movimientos/${uid()}`, { ciudad: "AQP", fecha: "2026-10-22", descripcion: "Pegamento", persona: "Rosa", categoria: "Gastos fijos", subcategoria: "Servicios", monto: 7 });
  const ultima = ultimaLlamada();
  assert.equal(ultima.op, "crearGasto");
  assert.equal(ultima.p.categoria, "SERVICIOS");
  assert.equal(ultima.p.ciudad, "Arequipa");
});

test("si el ERP está caído el dato NO se pierde: queda pendiente y se reintenta", async () => {
  const h = await abrir("MOQ", "2026-10-21");
  const id = uid();
  llamadas.length = 0;
  erpCaido = true;
  const r = await putFila(id, fila(h.id, { descripcion: "Venta con ERP caído", caja_ingreso_efectivo: 80 }));
  assert.equal(r.status, 200, "la caja guarda igual");
  assert.equal(r.data.fila.erp_pendiente, true);
  assert.match(r.data.fila.erp_error, /ERP caído/);
  assert.equal((await hojas("MOQ", "2026-10-21", "2026-10-21"))[0].filas.some((f: any) => f.id === id), true);
  erpCaido = false;
  const re = await call("POST", "/caja/erp/reintentar");
  assert.equal(re.data.pendientes, 0);
  assert.equal(llamadas.filter((c) => c.op === "crearIngreso" && c.p.detalle === "Venta con ERP caído").length, 1, "se mandó una sola vez");
  const f = (await hojas("MOQ", "2026-10-21", "2026-10-21"))[0].filas.find((x: any) => x.id === id);
  assert.equal(f.erp_pendiente, false);
});

test("solo quien tiene permiso cambia los saldos iniciales", async () => {
  const body = { saldo_inicial_caja: 1, saldo_inicial_cta_cte: 1, saldo_inicial_caja_chica: 1 };
  assert.equal((await call("PUT", "/caja/config/AQP", body, "dev:beto:VENTAS")).status, 403);
  assert.equal((await call("PUT", "/caja/config/AQP", { ...body, saldo_inicial_caja: "x" }, "dev:ana:ADMIN")).status, 400);
  assert.equal((await call("PUT", "/caja/config/AQP", { saldo_inicial_caja: 1000, saldo_inicial_cta_cte: 200, saldo_inicial_caja_chica: 0 })).status, 200);
});

test("observaciones del pie de la planilla", async () => {
  const h = await abrir("AQP", "2026-10-22");
  const r = await call("PATCH", `/caja/hojas/${h.id}`, { responsable_caja: "Rosa", obras_realizadas: "Losa nivel 2", maletas: "3", escaleras: "2", encargado_obra: "Luis" });
  assert.equal(r.data.hoja.responsable_caja, "Rosa");
  assert.equal(r.data.hoja.encargado_obra, "Luis");
  const parcial = await call("PATCH", `/caja/hojas/${h.id}`, { maletas: "4" });
  assert.equal(parcial.data.hoja.maletas, "4");
  assert.equal(parcial.data.hoja.obras_realizadas, "Losa nivel 2", "lo que no se manda no se toca");
});
