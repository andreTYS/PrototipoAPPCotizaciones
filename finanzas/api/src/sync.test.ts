/// <reference types="node" />
/**
 * Prueba de integración: el almacén local y el motor de sincronización DE LA APP, contra la API real
 * (Postgres de verdad con PGlite). Dos "dispositivos" con su propio almacenamiento, red que se corta,
 * respuestas que se pierden. Es la prueba de que el modo sin conexión no pierde ni duplica nada.
 */
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { applyMigrations, pgliteDb, type Db } from "./db";
import { authDesdeEntorno } from "./auth";
import { memoryStorage } from "./storage";
import { sinEspejo } from "./erp";
import { crearServicio } from "./service";
import { crearServidor } from "./server";
import { crearStore, pendientes, saldoCaja, saldoCajaChica, saldosDe, type Store } from "../../app/src/lib/caja/store";
import { crearSync, type Sync, type SyncApi } from "../../app/src/lib/caja/sync";
import { validarFila } from "../../app/src/lib/caja/calc";
import type { Fila } from "../../app/src/lib/caja/types";

let db: Db;
let server: ReturnType<typeof crearServidor>;
let base = "";
let hoy = "2026-10-22";
let peticiones: string[] = [];

before(async () => {
  db = await pgliteDb();
  await applyMigrations(db);
  const env = { AUTH_MODE: "dev" } as NodeJS.ProcessEnv;
  server = crearServidor({ auth: authDesdeEntorno(env), svc: crearServicio({ db, storage: memoryStorage(), mirror: sinEspejo, env, hoy: () => "2026-12-31" }) });
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(async () => {
  server.close();
  await db.close();
});

type Dispositivo = { store: Store; sync: Sync; fotos: Map<string, Blob>; red: { offline: boolean; perderRespuesta: boolean } };

function dispositivo(nombre: string): Dispositivo {
  const kvMem = new Map<string, unknown>();
  const fotos = new Map<string, Blob>();
  const red = { offline: false, perderRespuesta: false };
  const store = crearStore({
    kv: { get: async (k) => kvMem.get(k) as any, set: async (k, v) => void kvMem.set(k, structuredClone(v)) },
    hoy: () => hoy,
    borrarFoto: async (k) => void fotos.delete(k),
  });
  const llamar = async (metodo: string, path: string, init: { body?: BodyInit; contentType?: string }) => {
    if (red.offline) throw Object.assign(new Error("Sin conexión con el servidor."), { status: 0, code: "NETWORK" });
    peticiones.push(`${metodo} ${path.split("?")[0]}`);
    const res = await fetch(base + path, { method: metodo, headers: { Authorization: `Bearer dev:${nombre}:ADMIN`, ...(init.contentType ? { "Content-Type": init.contentType } : {}) }, body: init.body });
    if (red.perderRespuesta) throw Object.assign(new Error("Sin conexión con el servidor."), { status: 0, code: "NETWORK" }); // el servidor SÍ lo aplicó
    return res;
  };
  const api: SyncApi = {
    async json(metodo, path, body) {
      const res = await llamar(metodo, path, { body: body === undefined ? undefined : JSON.stringify(body), contentType: body === undefined ? undefined : "application/json" });
      const p: any = await res.json();
      if (!res.ok || p.status !== "success") throw Object.assign(new Error(p.error?.message), { status: res.status, code: p.error?.code });
      return p.data;
    },
    async subirFoto(path, blob) {
      const res = await llamar("PUT", path, { body: new Uint8Array(await blob.arrayBuffer()), contentType: blob.type });
      if (!res.ok) throw Object.assign(new Error("foto rechazada"), { status: res.status });
    },
    async bajarFoto(path) {
      return await (await llamar("GET", path, {})).blob();
    },
  };
  const sync = crearSync({ store, api, blobFoto: async (k) => fotos.get(k) ?? null, hoy: () => hoy });
  return { store, sync, fotos, red };
}

let n = 0;
const uid = () => `10000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;
const nuevaFila = (p: Partial<Fila> = {}) => ({
  id: uid(), tipo: "VTA" as const, descripcion: "Venta de panel", responsable: "Adrian", comprobante: "BOLETA" as const,
  caja_ingreso_efectivo: 100, caja_ingreso_transf: 0, caja_salida_efectivo: 0, caja_salida_transf: 0, cta_cte_ingreso: 0, cta_cte_salida: 0,
  categoria: "" as const, subcategoria: "" as const, interno: false, ...p,
});
const foto = (d: Dispositivo, texto = "jpg") => {
  const key = uid();
  const blob = new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xe0, ...Buffer.from(texto)])], { type: "image/jpeg" });
  d.fotos.set(key, blob);
  return { key, mime: "image/jpeg", bytes: blob.size };
};
const enServidor = async (ciudad: string, fecha: string) =>
  (await (await fetch(`${base}/caja/hojas?ciudad=${ciudad}&desde=${fecha}&hasta=${fecha}`, { headers: { Authorization: "Bearer dev:x" } })).json() as any).data.hojas[0];

test("trabajar TODO el día sin conexión y sincronizar al volver: nada se pierde ni se duplica", async () => {
  const a = dispositivo("ana");
  await a.store.init();
  a.store.setCiudad("AQP");
  a.store.setConfig("AQP", { saldo_inicial_caja: 1000, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 });
  await a.sync.sincronizar(); // con red: deja la configuración en el servidor
  assert.equal(pendientes(a.store.get()), 0);

  a.red.offline = true;
  // —— el día completo, sin señal ——
  const ventas = nuevaFila({ descripcion: "Venta de paneles", caja_ingreso_efectivo: 800, caja_ingreso_transf: 150.5 });
  a.store.guardarFila("AQP", hoy, ventas);
  const compra = nuevaFila({ descripcion: "Plumón indeleble", caja_ingreso_efectivo: 0, caja_salida_efectivo: 3, categoria: "Oficina" });
  a.store.guardarFila("AQP", hoy, compra);
  const adjId = a.store.agregarAdjunto("fila", compra.id, foto(a, "recibo-plumon"))!;
  a.store.patchHoja("AQP", hoy, { responsable_caja: "Rosa", obras_realizadas: "Losa nivel 2", maletas: "3" });
  a.store.enviarACajaChica({ ciudad: "AQP", fecha: hoy, monto: 200, nota: "movilidad", responsable: "Rosa" });
  const gasto = { id: uid(), ciudad: "AQP" as const, fecha: hoy, descripcion: "Pasajes", persona: "Carlos", categoria: "Movilidad" as const, subcategoria: "" as const, monto: 12.5, origen: "MANUAL" as const };
  a.store.guardarMov(gasto);
  await a.sync.sincronizar();
  assert.equal(a.sync.estado().fase, "sin-conexion");
  assert.ok(pendientes(a.store.get()) >= 6, "todo quedó en la cola");

  // la pantalla ya muestra los números correctos, sin servidor
  const h = a.store.hoja("AQP", hoy);
  assert.equal(h.saldo_anterior_caja, 1000, "abre con el saldo inicial");
  assert.equal(saldosDe(h).saldo_final_caja, 1000 + 950.5 - 3 - 200);
  assert.equal(saldoCajaChica(a.store.get(), "AQP"), 200 - 12.5);

  // —— vuelve la señal ——
  a.red.offline = false;
  peticiones = [];
  await a.sync.sincronizar();
  assert.equal(pendientes(a.store.get()), 0, "la cola quedó vacía");
  assert.equal(a.sync.estado().fase, "inactivo");

  const srv = await enServidor("AQP", hoy);
  assert.equal(srv.filas.length, 3, "2 filas + la del envío a caja chica, sin duplicados");
  assert.equal(srv.responsable_caja, "Rosa");
  assert.equal(srv.obras_realizadas, "Losa nivel 2");
  assert.equal(srv.saldo_final_caja, 1000 + 950.5 - 3 - 200);
  assert.equal(srv.filas.find((f: Fila) => f.id === compra.id).adjuntos[0].id, adjId, "la foto subió");
  // lo que muestra la app == lo que guardó el servidor
  const local = a.store.hoja("AQP", hoy);
  assert.equal(saldosDe(local).saldo_final_caja, srv.saldo_final_caja);
  assert.equal(local.estimado, false);
  assert.equal(saldoCajaChica(a.store.get(), "AQP"), 187.5);
  assert.equal(a.store.get().chica.AQP.movs.length, 2);
});

test("un segundo dispositivo ve lo del primero; los cambios locales pendientes no se pisan", async () => {
  const a = dispositivo("ana");
  const b = dispositivo("beto");
  await a.store.init();
  await b.store.init();
  await a.sync.sincronizar(); // A trae lo de la prueba anterior (mismo servidor)
  await b.sync.sincronizar();
  const hb = b.store.hoja("AQP", hoy);
  assert.equal(hb.filas.length, 3);
  assert.equal(hb.responsable_caja, "Rosa");
  assert.equal(saldoCajaChica(b.store.get(), "AQP"), 187.5);
  // la foto de A se puede bajar en B (pide sesión)
  const comp = hb.filas.find((f) => f.descripcion === "Plumón indeleble")!;
  const bajada = await b.sync.traerFotoRemota(comp.adjuntos[0].id);
  assert.match(Buffer.from(await bajada.arrayBuffer()).toString("latin1"), /recibo-plumon/);

  // A edita una fila SIN conexión mientras B edita otra distinta
  a.red.offline = true;
  const ventas = a.store.hoja("AQP", hoy).filas.find((f) => f.descripcion === "Venta de paneles")!;
  a.store.guardarFila("AQP", hoy, { ...ventas, descripcion: "Venta de paneles (editada por Ana)" });
  b.store.guardarFila("AQP", hoy, { ...comp, descripcion: "Plumón (editado por Beto)" });
  await b.sync.sincronizar();
  a.red.offline = false;
  // A trae lo de B mientras su propia edición todavía está pendiente: ninguna se pierde
  await a.sync.sincronizar();
  const ha = a.store.hoja("AQP", hoy);
  assert.equal(ha.filas.find((f) => f.id === ventas.id)!.descripcion, "Venta de paneles (editada por Ana)");
  assert.equal(ha.filas.find((f) => f.id === comp.id)!.descripcion, "Plumón (editado por Beto)");
  const srv = await enServidor("AQP", hoy);
  assert.equal(srv.filas.find((f: Fila) => f.id === ventas.id).descripcion, "Venta de paneles (editada por Ana)");
});

test("si la respuesta se pierde después de que el servidor aplicó el cambio, reintentar no duplica", async () => {
  const a = dispositivo("ana");
  await a.store.init();
  await a.sync.sincronizar();
  const antes = (await enServidor("AQP", hoy)).filas.length;
  const saldoChicaAntes = saldoCajaChica(a.store.get(), "AQP");
  a.store.guardarFila("AQP", hoy, nuevaFila({ descripcion: "Se cortó al responder", caja_ingreso_efectivo: 10 }));
  a.store.enviarACajaChica({ ciudad: "AQP", fecha: hoy, monto: 25, nota: "", responsable: "Ana" });
  a.red.perderRespuesta = true;
  await a.sync.sincronizar();
  assert.equal(a.sync.estado().fase, "sin-conexion");
  assert.ok(pendientes(a.store.get()) > 0, "la app cree que no llegó");
  a.red.perderRespuesta = false;
  await a.sync.sincronizar();
  assert.equal(pendientes(a.store.get()), 0);
  assert.equal((await enServidor("AQP", hoy)).filas.length, antes + 2, "una fila y un envío, no el doble");
  assert.equal(saldoCajaChica(a.store.get(), "AQP"), saldoChicaAntes + 25, "la caja chica recibió el envío una sola vez");
});

test("lo que el servidor rechaza queda marcado en esa fila y no frena al resto", async () => {
  const a = dispositivo("ana");
  await a.store.init();
  await a.sync.sincronizar();
  const buena = nuevaFila({ descripcion: "Esta sí pasa", caja_ingreso_efectivo: 5 });
  const mala = nuevaFila({ descripcion: "Esta no", caja_ingreso_efectivo: 0, caja_salida_efectivo: 5, categoria: "Material" });
  a.store.guardarFila("AQP", hoy, mala);
  a.store.guardarFila("AQP", hoy, buena);
  // un envío imposible: más de lo que hay en caja
  a.store.enviarACajaChica({ ciudad: "AQP", fecha: hoy, monto: 9_999_999, nota: "", responsable: "Ana" });
  a.store.mutar((s) => { // el servidor tiene la regla; hacemos que esta fila sea inválida para él alterando la categoría local
    const h = s.hojas[`AQP:${hoy}`];
    h.filas = h.filas.map((f) => (f.id === mala.id ? { ...f, categoria: "" as const } : f));
  });
  await a.sync.sincronizar();
  const s = a.store.get();
  const errores = s.outbox.filter((o) => o.error);
  assert.equal(errores.length, 2, JSON.stringify(errores));
  assert.match(errores.find((o) => o.ref === mala.id)!.error!, /categor/i);
  assert.match(errores.find((o) => o.kind === "transfer")!.error!, /caja diaria tiene/i);
  assert.equal((await enServidor("AQP", hoy)).filas.some((f: Fila) => f.id === buena.id), true, "la buena sí llegó");
  assert.equal(a.sync.estado().fase, "inactivo", "no es un problema de red");

  // la persona corrige la fila mala → se vuelve a mandar sola
  const corregida = a.store.hoja("AQP", hoy).filas.find((f) => f.id === mala.id)!;
  assert.ok(Object.keys(validarFila({ ...corregida })).length > 0, "la app también la marca inválida");
  a.store.guardarFila("AQP", hoy, { ...corregida, categoria: "Material" });
  await a.sync.sincronizar();
  assert.equal(a.store.get().outbox.filter((o) => o.error).length, 1, "solo queda el envío imposible");
  assert.equal((await enServidor("AQP", hoy)).filas.some((f: Fila) => f.id === mala.id), true);
  // descartar el envío imposible
  a.store.anularTransferencia("AQP", hoy, a.store.get().outbox.find((o) => o.kind === "transfer")!.ref);
  assert.equal(pendientes(a.store.get()) + a.store.get().outbox.filter((o) => o.error).length, 0);
});

test("borrar algo que nunca llegó al servidor no genera tráfico; borrar algo que sí llegó, lo borra allá", async () => {
  const a = dispositivo("ana");
  await a.store.init();
  await a.sync.sincronizar();
  a.red.offline = true;
  const efimera = nuevaFila({ descripcion: "La borro antes de sincronizar" });
  a.store.guardarFila("AQP", hoy, efimera);
  const fid = a.store.agregarAdjunto("fila", efimera.id, foto(a))!;
  a.store.borrarFila("AQP", hoy, efimera.id);
  assert.equal(a.store.get().outbox.some((o) => o.ref === efimera.id || o.ref === fid), false, "no queda ni la fila ni su foto en la cola");
  a.red.offline = false;

  const real = nuevaFila({ descripcion: "Esta sí se sincroniza" });
  a.store.guardarFila("AQP", hoy, real);
  await a.sync.sincronizar();
  assert.equal((await enServidor("AQP", hoy)).filas.some((f: Fila) => f.id === real.id), true);
  a.store.borrarFila("AQP", hoy, real.id);
  peticiones = [];
  await a.sync.sincronizar();
  assert.ok(peticiones.includes("DELETE /caja/filas/" + real.id));
  assert.equal((await enServidor("AQP", hoy)).filas.some((f: Fila) => f.id === real.id), false);
  assert.equal(peticiones.filter((p) => p.includes(efimera.id)).length, 0);
});

test("un día nuevo: la hoja se abre limpia con el cierre de ayer, también sin conexión", async () => {
  const a = dispositivo("ana");
  await a.store.init();
  await a.sync.sincronizar();
  const cierreHoy = saldosDe(a.store.hoja("AQP", hoy)).saldo_final_caja;
  const cajaHoy = saldoCaja(a.store.get(), "AQP").caja;
  assert.equal(cajaHoy, cierreHoy);

  hoy = "2026-10-23"; // pasa la medianoche
  a.red.offline = true;
  a.store.abrirHoja("AQP", hoy);
  const manana = a.store.hoja("AQP", hoy);
  assert.equal(manana.filas.length, 0, "arranca limpia");
  assert.equal(manana.saldo_anterior_caja, cierreHoy, "con el saldo de ayer");
  assert.equal(manana.responsable_caja, "Rosa", "y con el mismo responsable de caja");
  assert.equal(manana.estimado, true);
  a.store.guardarFila("AQP", hoy, nuevaFila({ descripcion: "Primera venta del día", caja_ingreso_efectivo: 40 }));

  a.red.offline = false;
  await a.sync.sincronizar();
  const srv = await enServidor("AQP", hoy);
  assert.equal(srv.saldo_anterior_caja, cierreHoy, "el servidor llega al mismo número que estimó la app");
  assert.equal(a.store.hoja("AQP", hoy).saldo_anterior_caja, srv.saldo_anterior_caja);
  assert.equal(a.store.hoja("AQP", hoy).estimado, false);
  assert.equal(saldoCaja(a.store.get(), "AQP").caja, cierreHoy + 40);
  // la hoja de ayer sigue ahí, intacta, para los reportes
  assert.equal((await enServidor("AQP", "2026-10-22")).filas.length > 0, true);
});

test("anular un envío a caja chica desde la app devuelve el dinero a la caja diaria", async () => {
  const a = dispositivo("ana");
  await a.store.init();
  await a.sync.sincronizar();
  const cajaAntes = saldoCaja(a.store.get(), "AQP").caja;
  const chicaAntes = saldoCajaChica(a.store.get(), "AQP");
  const tid = a.store.enviarACajaChica({ ciudad: "AQP", fecha: hoy, monto: 30, nota: "prueba", responsable: "Ana" });
  await a.sync.sincronizar();
  assert.equal(saldoCaja(a.store.get(), "AQP").caja, cajaAntes - 30);
  assert.equal(saldoCajaChica(a.store.get(), "AQP"), chicaAntes + 30);
  a.store.anularTransferencia("AQP", hoy, tid);
  assert.equal(saldoCaja(a.store.get(), "AQP").caja, cajaAntes, "inmediato, sin esperar al servidor");
  await a.sync.sincronizar();
  assert.equal(pendientes(a.store.get()), 0);
  const srv = await enServidor("AQP", hoy);
  assert.equal(srv.saldo_final_caja, cajaAntes);
  assert.equal(srv.filas.some((f: Fila) => f.transferencia_id === tid), false);
  assert.equal(saldoCajaChica(a.store.get(), "AQP"), chicaAntes);
});

test("el almacén sobrevive a cerrar y volver a abrir la app", async () => {
  const kvMem = new Map<string, unknown>();
  const mk = () => crearStore({ kv: { get: async (k) => kvMem.get(k) as any, set: async (k, v) => void kvMem.set(k, structuredClone(v)) }, hoy: () => hoy });
  const s1 = mk();
  await s1.init();
  s1.setCiudad("MOQ");
  s1.guardarFila("MOQ", hoy, nuevaFila({ descripcion: "Pendiente al cerrar" }));
  await s1.vaciar();
  const s2 = mk(); // "reabrir"
  await s2.init();
  assert.equal(s2.get().ciudad, "MOQ");
  assert.equal(s2.hoja("MOQ", hoy).filas[0].descripcion, "Pendiente al cerrar");
  assert.equal(pendientes(s2.get()), 2, "abrirHoja + putFila siguen en la cola");
});

test("si el servidor no deja anular un envío (la caja chica ya gastó ese dinero), se restaura y se avisa", async () => {
  const a = dispositivo("ana");
  await a.store.init();
  await a.sync.sincronizar();
  const chica0 = saldoCajaChica(a.store.get(), "MOQ");
  const caja0 = saldoCaja(a.store.get(), "MOQ").caja;
  a.store.setConfig("MOQ", { saldo_inicial_caja: 500, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 });
  await a.sync.sincronizar();
  const tid = a.store.enviarACajaChica({ ciudad: "MOQ", fecha: hoy, monto: 100, nota: "", responsable: "Ana" });
  a.store.guardarMov({ id: uid(), ciudad: "MOQ", fecha: hoy, descripcion: "Gastó casi todo", persona: "Ana", categoria: "Material", subcategoria: "", monto: 90, origen: "MANUAL" });
  await a.sync.sincronizar();
  const cajaConEnvio = saldoCaja(a.store.get(), "MOQ").caja;
  const chicaConEnvio = saldoCajaChica(a.store.get(), "MOQ");
  assert.equal(chicaConEnvio, 10);

  a.store.anularTransferencia("MOQ", hoy, tid); // en pantalla desaparece al instante…
  assert.equal(saldoCaja(a.store.get(), "MOQ").caja, cajaConEnvio + 100);
  await a.sync.sincronizar(); // …pero el servidor dice que no
  assert.equal(a.store.get().avisos.length, 1);
  assert.match(a.store.get().avisos[0].texto, /ya gastó/i);
  assert.equal(pendientes(a.store.get()) + a.store.get().outbox.filter((o) => o.error).length, 0, "no queda nada colgado en la cola");
  assert.equal(saldoCaja(a.store.get(), "MOQ").caja, cajaConEnvio, "el envío volvió a aparecer");
  assert.equal(saldoCajaChica(a.store.get(), "MOQ"), chicaConEnvio);
  void chica0; void caja0;
});
