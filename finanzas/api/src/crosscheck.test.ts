/// <reference types="node" />
/**
 * El SQL del servidor (vistas de saldos) y el cálculo de la app (calc.ts) son dos implementaciones de la misma regla.
 * Esta prueba las enfrenta con datos aleatorios: si alguna vez se desvían, el saldo que ve la persona en el
 * teléfono (calculado localmente mientras no hay conexión) no coincidiría con el que guarda el servidor.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { applyMigrations, pgliteDb } from "./db";
import { crearServicio } from "./service";
import { memoryStorage } from "./storage";
import { sinEspejo } from "./erp";
import { aperturaEstimada, saldoChica, saldosHoja } from "../../app/src/lib/caja/calc";
import type { Hoja } from "../../app/src/lib/caja/types";

// Generador pseudoaleatorio con semilla: el mismo resultado en cada corrida.
let semilla = 20261022;
const rnd = () => ((semilla = (semilla * 1664525 + 1013904223) % 4294967296) / 4294967296);
const monto = () => (rnd() < 0.4 ? 0 : Math.round(rnd() * 100000) / 100);

test("saldos del SQL == saldos de la app, con 30 días de movimientos al azar en dos ciudades", async () => {
  const db = await pgliteDb();
  await applyMigrations(db);
  const env = { AUTH_MODE: "dev" } as NodeJS.ProcessEnv;
  const svc = crearServicio({ db, storage: memoryStorage(), mirror: sinEspejo, env, hoy: () => "2026-12-31" });
  const u = { id: "t", nombre: "t", email: "t", rol: "ADMIN" };
  let n = 0;
  const uid = () => `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;

  for (const ciudad of ["AQP", "MOQ"] as const) {
    const cfg = { saldo_inicial_caja: Math.round(rnd() * 500000) / 100, saldo_inicial_cta_cte: Math.round(rnd() * 500000) / 100, saldo_inicial_caja_chica: Math.round(rnd() * 100000) / 100 };
    await svc.putConfig(ciudad, cfg, u);
    const fechas: string[] = [];
    for (let d = 1; d <= 30; d++) if (rnd() < 0.75) fechas.push(`2026-11-${String(d).padStart(2, "0")}`);
    // las hojas se crean fuera de orden a propósito
    for (const fecha of [...fechas].sort(() => rnd() - 0.5)) {
      const { hoja } = await svc.abrirHoja({ ciudad, fecha }, u);
      for (let i = 0; i < Math.floor(rnd() * 6); i++) {
        const v: number[] = [monto(), monto(), monto(), monto(), monto(), monto()];
        if (v.reduce((a, b) => a + b, 0) === 0) v[0] = 1.1;
        await svc.putFila(uid(), {
          hoja_id: hoja.id, tipo: "OTRO", descripcion: "x", responsable: "t", interno: true, // interno: no exige categoría
          caja_ingreso_efectivo: v[0], caja_ingreso_transf: v[1], caja_salida_efectivo: v[2], caja_salida_transf: v[3], cta_cte_ingreso: v[4], cta_cte_salida: v[5],
        }, u);
      }
    }

    const { hojas } = await svc.hojas({ ciudad, desde: "2026-11-01", hasta: "2026-11-30" });
    assert.ok(hojas.length > 10, "hay datos suficientes");
    const locales = hojas as unknown as Hoja[];
    for (const h of hojas) {
      // 1) totales y saldo final de la hoja, con la apertura que dio el servidor
      const s = saldosHoja(h);
      assert.equal(s.saldo_final_caja, h.saldo_final_caja, `${ciudad} ${h.fecha} saldo final caja`);
      assert.equal(s.saldo_final_cta_cte, h.saldo_final_cta_cte, `${ciudad} ${h.fecha} saldo final cta cte`);
      // 2) la apertura que la app estimaría sin conexión (cadena de cierres + saldo inicial) == la del servidor
      const est = aperturaEstimada(locales, h.fecha, cfg);
      assert.equal(est.saldo_anterior_caja, h.saldo_anterior_caja, `${ciudad} ${h.fecha} apertura caja`);
      assert.equal(est.saldo_anterior_cta_cte, h.saldo_anterior_cta_cte, `${ciudad} ${h.fecha} apertura cta cte`);
    }
    // 3) el saldo actual de la caja = cierre de la última hoja
    const ult = hojas[hojas.length - 1];
    assert.equal((await svc.estado(ciudad)).caja.saldo, ult.saldo_final_caja);
  }

  // Caja chica: el saldo del servidor == saldo base + efecto de los movimientos, en cualquier ventana
  for (const ciudad of ["AQP", "MOQ"] as const) {
    const ids: string[] = [];
    for (let i = 0; i < 25; i++) {
      const fecha = `2026-11-${String(1 + Math.floor(rnd() * 28)).padStart(2, "0")}`;
      const id = uid();
      if (rnd() < 0.3) {
        const { hoja } = await svc.abrirHoja({ ciudad, fecha }, u);
        await svc.putFila(uid(), { hoja_id: hoja.id, tipo: "OTRO", descripcion: "fondeo", responsable: "t", interno: true, caja_ingreso_efectivo: 100000 }, u);
        await svc.crearTransferencia({ id, fila_id: uid(), movimiento_id: uid(), ciudad, fecha, monto: Math.max(0.01, monto()), nota: "" }, u);
      } else {
        await svc.putMovChica(id, { ciudad, fecha, descripcion: "g", categoria: "Material", monto: Math.max(0.01, monto()) }, u);
      }
      ids.push(id);
    }
    for (const [desde, hasta] of [["2026-11-01", "2026-11-30"], ["2026-11-10", "2026-11-20"], ["2026-11-25", "2026-12-15"]]) {
      const r = await svc.movimientosChica({ ciudad, desde, hasta });
      const todos = await svc.movimientosChica({ ciudad, desde: "2026-11-01", hasta: "2026-12-31" });
      // saldo de la app = saldo anterior de la ventana + movimientos de la ventana (+ lo posterior a la ventana)
      const posteriores = todos.movimientos.filter((m: any) => m.fecha > hasta);
      assert.equal(saldoChica(r.saldo_anterior, [...r.movimientos, ...posteriores]), r.saldo, `${ciudad} ventana ${desde}..${hasta}`);
    }
  }
  await db.close();
});
