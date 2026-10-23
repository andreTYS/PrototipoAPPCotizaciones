/**
 * Lo que cada rol puede hacer en Finanzas. Quien decide de verdad es el servidor (api/src/permisos.ts); esto solo sirve
 * para mostrar u ocultar botones. Al iniciar sesión el servidor manda sus permisos; esta tabla es el respaldo y es la
 * misma que usa el servidor por defecto.
 */
export type Permisos = {
  /** Entrar a Finanzas y registrar movimientos del día. */
  acceso: boolean;
  /** Corregir días anteriores (movimientos, fotos, observaciones, caja chica). */
  corregir_pasado: boolean;
  /** Cerrar el día (arqueo). */
  cerrar: boolean;
  /** Reabrir un día cerrado. */
  reabrir: boolean;
  /** Cambiar los saldos iniciales. */
  configurar: boolean;
  /** Ver alertas y el historial de cambios. */
  revisar: boolean;
};

export const SIN_PERMISOS: Permisos = { acceso: false, corregir_pasado: false, cerrar: false, reabrir: false, configurar: false, revisar: false };

const ROLES = {
  admin: { acceso: true, corregir_pasado: true, cerrar: true, reabrir: true, configurar: true, revisar: true },
  finanzas: { acceso: true, corregir_pasado: true, cerrar: true, reabrir: false, configurar: false, revisar: true },
  encargado: { acceso: true, corregir_pasado: false, cerrar: false, reabrir: false, configurar: false, revisar: true },
} satisfies Record<string, Permisos>;

export const ROL_LABEL: Record<string, string> = { admin: "Administrador", finanzas: "Finanzas", encargado: "Encargado", almacen: "Almacén", empleado: "Empleado", vendedor: "Vendedor" };

/** Permisos por defecto de un rol (si el servidor no los mandó). */
export function permisosDeRol(rol: string): Permisos {
  return (ROLES as Record<string, Permisos>)[(rol ?? "").toLowerCase()] ?? SIN_PERMISOS;
}

/** ¿Se puede registrar o corregir algo en ese día? (el servidor lo vuelve a comprobar) */
export function puedeEditarDia(p: Permisos, fecha: string, hoy: string, cerrado: boolean): boolean {
  if (!p.acceso || cerrado) return false;
  return fecha >= hoy || p.corregir_pasado;
}

/** Por qué un día está en solo lectura (para explicárselo a la persona). */
export function motivoSoloLectura(p: Permisos, fecha: string, hoy: string, cerrado: boolean): string | null {
  if (cerrado) return "Día cerrado: ya no se puede cambiar. Si hay un error, un administrador puede reabrirlo.";
  if (fecha < hoy && !p.corregir_pasado) return "Día anterior · solo lectura. Para corregirlo, pídeselo a Finanzas.";
  return null;
}

/** ¿Ese día (o uno posterior de la misma ciudad) ya está cerrado? Entonces tampoco se puede tocar. */
export function diaCerrado(hojas: Record<string, { ciudad: string; fecha: string; cierre?: unknown }>, ciudad: string, fecha: string): boolean {
  return Object.values(hojas).some((h) => h.ciudad === ciudad && h.fecha >= fecha && !!h.cierre);
}
