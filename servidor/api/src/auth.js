import { randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { consulta } from './db.js';
import { falla } from './errores.js';

export const ROLES = ['admin', 'empleado', 'encargado', 'almacen', 'vendedor', 'finanzas'];
const DIAS_SESION = 30;
const MINUTOS_EDICION = 15;

// ---------------------------------------------------------------------------
// Sesión
// ---------------------------------------------------------------------------

const intentos = new Map(); // ip -> { cuenta, desde }

function limitarIntentos(ip) {
  const ahora = Date.now();
  const e = intentos.get(ip);
  if (e && ahora - e.desde > 15 * 60 * 1000) intentos.delete(ip);
  const actual = intentos.get(ip);
  if (actual && actual.cuenta >= 10) {
    throw falla(429, 'Demasiados intentos fallidos. Espera unos minutos e intenta de nuevo.');
  }
}

function anotarFallo(ip) {
  const e = intentos.get(ip) ?? { cuenta: 0, desde: Date.now() };
  e.cuenta += 1;
  intentos.set(ip, e);
}

export async function iniciarSesion(ip, usuario, clave, dispositivo) {
  limitarIntentos(ip);
  const { rows } = await consulta('SELECT * FROM usuarios WHERE lower(usuario) = lower($1)', [String(usuario ?? '').trim()]);
  const u = rows[0];
  const correcto = u && u.activo && (await bcrypt.compare(String(clave ?? ''), u.clave_hash));
  if (!correcto) {
    anotarFallo(ip);
    throw falla(401, 'Usuario o clave incorrectos.');
  }
  intentos.delete(ip);
  await consulta('DELETE FROM sesiones WHERE expira_en < (now() AT TIME ZONE \'America/Lima\')');
  const token = randomBytes(32).toString('hex');
  await consulta(
    `INSERT INTO sesiones (token, usuario_id, dispositivo, expira_en)
     VALUES ($1, $2, $3, (now() AT TIME ZONE 'America/Lima') + ($4 || ' days')::interval)`,
    [token, u.id, String(dispositivo ?? '').slice(0, 120) || null, String(DIAS_SESION)],
  );
  return { token, usuario: publico(u) };
}

export const publico = (u) => ({ id: u.id, usuario: u.usuario, nombre: u.nombre, rol: u.rol, activo: u.activo });

export async function cerrarSesion(token) {
  await consulta('DELETE FROM sesiones WHERE token = $1', [token]);
}

function tokenDe(req) {
  const cabecera = req.get('authorization') ?? '';
  if (cabecera.toLowerCase().startsWith('bearer ')) return cabecera.slice(7).trim();
  return req.get('x-token') ?? null;
}

/** Exige una sesión válida; deja `req.usuario` y `req.token`. */
export async function exigirSesion(req, _res, next) {
  const token = tokenDe(req);
  if (!token) throw falla(401, 'Ingresa con tu usuario y clave.');
  const { rows } = await consulta(
    `SELECT u.* FROM sesiones s JOIN usuarios u ON u.id = s.usuario_id
     WHERE s.token = $1 AND s.expira_en > (now() AT TIME ZONE 'America/Lima') AND u.activo`,
    [token],
  );
  if (rows.length === 0) throw falla(401, 'La sesión venció. Ingresa de nuevo.');
  req.usuario = rows[0];
  req.token = token;
  next();
}

export const esRol = (usuario, ...roles) => usuario.rol === 'admin' || roles.includes(usuario.rol);

/** Lanza 403 si el usuario no tiene alguno de esos roles (el admin siempre puede). */
export function exigirRol(usuario, accion, ...roles) {
  if (!esRol(usuario, ...roles)) {
    throw falla(403, `Tu rol no permite ${accion}.`);
  }
}

// ---------------------------------------------------------------------------
// Clave de edición (1234 al inicio): se verifica aquí y da un permiso corto
// ---------------------------------------------------------------------------

const permisosEdicion = new Map(); // token de edición -> { usuarioId, hasta }

export async function verificarClaveEdicion(usuario, clave) {
  limitarIntentos(`edicion-${usuario.id}`);
  const { rows } = await consulta("SELECT valor FROM configuracion WHERE clave = 'clave_edicion'");
  if (!rows[0] || !(await bcrypt.compare(String(clave ?? ''), rows[0].valor))) {
    anotarFallo(`edicion-${usuario.id}`);
    throw falla(403, 'Clave incorrecta.');
  }
  intentos.delete(`edicion-${usuario.id}`);
  const token = randomBytes(24).toString('hex');
  const hasta = Date.now() + MINUTOS_EDICION * 60 * 1000;
  permisosEdicion.set(token, { usuarioId: usuario.id, hasta });
  for (const [t, p] of permisosEdicion) if (p.hasta < Date.now()) permisosEdicion.delete(t);
  return { token_edicion: token, minutos: MINUTOS_EDICION };
}

export async function cambiarClaveEdicion(nueva) {
  if (String(nueva ?? '').length < 4) throw falla(400, 'La clave debe tener al menos 4 caracteres.');
  const hash = await bcrypt.hash(String(nueva), 10);
  await consulta(
    `INSERT INTO configuracion (clave, valor) VALUES ('clave_edicion', $1)
     ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor, actualizado_en = now() AT TIME ZONE 'America/Lima'`,
    [hash],
  );
  permisosEdicion.clear();
}

/** ¿Esta petición trae un permiso de edición vigente de este usuario? */
export function tienePermisoEdicion(req) {
  const t = req.get('x-edicion');
  const p = t ? permisosEdicion.get(t) : null;
  return Boolean(p && p.usuarioId === req.usuario.id && p.hasta > Date.now());
}

export function exigirEdicion(req) {
  if (!tienePermisoEdicion(req)) throw falla(403, 'Para editar ingresa la clave de edición.');
}

// ---------------------------------------------------------------------------
// Usuarios (administración)
// ---------------------------------------------------------------------------

export async function listarUsuarios() {
  const { rows } = await consulta('SELECT id, usuario, nombre, rol, activo FROM usuarios ORDER BY lower(nombre)');
  return rows;
}

export async function crearUsuario({ usuario, nombre, clave, rol }) {
  const u = String(usuario ?? '').trim().toLowerCase();
  if (!/^[a-z0-9._-]{3,60}$/.test(u)) throw falla(400, 'El usuario debe tener 3 a 60 caracteres: letras, números, punto, guion.');
  if (String(nombre ?? '').trim() === '') throw falla(400, 'Escribe el nombre de la persona.');
  if (String(clave ?? '').length < 6) throw falla(400, 'La clave debe tener al menos 6 caracteres.');
  if (!ROLES.includes(rol)) throw falla(400, 'Rol no válido.');
  if ((await consulta('SELECT 1 FROM usuarios WHERE lower(usuario) = $1', [u])).rowCount > 0) {
    throw falla(409, 'Ese usuario ya existe.');
  }
  const { rows } = await consulta(
    'INSERT INTO usuarios (usuario, nombre, clave_hash, rol) VALUES ($1, $2, $3, $4) RETURNING id, usuario, nombre, rol, activo',
    [u, String(nombre).trim(), await bcrypt.hash(String(clave), 10), rol],
  );
  return rows[0];
}

export async function actualizarUsuario(id, { nombre, clave, rol, activo }, yoId) {
  if (rol !== undefined && !ROLES.includes(rol)) throw falla(400, 'Rol no válido.');
  if (clave !== undefined && String(clave).length < 6) throw falla(400, 'La clave debe tener al menos 6 caracteres.');
  if (Number(id) === yoId && (activo === false || (rol !== undefined && rol !== 'admin'))) {
    throw falla(400, 'No puedes quitarte el acceso ni el rol de administrador a ti mismo.');
  }
  const { rows } = await consulta(
    `UPDATE usuarios SET
       nombre = COALESCE($2, nombre),
       clave_hash = COALESCE($3, clave_hash),
       rol = COALESCE($4, rol),
       activo = COALESCE($5, activo)
     WHERE id = $1 RETURNING id, usuario, nombre, rol, activo`,
    [id, nombre ?? null, clave === undefined ? null : await bcrypt.hash(String(clave), 10), rol ?? null, activo ?? null],
  );
  if (rows.length === 0) throw falla(404, 'No existe ese usuario.');
  if (activo === false || clave !== undefined) await consulta('DELETE FROM sesiones WHERE usuario_id = $1', [id]);
  return rows[0];
}

export async function cambiarMiClave(usuario, actual, nueva) {
  if (!(await bcrypt.compare(String(actual ?? ''), usuario.clave_hash))) throw falla(403, 'La clave actual no es correcta.');
  if (String(nueva ?? '').length < 6) throw falla(400, 'La clave nueva debe tener al menos 6 caracteres.');
  await consulta('UPDATE usuarios SET clave_hash = $2 WHERE id = $1', [usuario.id, await bcrypt.hash(String(nueva), 10)]);
}
