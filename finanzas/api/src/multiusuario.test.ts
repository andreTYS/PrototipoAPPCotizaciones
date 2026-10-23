/// <reference types="node" />
/**
 * Varias personas a la vez sobre los mismos datos, con el motor de sincronización de la app contra la API real:
 * lo que una registra lo ve la otra, el cierre del día bloquea a todos, y cada rol tiene su alcance.
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
import { crearStore, saldosDe } from "../../app/src/lib/caja/store";
import { crearSync, type SyncApi } from "../../app/src/lib/caja/sync";
import { diaCerrado, motivoSoloLectura, permisosDeRol } from "../../app/src/lib/caja/permisos";
import { hojaKey, type Fila } from "../../app/src/lib/caja/types";

let db: Db;
let server: ReturnType<typeof crearServidor>;
let base = "";
const HOY = "2026-10-22";
const AYER = "2026-10-21";

before(async () => {
  db = await pgliteDb();
  await applyMigrations(db);
  const env = { AUTH_MODE: "dev" } as NodeJS.ProcessEnv;
  server = crearServidor({ auth: authDesdeEntorno(env), svc: crearServicio({ db, storage: memoryStorage(), mirror: sinEspejo, env, hoy: () => HOY }) });
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(async () => {
  server.close();
  await db.close();
});

/** Un teléfono/computadora de una persona con su rol: tiene su propio almacén en memoria y habla con la API por HTTP. */
function persona(nombre: string, rol: string) {
  const store = crearStore({ hoy: () => HOY });
  const api: SyncApi = {
    async json(metodo, path, body) {
      const res = await fetch(base + path, { method: metodo, headers: { Authorization: `Bearer dev:${nombre}:${rol}`, ...(body === undefined ? {} : { "Content-Type": "application/json" }) }, body: body === undefined ? undefined : JSON.stringify(body) });
      const p: any = await res.json();
      if (!res.ok || p.status !== "success") throw Object.assign(new Error(p.error?.message), { status: res.status, code: p.error?.code });
      return p.data;
    },
    async subirFoto() {},
    async bajarFoto() {
      return new Blob([]);
    },
  };
  const sync = crearSync({ store, api, blobFoto: async () => null, hoy: () => HOY });
  return { store, sync, permisos: permisosDeRol(rol) };
}

let n = 0;
const uid = () => `20000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;
const venta = (monto: number, p: Partial<Fila> = {}) => ({ id: uid(), tipo: "VTA" as const, descripcion: "Venta", responsable: "Ana", comprobante: "BOLETA" as const, caja_ingreso_efectivo: monto, caja_ingreso_transf: 0, caja_salida_efectivo: 0, caja_salida_transf: 0, cta_cte_ingreso: 0, cta_cte_salida: 0, categoria: "" as const, subcategoria: "" as const, interno: false, ...p });

test("dos personas trabajan a la vez: cada una ve lo que registró la otra", async () => {
  const ana = persona("ana", "finanzas");
  const beto = persona("beto", "encargado");
  ana.store.abrirHoja("AQP", HOY);
  ana.store.guardarFila("AQP", HOY, venta(100));
  await ana.sync.sincronizar(true);
  await beto.sync.sincronizar(true);
  assert.equal(beto.store.get().hojas[hojaKey("AQP", HOY)]?.filas.length, 1);
  beto.store.guardarFila("AQP", HOY, venta(50, { descripcion: "Venta de beto" }));
  await beto.sync.sincronizar(true);
  await ana.sync.sincronizar(true);
  const h = ana.store.get().hojas[hojaKey("AQP", HOY)];
  assert.equal(h.filas.length, 2);
  assert.equal(saldosDe(h).totales.caja.ingreso, 150);
});

test("el encargado no puede corregir días anteriores; Finanzas sí", async () => {
  const ana = persona("ana", "finanzas");
  const beto = persona("beto", "encargado");
  assert.equal(motivoSoloLectura(beto.permisos, AYER, HOY, false)?.includes("solo lectura"), true);
  assert.equal(motivoSoloLectura(ana.permisos, AYER, HOY, false), null);
  ana.store.abrirHoja("MOQ", AYER);
  await ana.sync.sincronizar(true);
  beto.store.guardarFila("MOQ", AYER, venta(30)); // el servidor lo rechaza
  await beto.sync.sincronizar(true);
  assert.match(beto.store.get().avisos.map((a) => a.texto).join(" "), /Solo Finanzas/); // el servidor lo rechazó y se le avisó
  assert.equal(beto.store.get().outbox.length, 0);
  ana.store.guardarFila("MOQ", AYER, venta(30));
  await ana.sync.sincronizar(true);
  assert.equal(ana.sync.errores().length, 0);
});

test("cerrar el día desde la app: la diferencia queda guardada, el día se bloquea para todos y solo el admin lo reabre", async () => {
  const ana = persona("ana", "finanzas");
  const beto = persona("beto", "encargado");
  const admin = persona("root", "admin");
  ana.store.abrirHoja("MOQ", HOY);
  ana.store.guardarFila("MOQ", HOY, venta(200));
  await ana.sync.sincronizar(true);
  // el encargado no puede cerrar
  await assert.rejects(() => beto.sync.cerrarHoja("MOQ", AYER, 0, ""), /permiso|Solo|403|encontr/i);
  assert.equal((await ana.sync.cerrarHoja("MOQ", AYER, 30, "")).diferencia, 0); // los días se cierran en orden
  const cierre = await ana.sync.cerrarHoja("MOQ", HOY, 220, "faltaron 10 de vuelto");
  assert.equal(cierre.diferencia, -10);
  assert.equal(cierre.saldo_calculado, saldosDe(ana.store.get().hojas[hojaKey("MOQ", HOY)]).saldo_final_caja);
  // el encargado lo ve cerrado y no puede agregar nada
  await beto.sync.sincronizar(true);
  assert.ok(beto.store.get().hojas[hojaKey("MOQ", HOY)].cierre);
  assert.equal(diaCerrado(beto.store.get().hojas, "MOQ", HOY), true);
  assert.match(motivoSoloLectura(beto.permisos, HOY, HOY, true) ?? "", /cerrado/i);
  beto.store.quitarAviso(beto.store.get().avisos[0]?.id ?? "");
  beto.store.guardarFila("MOQ", HOY, venta(5));
  await beto.sync.sincronizar(true);
  assert.match(beto.store.get().avisos.map((a) => a.texto).join(" "), /cerrado/i);
  await ana.sync.sincronizar(true);
  assert.equal(ana.store.get().hojas[hojaKey("MOQ", HOY)].filas.length, 1); // lo de beto no entró
  // Finanzas no puede reabrir; el administrador sí, con motivo
  await assert.rejects(() => ana.sync.reabrirHoja("MOQ", HOY, "me equivoqué"));
  await admin.sync.sincronizar(true);
  await admin.sync.reabrirHoja("MOQ", HOY, "faltaba un recibo");
  await ana.sync.sincronizar(true);
  assert.equal(ana.store.get().hojas[hojaKey("MOQ", HOY)].cierre ?? null, null);
});
