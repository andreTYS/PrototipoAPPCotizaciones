/**
 * Arranque de la API de referencia.
 *
 * Producción:  DATABASE_URL=postgres://… MAIN_API_URL=http://api:3000 UPLOAD_DIR=/data/fotos API_PREFIX=/api-caja npm start
 * Desarrollo:  AUTH_MODE=dev npm start   (Postgres en memoria con PGlite + migración aplicada; nada se guarda)
 *
 * Variables: PORT (8787), DATABASE_URL, MAIN_API_URL (la API de usuarios) | AUTH_MODE=dev, UPLOAD_DIR (./uploads), FINANZAS_ROLES… (ver permisos.ts),
 *   ERP_API_URL (si se define, cada ingreso/gasto real se refleja en el ERP; si no, no se refleja nada),
 *   CORS_ORIGIN (solo si la app vive en otro origen), API_PREFIX (p. ej. /api-caja).
 */
import { applyMigrations, migrar, pgDb, pgliteDb } from "./db";
import { authDesdeEntorno } from "./auth";
import { diskStorage, memoryStorage } from "./storage";
import { espejoHttp, sinEspejo } from "./erp";
import { crearServicio } from "./service";
import { crearServidor, type LoginPrincipal } from "./server";
import { loginHttp } from "./login";
import { crearPermisos } from "./permisos";

const env = process.env;
const dev = env.AUTH_MODE === "dev";
const db = env.DATABASE_URL ? await pgDb(env.DATABASE_URL) : await pgliteDb();
if (!env.DATABASE_URL) {
  if (!dev) throw new Error("Define DATABASE_URL (o AUTH_MODE=dev para probar con una base en memoria).");
  await applyMigrations(db);
  console.log("Modo desarrollo: base en memoria, se pierde al apagar.");
} else {
  // Producción: las tablas nuevas se crean solas al arrancar (una sola vez cada migración).
  for (const m of await migrar(db)) console.log(`Migración aplicada: ${m}`);
}
const permisos = crearPermisos(env);
const svc = crearServicio({
  db,
  env,
  permisos,
  storage: dev && !env.UPLOAD_DIR ? memoryStorage() : diskStorage(env.UPLOAD_DIR ?? "./uploads"),
  mirror: env.ERP_API_URL ? espejoHttp(env.ERP_API_URL) : sinEspejo,
});
// Los usuarios y las sesiones los maneja la API principal; esta API solo valida el token y pide el inicio de sesión allá.
const principal = (env.MAIN_API_URL ?? "").replace(/\/+$/, "");
const loginPrincipal: LoginPrincipal | undefined = principal ? loginHttp(principal) : undefined;
const port = Number(env.PORT ?? 8787);
crearServidor({ auth: authDesdeEntorno(env, db), svc, permisos, loginPrincipal, corsOrigin: env.CORS_ORIGIN ?? (dev ? "*" : ""), prefijo: env.API_PREFIX ?? "", loginDev: dev }).listen(port, () =>
  console.log(`API de caja escuchando en :${port}${env.ERP_API_URL ? ` · reflejando en ${env.ERP_API_URL}` : " · sin reflejo al ERP"}`),
);
