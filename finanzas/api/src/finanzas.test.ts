/// <reference types="node" />
// Roles en el servidor, historial de cambios, cierre del día, cambios simultáneos, alertas y sesiones reales.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { applyMigrations, migrar, pgliteDb, type Db } from "./db";
import { authDesdeEntorno, authSesiones } from "./auth";
import { memoryStorage } from "./storage";
import { sinEspejo } from "./erp";
import { crearServicio } from "./service";
import { crearServidor, type LoginPrincipal } from "./server";
import { ApiError } from "./auth";

const HOY = "2026-10-22";
let db: Db;
let base = "";
let server: ReturnType<typeof crearServidor>;
const salidas: string[] = [];

before(async () => {
  db = await pgliteDb();
  await applyMigrations(db);
  const env = { AUTH_MODE: "dev" } as NodeJS.ProcessEnv;
  const loginPrincipal: LoginPrincipal = {
    async entrar(usuario, clave) {
      if (clave !== "clave-buena") throw new ApiError(401, "CREDENCIALES", "Usuario o clave incorrectos.");
      const rol = usuario.startsWith("emp") ? "empleado" : "finanzas";
      return { token: `tok-${usuario}`, usuario: { usuario, nombre: usuario.toUpperCase(), rol } };
    },
    async salir(token) {
      salidas.push(token);
    },
  };
  server = crearServidor({ auth: authDesdeEntorno(env), svc: crearServicio({ db, storage: memoryStorage(), mirror: sinEspejo, env, hoy: () => HOY }), loginPrincipal });
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(async () => {
  server.close();
  await db.close();
});

type R = { status: number; data?: any; error?: { code: string; message: string } };
const ADMIN = "dev:ana:admin";
const FINANZAS = "dev:carla:finanzas";
const ENCARGADO = "dev:beto:encargado";
const EMPLEADO = "dev:dani:empleado";
const ALMACEN = "dev:eva:almacen";

async function call(method: string, path: string, body?: unknown, user: string | null = ADMIN, raw?: { mime: string; bytes: Buffer }): Promise<R> {
  const res = await fetch(base + path, {
    method,
    headers: { ...(user ? { Authorization: `Bearer ${user}` } : {}), ...(raw ? { "Content-Type": raw.mime } : body ? { "Content-Type": "application/json" } : {}) },
    body: raw ? new Uint8Array(raw.bytes) : body ? JSON.stringify(body) : undefined,
  });
  const j = (await res.json().catch(() => ({}))) as any;
  return { status: res.status, data: j.data, error: j.error };
}

let n = 0;
const uid = () => `10000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;
const fila = (hoja_id: string, p: Record<string, unknown> = {}) => ({ hoja_id, tipo: "VTA", descripcion: "Venta de panel", responsable: "Adrian", comprobante: "BOLETA", caja_ingreso_efectivo: 100, ...p });
const abrir = async (ciudad: string, fecha: string, user = ADMIN) => (await call("POST", "/caja/hojas/abrir", { ciudad, fecha }, user)).data.hoja;
const hoja = async (ciudad: string, fecha: string) => ((await call("GET", `/caja/hojas?ciudad=${ciudad}&desde=${fecha}&hasta=${fecha}`)).data.hojas as any[])[0];
const cambios = async (q: string, user = ADMIN) => (await call("GET", `/caja/auditoria?${q}`, undefined, user)).data.cambios as any[];

test("cada rol entra solo a lo suyo: empleado y almacén no ven Finanzas", async () => {
  for (const u of [EMPLEADO, ALMACEN]) {
    const r = await call("GET", "/caja/estado?ciudad=AQP", undefined, u);
    assert.equal(r.status, 403);
    assert.equal(r.error?.code, "SIN_ACCESO");
  }
  for (const u of [ADMIN, FINANZAS, ENCARGADO]) assert.equal((await call("GET", "/caja/estado?ciudad=AQP", undefined, u)).status, 200);

  // La app consulta sus permisos aunque el rol no tenga acceso, para poder explicarlo
  const p = await call("GET", "/caja/permisos", undefined, EMPLEADO);
  assert.equal(p.status, 200);
  assert.equal(p.data.permisos.acceso, false);
  assert.deepEqual((await call("GET", "/caja/permisos", undefined, FINANZAS)).data.permisos, { acceso: true, corregir_pasado: true, cerrar: true, reabrir: false, configurar: false, revisar: true });
  assert.equal((await call("GET", "/caja/permisos", undefined, ENCARGADO)).data.permisos.corregir_pasado, false);
});

test("los saldos iniciales solo los cambia un administrador", async () => {
  const cuerpo = { saldo_inicial_caja: 500, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 100 };
  assert.equal((await call("PUT", "/caja/config/AQP", cuerpo, FINANZAS)).status, 403);
  assert.equal((await call("PUT", "/caja/config/AQP", cuerpo, ENCARGADO)).error?.code, "SIN_PERMISO");
  assert.equal((await call("PUT", "/caja/config/AQP", cuerpo, ADMIN)).status, 200);
  const [c] = await cambios("ciudad=AQP&limite=5");
  assert.equal(c.accion, "config");
  assert.equal(c.antes.saldo_inicial_caja, 0);
  assert.equal(c.despues.saldo_inicial_caja, 500);
  assert.equal(c.usuario, "ana");
});

test("el día de hoy lo registra cualquiera con acceso; corregir un día anterior solo Finanzas o admin (lo decide el servidor)", async () => {
  const hoyHoja = await abrir("AQP", HOY, ENCARGADO);
  const f1 = uid();
  assert.equal((await call("PUT", `/caja/filas/${f1}`, fila(hoyHoja.id), ENCARGADO)).status, 200);

  const ayer = await abrir("AQP", "2026-10-21", ENCARGADO); // abrir la hoja no es corregir
  const f2 = uid();
  const rechazo = await call("PUT", `/caja/filas/${f2}`, fila(ayer.id), ENCARGADO);
  assert.equal(rechazo.status, 403);
  assert.equal(rechazo.error?.code, "SIN_PERMISO");
  assert.equal((await call("PUT", `/caja/filas/${f2}`, fila(ayer.id), FINANZAS)).status, 200);

  // tampoco puede borrarla, editar las observaciones ni subir fotos a un día anterior
  assert.equal((await call("DELETE", `/caja/filas/${f2}`, undefined, ENCARGADO)).status, 403);
  assert.equal((await call("PATCH", `/caja/hojas/${ayer.id}`, { obras_realizadas: "Losa" }, ENCARGADO)).status, 403);
  const png = { mime: "image/png", bytes: Buffer.from("89504e470d0a1a0a0000000d", "hex") };
  assert.equal((await call("PUT", `/caja/adjuntos/${uid()}?fila_id=${f2}`, undefined, ENCARGADO, png)).status, 403);
  assert.equal((await call("PUT", `/caja/adjuntos/${uid()}?fila_id=${f2}`, undefined, FINANZAS, png)).status, 200);
  // y la caja chica de un día anterior sigue la misma regla
  const mov = { ciudad: "AQP", fecha: "2026-10-20", descripcion: "Plumón", persona: "Luis", categoria: "Oficina", monto: 5 };
  assert.equal((await call("PUT", `/caja-chica/movimientos/${uid()}`, mov, ENCARGADO)).status, 403);
  assert.equal((await call("PUT", `/caja-chica/movimientos/${uid()}`, { ...mov, fecha: HOY }, ENCARGADO)).status, 200);
});

test("historial de cambios: qué, quién, cuándo y el valor anterior", async () => {
  const h = await abrir("MOQ", "2026-10-21");
  const id = uid();
  await call("PUT", `/caja/filas/${id}`, fila(h.id, { caja_ingreso_efectivo: 100 }), FINANZAS);
  await call("PUT", `/caja/filas/${id}`, fila(h.id, { caja_ingreso_efectivo: 100 }), FINANZAS); // reintento idéntico: no es un cambio
  await call("PUT", `/caja/filas/${id}`, fila(h.id, { caja_ingreso_efectivo: 150 }), FINANZAS);
  await call("PATCH", `/caja/hojas/${h.id}`, { responsable_caja: "Mario" }, FINANZAS);
  await call("DELETE", `/caja/filas/${id}`, undefined, FINANZAS);
  await call("DELETE", `/caja/filas/${id}`, undefined, FINANZAS); // borrar dos veces: una sola anotación

  const lista = (await cambios("ciudad=MOQ&fecha=2026-10-21")).reverse();
  assert.deepEqual(lista.map((c) => `${c.accion}:${c.entidad}`), ["crear:fila", "editar:fila", "editar:hoja", "eliminar:fila"]);
  assert.equal(lista[0].antes, null);
  assert.equal(lista[0].despues.caja_ingreso_efectivo, 100);
  assert.equal(lista[1].antes.caja_ingreso_efectivo, 100);
  assert.equal(lista[1].despues.caja_ingreso_efectivo, 150);
  assert.equal(lista[2].antes.responsable_caja, "");
  assert.equal(lista[2].despues.responsable_caja, "Mario");
  assert.equal(lista[3].antes.caja_ingreso_efectivo, 150);
  assert.equal(lista[3].despues, null);
  for (const c of lista) {
    assert.equal(c.usuario, "carla");
    assert.equal(c.rol, "finanzas");
    assert.ok(c.creado_en);
    assert.equal(c.fecha_dia, "2026-10-21");
  }
  assert.equal((await call("GET", "/caja/auditoria?ciudad=MOQ", undefined, EMPLEADO)).status, 403);
});

test("dos personas editando lo mismo: la segunda recibe un aviso y no pisa a la primera", async () => {
  const h = await abrir("AQP", HOY);
  const id = uid();
  const creada = (await call("PUT", `/caja/filas/${id}`, fila(h.id, { descripcion: "Venta A" }), ENCARGADO)).data.fila;
  assert.equal(creada.version, 1);
  // Beto la edita (versión 1 → 2)
  const beto = await call("PUT", `/caja/filas/${id}`, { ...fila(h.id, { descripcion: "Venta A (Beto)" }), version: 1 }, ENCARGADO);
  assert.equal(beto.data.fila.version, 2);
  // Carla todavía tenía la versión 1
  const carla = await call("PUT", `/caja/filas/${id}`, { ...fila(h.id, { descripcion: "Venta A (Carla)" }), version: 1 }, FINANZAS);
  assert.equal(carla.status, 409);
  assert.equal(carla.error?.code, "CAMBIO_CONCURRENTE");
  assert.equal((await hoja("AQP", HOY)).filas.find((f: any) => f.id === id).descripcion, "Venta A (Beto)");
  // Con lo último, sí
  assert.equal((await call("PUT", `/caja/filas/${id}`, { ...fila(h.id, { descripcion: "Venta A (Carla)" }), version: 2 }, FINANZAS)).status, 200);
  // Un reintento de lo que ya se guardó (se perdió la respuesta) no se confunde con un conflicto
  assert.equal((await call("PUT", `/caja/filas/${id}`, { ...fila(h.id, { descripcion: "Venta A (Carla)" }), version: 2 }, FINANZAS)).status, 200);
  // lo mismo con las observaciones del día
  const v = (await hoja("AQP", HOY)).version;
  assert.equal((await call("PATCH", `/caja/hojas/${h.id}`, { maletas: "2", version: v }, ENCARGADO)).status, 200);
  assert.equal((await call("PATCH", `/caja/hojas/${h.id}`, { maletas: "3", version: v }, FINANZAS)).error?.code, "CAMBIO_CONCURRENTE");
});

test("cierre del día: efectivo contado, diferencia, bloqueo y reapertura con motivo", async () => {
  await call("PUT", "/caja/config/MOQ", { saldo_inicial_caja: 1000, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 });
  const d = await abrir("MOQ", "2026-10-15");
  const f = uid();
  await call("PUT", `/caja/filas/${f}`, fila(d.id, { caja_ingreso_efectivo: 200 }), FINANZAS); // saldo calculado = 1200

  assert.equal((await call("POST", `/caja/hojas/${d.id}/cerrar`, { efectivo_contado: 1200 }, ENCARGADO)).status, 403);
  assert.equal((await call("POST", `/caja/hojas/${d.id}/cerrar`, {}, FINANZAS)).status, 400);
  const sin = await call("POST", `/caja/hojas/${d.id}/cerrar`, { efectivo_contado: 1180 }, FINANZAS);
  assert.equal(sin.status, 400);
  assert.match(sin.error!.message, /faltan S\/ 20\.00/);
  const ok = await call("POST", `/caja/hojas/${d.id}/cerrar`, { efectivo_contado: 1180, nota: "Vuelto mal dado" }, FINANZAS);
  assert.equal(ok.status, 200);
  assert.deepEqual({ ...ok.data.hoja.cierre, cerrada_en: "x" }, { cerrada_en: "x", cerrada_por: "carla", efectivo_contado: 1180, saldo_calculado: 1200, diferencia: -20, nota: "Vuelto mal dado" });

  // bloqueado para todos, también para el administrador
  for (const u of [ADMIN, FINANZAS]) {
    assert.equal((await call("PUT", `/caja/filas/${uid()}`, fila(d.id), u)).error?.code, "DIA_CERRADO");
    assert.equal((await call("PUT", `/caja/filas/${f}`, fila(d.id, { caja_ingreso_efectivo: 999 }), u)).error?.code, "DIA_CERRADO");
    assert.equal((await call("DELETE", `/caja/filas/${f}`, undefined, u)).error?.code, "DIA_CERRADO");
    assert.equal((await call("PATCH", `/caja/hojas/${d.id}`, { maletas: "x" }, u)).error?.code, "DIA_CERRADO");
    assert.equal((await call("POST", "/caja/transferencias", { id: uid(), fila_id: uid(), movimiento_id: uid(), ciudad: "MOQ", fecha: "2026-10-15", monto: 5 }, u)).error?.code, "DIA_CERRADO");
  }
  assert.equal((await call("POST", `/caja/hojas/${d.id}/cerrar`, { efectivo_contado: 1200 }, FINANZAS)).error?.code, "DIA_CERRADO"); // ya estaba cerrado
  assert.equal((await hoja("MOQ", "2026-10-15")).filas[0].caja_ingreso_efectivo, 200);

  // reabrir: solo administrador y con motivo
  assert.equal((await call("POST", `/caja/hojas/${d.id}/reabrir`, { motivo: "Error al contar" }, FINANZAS)).status, 403);
  assert.equal((await call("POST", `/caja/hojas/${d.id}/reabrir`, { motivo: "ya" }, ADMIN)).status, 400);
  const re = await call("POST", `/caja/hojas/${d.id}/reabrir`, { motivo: "Error al contar el efectivo" }, ADMIN);
  assert.equal(re.status, 200);
  assert.equal(re.data.hoja.cierre, null);
  assert.equal((await call("PUT", `/caja/filas/${f}`, fila(d.id, { caja_ingreso_efectivo: 250 }), FINANZAS)).status, 200);

  const rastro = (await cambios("ciudad=MOQ&fecha=2026-10-15")).map((c) => `${c.accion}:${c.entidad}`).reverse();
  assert.deepEqual(rastro.slice(-3), ["cerrar:hoja", "reabrir:hoja", "editar:fila"]);
  const reabierto = (await cambios("ciudad=MOQ&fecha=2026-10-15")).find((c) => c.accion === "reabrir");
  assert.equal(reabierto.motivo, "Error al contar el efectivo");
  assert.equal(reabierto.antes.diferencia, -20);
  assert.equal(reabierto.usuario, "ana");
});

test("los días se cierran y se reabren en orden", async () => {
  const d1 = await abrir("AQP", "2026-10-10");
  const d2 = await abrir("AQP", "2026-10-11");
  const d3 = await abrir("AQP", "2026-10-12");
  const d0 = await abrir("AQP", "2026-10-09"); // sin movimientos: no estorba
  await call("PUT", `/caja/filas/${uid()}`, fila(d1.id), FINANZAS);
  await call("PUT", `/caja/filas/${uid()}`, fila(d2.id), FINANZAS);
  const saldo = async (fecha: string) => (await hoja("AQP", fecha)).saldo_final_caja as number;

  const salto = await call("POST", `/caja/hojas/${d2.id}/cerrar`, { efectivo_contado: await saldo("2026-10-11") }, FINANZAS);
  assert.equal(salto.error?.code, "DIA_ANTERIOR_ABIERTO");
  assert.match(salto.error!.message, /2026-10-10/);
  assert.equal((await call("POST", `/caja/hojas/${d1.id}/cerrar`, { efectivo_contado: await saldo("2026-10-10") }, FINANZAS)).status, 200);
  assert.equal((await call("POST", `/caja/hojas/${d2.id}/cerrar`, { efectivo_contado: await saldo("2026-10-11") }, FINANZAS)).status, 200);
  assert.equal((await call("POST", `/caja/hojas/${d3.id}/cerrar`, { efectivo_contado: await saldo("2026-10-12") }, FINANZAS)).status, 200); // vacío pero posterior a cerrados

  // un día anterior vacío ya no se puede llenar: cambiaría el saldo de días cerrados
  assert.equal((await call("PUT", `/caja/filas/${uid()}`, fila(d0.id), FINANZAS)).error?.code, "DIA_POSTERIOR_CERRADO");
  assert.equal((await call("POST", `/caja/hojas/${d1.id}/reabrir`, { motivo: "Corregir el día 10" }, ADMIN)).error?.code, "DIA_POSTERIOR_CERRADO");
  assert.equal((await call("POST", `/caja/hojas/${d3.id}/reabrir`, { motivo: "Reabrir de atrás hacia adelante" }, ADMIN)).status, 200);
  assert.equal((await call("POST", `/caja/hojas/${d2.id}/reabrir`, { motivo: "Reabrir de atrás hacia adelante" }, ADMIN)).status, 200);
  assert.equal((await call("POST", `/caja/hojas/${d1.id}/reabrir`, { motivo: "Reabrir de atrás hacia adelante" }, ADMIN)).status, 200);
  assert.equal((await call("POST", `/caja/hojas/${d1.id}/reabrir`, { motivo: "Ya estaba abierto" }, ADMIN)).error?.code, "DIA_ABIERTO");
  assert.equal((await call("POST", `/caja/hojas/${d3.id}/cerrar`, { efectivo_contado: 0 }, FINANZAS)).error?.code, "DIA_ANTERIOR_ABIERTO");
  const manana = await abrir("AQP", "2026-10-23");
  assert.match((await call("POST", `/caja/hojas/${manana.id}/cerrar`, { efectivo_contado: 0 }, FINANZAS)).error!.message, /todavía no llegó/);
  assert.equal((await call("POST", "/caja/hojas/00000000-0000-4000-8000-000000000000/cerrar", { efectivo_contado: 0 }, FINANZAS)).status, 404);
});

test("alertas: cajas en negativo, movimientos sin comprobante, días sin cerrar y descuadres", async () => {
  await call("PUT", "/caja/config/AQP", { saldo_inicial_caja: 0, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 });
  await call("PUT", "/caja/config/MOQ", { saldo_inicial_caja: 0, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 });
  // Se parte de una ciudad limpia: Cusco no existe, así que se usan días propios en MOQ lejos de los demás tests
  const d = await abrir("MOQ", "2026-09-30");
  await call("PUT", `/caja/filas/${uid()}`, fila(d.id, { descripcion: "Pago sin papel", comprobante: "NINGUNO", caja_ingreso_efectivo: 0, caja_salida_efectivo: 80, categoria: "Material", tipo: "OTRO" }), FINANZAS);
  const sinCierre = await call("GET", "/caja/alertas?ciudad=MOQ&dias=30", undefined, ENCARGADO);
  assert.equal(sinCierre.status, 200);
  const tipos = (ciudad: string) => sinCierre.data.alertas.filter((a: any) => a.ciudad === ciudad && a.fecha === "2026-09-30").map((a: any) => `${a.tipo}:${a.nivel}`).sort();
  assert.deepEqual(tipos("MOQ"), ["CAJA_NEGATIVA:alta", "DIA_SIN_CERRAR:media", "FILAS_SIN_COMPROBANTE:media"].sort());
  const neg = sinCierre.data.alertas.find((a: any) => a.tipo === "CAJA_NEGATIVA" && a.fecha === "2026-09-30");
  assert.equal(neg.monto, -80);
  assert.equal(neg.id, "CAJA_NEGATIVA:MOQ:2026-09-30");

  // una foto del recibo cuenta como comprobante
  const filaId = (await hoja("MOQ", "2026-09-30")).filas[0].id;
  await call("PUT", `/caja/adjuntos/${uid()}?fila_id=${filaId}`, undefined, FINANZAS, { mime: "image/png", bytes: Buffer.from("89504e470d0a1a0a0000000d", "hex") });
  const conFoto = await call("GET", "/caja/alertas?ciudad=MOQ&dias=30", undefined, ENCARGADO);
  assert.ok(!conFoto.data.alertas.some((a: any) => a.tipo === "FILAS_SIN_COMPROBANTE" && a.fecha === "2026-09-30"));

  // cierre con diferencia → alerta de descuadre
  await call("POST", `/caja/hojas/${d.id}/cerrar`, { efectivo_contado: -0 + 10, nota: "Sobraron 90" }, FINANZAS).then((r) => assert.equal(r.status, 200, JSON.stringify(r.error)));
  const cerrado = await call("GET", "/caja/alertas?ciudad=MOQ&dias=30", undefined, ENCARGADO);
  const desc = cerrado.data.alertas.find((a: any) => a.tipo === "DIFERENCIA_EN_CIERRE" && a.fecha === "2026-09-30");
  assert.equal(desc.monto, 90);
  assert.ok(!cerrado.data.alertas.some((a: any) => a.tipo === "DIA_SIN_CERRAR" && a.fecha === "2026-09-30"));

  // caja chica en negativo y gastos sin foto
  await call("PUT", `/caja-chica/movimientos/${uid()}`, { ciudad: "MOQ", fecha: HOY, descripcion: "Taxi", persona: "Luis", categoria: "Movilidad", monto: 40 }, ENCARGADO);
  const chica = await call("GET", "/caja/alertas?ciudad=MOQ&dias=30", undefined, ADMIN);
  assert.ok(chica.data.alertas.some((a: any) => a.tipo === "CAJA_CHICA_NEGATIVA" && a.fecha === HOY));
  assert.equal(chica.data.resumen.alta >= 3, true);
  assert.equal(chica.data.alertas[0].nivel, "alta"); // lo más grave primero

  assert.equal((await call("GET", "/caja/alertas", undefined, EMPLEADO)).status, 403);
});

test("resumen para el tablero general", async () => {
  const r = await call("GET", "/caja/resumen", undefined, ENCARGADO);
  assert.equal(r.status, 200);
  assert.equal(r.data.fecha, HOY);
  assert.deepEqual(Object.keys(r.data.ciudades).sort(), ["AQP", "MOQ"]);
  assert.ok(r.data.ciudades.AQP.hoy.movimientos >= 1);
  assert.ok(r.data.ciudades.MOQ.ultimos_dias.every((d: any, i: number, a: any[]) => i === 0 || a[i - 1].fecha >= d.fecha), "últimos días del más reciente al más antiguo");
  assert.ok(r.data.alertas.alta >= 1);
  assert.ok(r.data.cambios_recientes.length > 0);
  assert.equal((await call("GET", "/caja/resumen", undefined, EMPLEADO)).status, 403);
});

test("la versión de la caja cambia solo cuando algo cambia", async () => {
  const a = (await call("GET", "/caja/version")).data.version;
  assert.equal((await call("GET", "/caja/version")).data.version, a);
  const h = await abrir("AQP", HOY);
  await call("PUT", `/caja/filas/${uid()}`, fila(h.id, { descripcion: "Otra venta" }), FINANZAS);
  const b = (await call("GET", "/caja/version")).data.version;
  assert.notEqual(b, a);
  const id = uid();
  await call("PUT", `/caja/filas/${id}`, fila(h.id, { descripcion: "Para borrar" }), FINANZAS);
  const c = (await call("GET", "/caja/version")).data.version;
  await call("DELETE", `/caja/filas/${id}`, undefined, FINANZAS);
  assert.notEqual((await call("GET", "/caja/version")).data.version, c, "borrar también cambia la versión");
});

test("inicio de sesión con el usuario de la plataforma: solo entran los roles con acceso", async () => {
  const ok = await call("POST", "/auth/login", { email: "carlos", password: "clave-buena" }, null);
  assert.equal(ok.status, 200);
  assert.equal(ok.data.token, "tok-carlos");
  assert.deepEqual(ok.data.user, { nombre_completo: "CARLOS", email: "carlos", rol_codigo: "finanzas" });
  assert.equal(ok.data.permisos.cerrar, true);
  assert.equal((await call("POST", "/auth/login", { usuario: "carlos", clave: "clave-buena" }, null)).status, 200); // acepta "usuario" y "clave" también

  const mala = await call("POST", "/auth/login", { email: "carlos", password: "x" }, null);
  assert.equal(mala.status, 401);
  assert.equal(mala.error?.message, "Usuario o clave incorrectos.");

  const sinAcceso = await call("POST", "/auth/login", { email: "empleado1", password: "clave-buena" }, null);
  assert.equal(sinAcceso.status, 403);
  assert.equal(sinAcceso.error?.code, "SIN_ACCESO");
  assert.deepEqual(salidas, ["tok-empleado1"], "la sesión que se abrió sin querer se cierra");
  assert.equal((await call("POST", "/auth/login", { email: "", password: "" }, null)).status, 400);
});

test("sesiones reales: el token debe estar en la base, vigente y de un usuario activo", async () => {
  const d = await pgliteDb();
  await d.exec(`CREATE TABLE usuarios (id serial PRIMARY KEY, usuario text, nombre text, rol text, activo boolean DEFAULT true);
    CREATE TABLE sesiones (token char(64) PRIMARY KEY, usuario_id int REFERENCES usuarios(id), expira_en timestamp NOT NULL);
    INSERT INTO usuarios (usuario, nombre, rol) VALUES ('carlos', 'Carlos Pérez', 'finanzas'), ('inactivo', 'Inactivo', 'admin');
    UPDATE usuarios SET activo = false WHERE usuario = 'inactivo';`);
  const futuro = "(now() AT TIME ZONE 'America/Lima') + interval '1 day'";
  const pasado = "(now() AT TIME ZONE 'America/Lima') - interval '1 minute'";
  await d.exec(`INSERT INTO sesiones VALUES (repeat('a', 64), 1, ${futuro}), (repeat('b', 64), 1, ${pasado}), (repeat('c', 64), 2, ${futuro})`);
  const auth = authSesiones(d);
  const u = await auth(`Bearer ${"a".repeat(64)}`);
  assert.deepEqual({ ...u, token: undefined }, { id: "1", nombre: "Carlos Pérez", email: "carlos", rol: "finanzas", token: undefined });
  for (const malo of [`Bearer ${"b".repeat(64)}`, `Bearer ${"c".repeat(64)}`, `Bearer ${"z".repeat(64)}`, "Bearer ", undefined, "Basic abc"])
    await assert.rejects(() => auth(malo), (e: unknown) => e instanceof ApiError && e.status === 401);
  await d.close();
});

test("las migraciones se aplican una sola vez y en orden", async () => {
  const d = await pgliteDb();
  const primera = await migrar(d);
  assert.deepEqual(primera, ["001_caja.sql", "002_cierre_auditoria.sql", "003_comprobante_recibo.sql"]);
  assert.deepEqual(await migrar(d), []);
  await d.close();
});
