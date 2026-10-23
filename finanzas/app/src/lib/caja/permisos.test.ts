import { test } from "node:test";
import assert from "node:assert/strict";
import { diaCerrado, motivoSoloLectura, permisosDeRol, puedeEditarDia, SIN_PERMISOS } from "./permisos";
import { describirCambio, diferencias } from "./revision";

const HOY = "2026-10-22";

test("cada rol tiene su alcance; los demás roles no entran", () => {
  assert.equal(permisosDeRol("admin").reabrir, true);
  assert.equal(permisosDeRol("finanzas").cerrar, true);
  assert.equal(permisosDeRol("finanzas").reabrir, false);
  assert.equal(permisosDeRol("encargado").corregir_pasado, false);
  assert.equal(permisosDeRol("encargado").revisar, true);
  assert.deepEqual(permisosDeRol("almacen"), SIN_PERMISOS);
  assert.deepEqual(permisosDeRol("EMPLEADO"), SIN_PERMISOS);
});

test("un día se puede editar según rol, fecha y cierre", () => {
  const enc = permisosDeRol("encargado");
  const fin = permisosDeRol("finanzas");
  assert.equal(puedeEditarDia(enc, HOY, HOY, false), true);
  assert.equal(puedeEditarDia(enc, "2026-10-21", HOY, false), false);
  assert.equal(puedeEditarDia(fin, "2026-10-21", HOY, false), true);
  assert.equal(puedeEditarDia(fin, HOY, HOY, true), false);
  assert.match(motivoSoloLectura(enc, "2026-10-21", HOY, false) ?? "", /solo lectura/);
  assert.match(motivoSoloLectura(fin, HOY, HOY, true) ?? "", /cerrado/);
  assert.equal(motivoSoloLectura(fin, HOY, HOY, false), null);
});

test("un día anterior a uno cerrado también queda cerrado, pero no al revés ni en la otra ciudad", () => {
  const hojas = {
    "AQP|2026-10-21": { ciudad: "AQP", fecha: "2026-10-21" },
    "AQP|2026-10-22": { ciudad: "AQP", fecha: "2026-10-22", cierre: {} },
    "MOQ|2026-10-20": { ciudad: "MOQ", fecha: "2026-10-20" },
  };
  assert.equal(diaCerrado(hojas, "AQP", "2026-10-21"), true);
  assert.equal(diaCerrado(hojas, "AQP", "2026-10-22"), true);
  assert.equal(diaCerrado(hojas, "AQP", "2026-10-23"), false);
  assert.equal(diaCerrado(hojas, "MOQ", "2026-10-20"), false);
});

test("el historial de cambios se lee en español con el valor anterior", () => {
  assert.deepEqual(diferencias({ caja_salida_efectivo: 20, descripcion: "Cable" }, { caja_salida_efectivo: 25, descripcion: "Cable" }), ["salida en efectivo: S/ 20.00 → S/ 25.00"]);
  const c = describirCambio({ accion: "cerrar", entidad: "hoja", antes: null, despues: { efectivo_contado: 190, saldo_calculado: 200, diferencia: -10 }, motivo: "vuelto" });
  assert.match(c.titulo, /falta S\/ 10\.00/);
  assert.ok(c.detalle.includes("nota: vuelto"));
  assert.match(describirCambio({ accion: "reabrir", entidad: "hoja", antes: null, despues: null, motivo: "recibo" }).detalle[0], /recibo/);
});
