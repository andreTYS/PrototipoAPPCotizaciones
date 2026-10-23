/**
 * Cliente de la API de Finanzas (la misma plataforma de usuarios del Cotizador y el Almacén).
 *
 * Cada persona entra con su propio usuario y clave; el token de SU sesión es el único que usa esta app y el servidor
 * decide, según su rol, qué puede hacer (el candado de código compartido ya no existe). La app trabaja siempre conectada:
 * no guarda datos propios en el dispositivo, solo la sesión. Rutas: /caja/* y /caja-chica/*.
 *
 * Formato de respuesta:  { status: "success", data }  |  { status: "error", error: { code, message } }
 */
import AsyncStorage from "@react-native-async-storage/async-storage";
import { permisosDeRol, type Permisos } from "./caja/permisos";

// En producción la web y la API viven en el mismo dominio (finanzas.…/api-caja), así que basta la ruta relativa.
const BASE_URL = (process.env.EXPO_PUBLIC_API_URL || "/api-caja").replace(/\/+$/, "");
const SESSION_KEY = "cajaobra.session.v1";

export type Session = { token: string; nombre: string; email: string; rolCodigo: string; permisos: Permisos };

let session: Session | null = null;
let onUnauthorized: (() => void) | null = null;

/** La app se entera cuando el ERP dice que la sesión ya no vale (para volver a la pantalla de ingreso). */
export const setUnauthorizedHandler = (fn: (() => void) | null) => {
  onUnauthorized = fn;
};

export async function loadSession(): Promise<Session | null> {
  if (session) return session;
  try {
    const raw = await AsyncStorage.getItem(SESSION_KEY);
    const guardada = raw ? (JSON.parse(raw) as Session) : null;
    session = guardada ? { ...guardada, permisos: guardada.permisos ?? permisosDeRol(guardada.rolCodigo) } : null;
  } catch {
    session = null;
  }
  return session;
}

async function saveSession(next: Session | null) {
  session = next;
  try {
    if (next) await AsyncStorage.setItem(SESSION_KEY, JSON.stringify(next));
    else await AsyncStorage.removeItem(SESSION_KEY);
  } catch {}
}

/** `status` 0 = no hubo respuesta (sin red). Con status 5xx o 0 conviene reintentar; con 4xx el servidor ya dijo que no. */
export class ApiError extends Error {
  constructor(message: string, public code?: string, public status = 0) {
    super(message);
  }
  get sinRed() {
    return this.status === 0 || this.status >= 500;
  }
}

async function enviar(method: string, path: string, init: { body?: BodyInit; contentType?: string }): Promise<Response> {
  const headers: Record<string, string> = {};
  if (init.contentType) headers["Content-Type"] = init.contentType;
  if (session?.token) headers.Authorization = `Bearer ${session.token}`;
  let res: Response;
  try {
    res = await fetch(`${BASE_URL}${path}`, { method, headers, body: init.body });
  } catch {
    throw new ApiError("Sin conexión con el servidor.", "NETWORK", 0);
  }
  if (res.status === 401 && session) {
    await saveSession(null);
    onUnauthorized?.();
  }
  return res;
}

async function leerError(res: Response): Promise<ApiError> {
  const body = await res.json().catch(() => null);
  return new ApiError(body?.error?.message || `El servidor respondió ${res.status}`, body?.error?.code, res.status);
}

/** JSON hacia el ERP; devuelve `data`. */
export async function apiJson<T = any>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await enviar(method, path, { body: body === undefined ? undefined : JSON.stringify(body), contentType: body === undefined ? undefined : "application/json" });
  const payload = await res.json().catch(() => null);
  if (!res.ok || payload?.status !== "success") throw new ApiError(payload?.error?.message || `El servidor respondió ${res.status}`, payload?.error?.code, res.status);
  return payload.data as T;
}

/** Sube una foto (cuerpo binario). */
export async function apiSubirFoto(path: string, blob: Blob): Promise<void> {
  const res = await enviar("PUT", path, { body: blob, contentType: blob.type || "image/jpeg" });
  if (!res.ok) throw await leerError(res);
}

/** Baja una foto (pide sesión, por eso no se puede usar directo en un <img src>). */
export async function apiBajarFoto(path: string): Promise<Blob> {
  const res = await enviar("GET", path, {});
  if (!res.ok) throw await leerError(res);
  return res.blob();
}

export async function login(usuario: string, clave: string): Promise<Session> {
  const res = await enviar("POST", "/auth/login", { body: JSON.stringify({ usuario, clave }), contentType: "application/json" });
  const payload = await res.json().catch(() => null);
  if (!res.ok || payload?.status !== "success") throw new ApiError(payload?.error?.message || `El servidor respondió ${res.status}`, payload?.error?.code, res.status);
  const data = payload.data;
  const next: Session = {
    token: data.token, nombre: data.user.nombre_completo, email: data.user.email, rolCodigo: data.user.rol_codigo,
    permisos: data.permisos ?? permisosDeRol(data.user.rol_codigo),
  };
  await saveSession(next);
  return next;
}

/** Vuelve a pedir los permisos del rol (por si el administrador los cambió desde la última vez que entró). */
export async function refrescarPermisos(): Promise<Session | null> {
  if (!session) return null;
  try {
    const r = await apiJson<{ usuario: { nombre: string; rol: string }; permisos: Permisos }>("GET", "/caja/permisos");
    await saveSession({ ...session, nombre: r.usuario.nombre || session.nombre, rolCodigo: r.usuario.rol, permisos: r.permisos });
  } catch {
    // sin conexión: se queda con los que ya tenía
  }
  return session;
}

export async function logout() {
  await saveSession(null);
}

export function currentSession(): Session | null {
  return session;
}
