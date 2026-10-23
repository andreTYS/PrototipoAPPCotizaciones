/**
 * Quién puede hacer qué en Finanzas. Los roles son los mismos de todo el sistema (usuarios.rol): admin, finanzas,
 * encargado, almacen, empleado, vendedor. Se comprueba en el SERVIDOR; la app solo esconde los botones que no corresponden.
 *
 * Valores por defecto (se pueden cambiar con variables de entorno, separando los roles con coma):
 *   FINANZAS_ROLES            admin,finanzas,encargado   entrar a Finanzas y registrar movimientos del día
 *   FINANZAS_ROLES_CORREGIR   admin,finanzas             corregir días anteriores (incluida la caja chica)
 *   FINANZAS_ROLES_CERRAR     admin,finanzas             cerrar el día (arqueo)
 *   FINANZAS_ROLES_REABRIR    admin                      reabrir un día cerrado (queda anotado con el motivo)
 *   FINANZAS_ROLES_CONFIG     admin                      cambiar los saldos iniciales
 *   FINANZAS_ROLES_REVISAR    admin,finanzas,encargado   ver alertas, historial de cambios y reportes
 */
import type { Usuario } from "./auth";

const lista = (valor: string | undefined, porDefecto: string[]) =>
  (valor ?? "").trim() ? valor!.split(",").map((r) => r.trim().toLowerCase()).filter(Boolean) : porDefecto;

export type Permisos = ReturnType<typeof crearPermisos>;

export function crearPermisos(env: NodeJS.ProcessEnv = {}) {
  const acceso = lista(env.FINANZAS_ROLES, ["admin", "finanzas", "encargado"]);
  const corregir = lista(env.FINANZAS_ROLES_CORREGIR, ["admin", "finanzas"]);
  const cerrar = lista(env.FINANZAS_ROLES_CERRAR, ["admin", "finanzas"]);
  const reabrir = lista(env.FINANZAS_ROLES_REABRIR, ["admin"]);
  const config = lista(env.FINANZAS_ROLES_CONFIG, ["admin"]);
  const revisar = lista(env.FINANZAS_ROLES_REVISAR, ["admin", "finanzas", "encargado"]);
  const rol = (u: Pick<Usuario, "rol">) => (u.rol ?? "").toLowerCase();
  // El administrador siempre puede todo.
  const en = (roles: string[]) => (u: Pick<Usuario, "rol">) => rol(u) === "admin" || roles.includes(rol(u));
  return {
    acceso: en(acceso),
    corregirPasado: en(corregir),
    cerrar: en(cerrar),
    reabrir: en(reabrir),
    configurar: en(config),
    revisar: en(revisar),
    /** Lo que la app necesita saber para mostrar u ocultar botones. */
    de: (u: Pick<Usuario, "rol">) => ({
      acceso: en(acceso)(u), corregir_pasado: en(corregir)(u), cerrar: en(cerrar)(u), reabrir: en(reabrir)(u), configurar: en(config)(u), revisar: en(revisar)(u),
    }),
  };
}
