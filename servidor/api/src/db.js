import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import pg from 'pg';

const aqui = dirname(fileURLToPath(import.meta.url));
export const carpetaDb = process.env.DB_DIR || join(aqui, '..', '..', 'db');

// Números como números (no como texto) y fechas como ISO sin zona: la app
// guarda la hora local de Perú tal cual la escribe.
pg.types.setTypeParser(20, (v) => parseInt(v, 10)); // bigint
pg.types.setTypeParser(1700, (v) => parseFloat(v)); // numeric
pg.types.setTypeParser(1114, (v) => v.replace(' ', 'T')); // timestamp

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres@localhost:5432/cotizador',
  max: 10,
});

export const consulta = (texto, valores = []) => pool.query(texto, valores);

/** Ejecuta varias sentencias como una sola transacción. */
export async function enTransaccion(trabajo) {
  const cliente = await pool.connect();
  try {
    await cliente.query('BEGIN');
    const resultado = await trabajo(cliente);
    await cliente.query('COMMIT');
    return resultado;
  } catch (e) {
    await cliente.query('ROLLBACK');
    throw e;
  } finally {
    cliente.release();
  }
}

/**
 * Deja la base lista cada vez que arranca la API (se puede repetir sin
 * riesgo): crea las tablas, aplica las migraciones nuevas, carga los datos
 * iniciales una sola vez y crea el primer administrador.
 */
export async function prepararBase() {
  await consulta(readFileSync(join(carpetaDb, 'schema.sql'), 'utf8'));

  // Migraciones: db/migraciones/NNN_nombre.sql, una sola vez cada una y en orden.
  await consulta('CREATE TABLE IF NOT EXISTS migraciones (nombre TEXT PRIMARY KEY, aplicada_en TIMESTAMP NOT NULL DEFAULT now())');
  const carpetaMigraciones = join(carpetaDb, 'migraciones');
  if (existsSync(carpetaMigraciones)) {
    const hechas = new Set((await consulta('SELECT nombre FROM migraciones')).rows.map((f) => f.nombre));
    for (const archivo of readdirSync(carpetaMigraciones).filter((a) => a.endsWith('.sql')).sort()) {
      if (hechas.has(archivo)) continue;
      await enTransaccion(async (c) => {
        await c.query(readFileSync(join(carpetaMigraciones, archivo), 'utf8'));
        await c.query('INSERT INTO migraciones (nombre) VALUES ($1)', [archivo]);
      });
      console.log(`Migración aplicada: ${archivo}`);
    }
  }

  // Datos iniciales (productos, listas, maletas): solo si la base está vacía.
  const seedHecho = await consulta("SELECT 1 FROM configuracion WHERE clave = 'seed_aplicado'");
  if (seedHecho.rowCount === 0) {
    const archivoSeed = join(carpetaDb, 'seed.sql');
    if (existsSync(archivoSeed) && (await consulta('SELECT 1 FROM productos LIMIT 1')).rowCount === 0) {
      await enTransaccion((c) => c.query(readFileSync(archivoSeed, 'utf8')));
      console.log('Datos iniciales cargados (productos, listas y maletas).');
    }
    await consulta("INSERT INTO configuracion (clave, valor) VALUES ('seed_aplicado', '1') ON CONFLICT DO NOTHING");
  }

  // Clave para editar documentos (por defecto 1234; se guarda cifrada).
  if ((await consulta("SELECT 1 FROM configuracion WHERE clave = 'clave_edicion'")).rowCount === 0) {
    const hash = await bcrypt.hash(process.env.CLAVE_EDICION || '1234', 10);
    await consulta("INSERT INTO configuracion (clave, valor) VALUES ('clave_edicion', $1)", [hash]);
  }

  // No hay administrador que crear acá: cada cuenta se espeja sola la
  // primera vez que esa persona entra con su correo y clave del ERP (ver
  // iniciarSesion en auth.js).
}
