import { randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { consulta } from './db.js';
import { falla } from './errores.js';

export const ROLES = ['admin', 'empleado', 'encargado', 'almacen', 'vendedor', 'finanzas'];
const DIAS_SESION = 30;
const MINUTOS_EDICION = 15;

// ---------------------------------------------------------------------------
// Sesión — las credenciales nunca se guardan acá: cada login se valida
// contra el ERP real (el mismo /auth/login que ya usan el ERP web e
// ICR-TIENDA) y, si dice que sí, se espeja el usuario localmente (upsert por
// su id del ERP) solo para las foreign keys de bitacora/creado_por — nunca
// la clave.
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

// Mapea el rol_codigo real del ERP al rol simplificado que usa este backend.
// Ajusta esta lista si en el ERP los códigos de rol son otros — se ve con
// SELECT DISTINCT rol_codigo FROM usuarios en la base del ERP.
function mapearRolErp(rolErp) {
  switch (String(rolErp ?? '').toUpperCase()) {
    case 'ADMIN': return 'admin';
    case 'SUPERVISOR': return 'encargado';
    case 'VENTAS': return 'vendedor';
    case 'ALMACENERO': return 'almacen';
    default: return 'empleado'; // cualquier empleado puede mandar requerimientos
  }
}

async function validarContraErp(email, clave) {
  const base = process.env.ERP_API_URL || 'https://erp.inversionesicr.com/api';
  const controlador = new AbortController();
  const vencido = setTimeout(() => controlador.abort(), 10_000);
  let resp;
  try {
    resp = await fetch(`${base}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: clave }),
      signal: controlador.signal,
    });
  } catch {
    throw falla(503, 'No se pudo conectar con el ERP, intenta de nuevo.');
  } finally {
    clearTimeout(vencido);
  }
  const datos = await resp.json().catch(() => null);
  if (!resp.ok || !datos?.data?.user) throw falla(401, 'Correo o clave incorrectos.');
  return datos.data.user;
}

export async function iniciarSesion(ip, email, clave, dispositivo) {
  limitarIntentos(ip);
  const correo = String(email ?? '').trim();
  let usuarioErp;
  try {
    usuarioErp = await validarContraErp(correo, clave);
  } catch (e) {
    if (e?.codigo === 401) anotarFallo(ip);
    throw e;
  }
  intentos.delete(ip);
  const id = Number(usuarioErp.usuario_id);
  const nombre = String(usuarioErp.nombre_completo ?? correo);
  const rol = mapearRolErp(usuarioErp.rol_codigo);
  const { rows: filasU } = await consulta(
    `INSERT INTO usuarios (id, usuario, nombre, clave_hash, rol, activo)
     VALUES ($1, $2, $3, '', $4, TRUE)
     ON CONFLICT (id) DO UPDATE SET usuario = EXCLUDED.usuario, nombre = EXCLUDED.nombre, rol = EXCLUDED.rol, activo = TRUE
     RETURNING *`,
    [id, correo.toLowerCase(), nombre, rol],
  );
  const u = filasU[0];
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
// Usuarios: ya no se administran acá — cada cuenta se espeja sola al entrar
// con su correo y clave del ERP (ver iniciarSesion). Solo lectura, para ver
// quién ha entrado.
// ---------------------------------------------------------------------------

export async function listarUsuarios() {
  const { rows } = await consulta('SELECT id, usuario, nombre, rol, activo FROM usuarios ORDER BY lower(nombre)');
  return rows;
}
