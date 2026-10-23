/**
 * Acceso a la base. Una sola interfaz con dos implementaciones: `pg` (producción, el Postgres del
 * ERP) y PGlite (Postgres real compilado a WASM, en memoria: para pruebas y desarrollo sin instalar nada).
 * El SQL del servicio es idéntico en las dos; así las pruebas corren contra Postgres de verdad.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export interface Db {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
  /** Ejecuta un script con varias sentencias y sin parámetros (migraciones). */
  exec(sql: string): Promise<void>;
  /** Corre `fn` dentro de una transacción; si lanza, se deshace todo. */
  tx<T>(fn: (db: Db) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

export async function pgDb(connectionString: string): Promise<Db> {
  const { default: pg } = await import("pg");
  const pool = new pg.Pool({ connectionString });
  const wrap = (c: { query: (sql: string, p?: unknown[]) => Promise<{ rows: unknown[] }> }): Omit<Db, "tx" | "close"> => ({
    query: async <T>(sql: string, params: unknown[] = []) => (await c.query(sql, params)).rows as T[],
    exec: async (sql) => void (await c.query(sql)), // sin parámetros, pg usa el protocolo simple (acepta varias sentencias)
  });
  return {
    ...wrap(pool),
    async tx(fn) {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const out = await fn({ ...wrap(client), tx: (f) => f({ ...wrap(client), tx: undefined as never, close: async () => {} }), close: async () => {} });
        await client.query("COMMIT");
        return out;
      } catch (e) {
        await client.query("ROLLBACK").catch(() => {});
        throw e;
      } finally {
        client.release();
      }
    },
    close: () => pool.end(),
  };
}

export async function pgliteDb(): Promise<Db> {
  const { PGlite } = await import("@electric-sql/pglite");
  const lite = new PGlite();
  const build = (c: { query: (sql: string, p?: unknown[]) => Promise<{ rows: unknown[] }>; exec: (sql: string) => Promise<unknown> }): Db => ({
    query: async <T>(sql: string, params: unknown[] = []) => (await c.query(sql, params)).rows as T[],
    exec: async (sql) => void (await c.exec(sql)),
    tx: async (fn) => fn(build(c)), // dentro de una transacción ya abierta, anidar es seguir en la misma
    close: async () => {},
  });
  return {
    ...build(lite),
    tx: (fn) => lite.transaction(async (t) => fn(build(t))),
    close: () => lite.close(),
  };
}

const MIGRATIONS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../db/migrations");

/** Archivos de migración en orden (001, 002, …). Los `_down` son para deshacer y nunca se aplican solos. */
const archivosDeMigracion = (dir = MIGRATIONS) =>
  fs.readdirSync(dir).filter((f) => /^\d+_.*\.sql$/.test(f) && !f.endsWith("_down.sql")).sort();

/** Aplica todas las migraciones (solo para desarrollo y pruebas, en una base nueva). */
export async function applyMigrations(db: Db) {
  for (const f of archivosDeMigracion()) await db.exec(fs.readFileSync(path.join(MIGRATIONS, f), "utf8"));
}

/**
 * Aplica las migraciones que falten, una sola vez cada una y en orden (queda anotado en `caja_migraciones`).
 * Es lo que corre al arrancar la API en producción: no hace falta ejecutar nada a mano.
 */
export async function migrar(db: Db, dir = MIGRATIONS): Promise<string[]> {
  await db.exec("CREATE TABLE IF NOT EXISTS caja_migraciones (nombre text PRIMARY KEY, aplicada_en timestamptz NOT NULL DEFAULT now())");
  const hechas = new Set((await db.query<{ nombre: string }>("SELECT nombre FROM caja_migraciones")).map((r) => r.nombre));
  const nuevas: string[] = [];
  for (const f of archivosDeMigracion(dir)) {
    if (hechas.has(f)) continue;
    await db.exec(fs.readFileSync(path.join(dir, f), "utf8"));
    await db.query("INSERT INTO caja_migraciones (nombre) VALUES ($1)", [f]);
    nuevas.push(f);
  }
  return nuevas;
}
