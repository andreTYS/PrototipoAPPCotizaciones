/**
 * Quién llama. La app manda el token de sesión que le dio el servidor al iniciar sesión (Authorization: Bearer …).
 * Es el mismo sistema de usuarios y sesiones de toda la plataforma (tablas `usuarios` y `sesiones`, que crea la API
 * principal): una sola cuenta para el Cotizador, el Almacén y Finanzas, y un solo lugar donde se manejan los roles.
 *
 * AUTH_MODE=dev acepta cualquier "Bearer dev:<nombre>[:<rol>]" — solo para desarrollo y pruebas.
 */
import type { Db } from "./db";

export type Usuario = { id: string; nombre: string; email: string; rol: string; token?: string };

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export type Auth = (authorization: string | undefined) => Promise<Usuario>;

/** Sesiones reales: el token tiene que estar en `sesiones`, sin vencer, y su usuario activo. */
export function authSesiones(db: Db): Auth {
  return async (h) => {
    const token = /^Bearer (.+)$/.exec(h ?? "")?.[1]?.trim();
    if (!token) throw new ApiError(401, "NO_AUTORIZADO", "Falta el token de sesión.");
    const [u] = await db.query<{ id: number; usuario: string; nombre: string; rol: string }>(
      `SELECT u.id, u.usuario, u.nombre, u.rol
         FROM sesiones s JOIN usuarios u ON u.id = s.usuario_id
        WHERE s.token = $1 AND s.expira_en > (now() AT TIME ZONE 'America/Lima') AND u.activo`,
      [token],
    );
    if (!u) throw new ApiError(401, "NO_AUTORIZADO", "La sesión expiró o no es válida. Vuelve a iniciar sesión.");
    return { id: String(u.id), nombre: u.nombre, email: u.usuario, rol: u.rol, token };
  };
}

export function authDesdeEntorno(env: NodeJS.ProcessEnv, db?: Db): Auth {
  if (env.AUTH_MODE === "dev") {
    return async (h) => {
      const m = /^Bearer dev:([^:]+)(?::(.+))?$/.exec(h ?? "");
      if (!m) throw new ApiError(401, "NO_AUTORIZADO", "Falta el token de sesión.");
      return { id: m[1], nombre: m[1], email: `${m[1]}@dev.local`, rol: (m[2] ?? "admin").toLowerCase(), token: h?.slice(7) };
    };
  }
  if (!db) throw new Error("Falta la base de datos para validar las sesiones (o AUTH_MODE=dev para desarrollo local).");
  return authSesiones(db);
}
