// Reglas de los documentos compartidos (requerimientos, salidas de
// herramientas y cotizaciones): qué rol puede hacer cada cambio y cuándo se
// pide la clave de edición. La app guarda sus ítems como JSON de categorías.
import { esRol, exigirEdicion, exigirRol, tienePermisoEdicion } from './auth.js';
import { falla } from './errores.js';

// ---------------------------------------------------------------------------
// Forma que entiende la app (los mismos nombres y tipos que su base local)
// ---------------------------------------------------------------------------

const bool = (v) => (v ? 1 : 0);

export function filaRequerimiento(r) {
  return { ...r, urgente: bool(r.urgente), categorias_json: JSON.stringify(r.categorias_json ?? []) };
}

export function filaHerramientas(h) {
  return { ...h, categorias_json: JSON.stringify(h.categorias_json ?? []) };
}

export function filaCotizacion(c) {
  return { ...c, items_json: JSON.stringify(c.items_json ?? []) };
}

export function filaCatalogo(i) {
  return { ...i, base: bool(i.base) };
}

export function filaProducto(p) {
  const { modificado, eliminado, clave_catalogo: _c, actualizado_en: _a, codigo_erp: _e, ...resto } = p;
  return { ...resto, modificado: bool(modificado), eliminado: bool(eliminado) };
}

/** Lo que llega de la app como texto JSON se guarda como JSON de verdad. */
export function jsonDeEntrada(valor, porDefecto = []) {
  if (valor === undefined || valor === null || valor === '') return porDefecto;
  if (typeof valor !== 'string') return valor;
  try {
    return JSON.parse(valor);
  } catch {
    throw falla(400, 'El detalle del documento no tiene un formato válido.');
  }
}

// ---------------------------------------------------------------------------
// Comparar ítems (qué cambió entre la versión guardada y la que llega)
// ---------------------------------------------------------------------------

function aplanar(categorias) {
  const mapa = new Map();
  for (const c of Array.isArray(categorias) ? categorias : []) {
    for (const i of c.items ?? []) {
      mapa.set(`${c.nombre}|${String(i.texto ?? '').toLowerCase()}`, i);
    }
  }
  return mapa;
}

/** ¿Se agregó, quitó o cambió la cantidad/precio de algún ítem? (= una edición) */
export function cambioDeContenido(antes, despues) {
  const a = aplanar(antes);
  const d = aplanar(despues);
  if (a.size !== d.size) return true;
  for (const [k, i] of d) {
    const previo = a.get(k);
    if (!previo) return true;
    if ((previo.cantidad ?? 0) !== (i.cantidad ?? 0)) return true;
    if ((previo.precio ?? null) !== (i.precio ?? null)) return true;
  }
  return false;
}

/** ¿Cambió alguna marca de alistado? */
export function cambioDeAlistado(antes, despues) {
  const a = aplanar(antes);
  for (const [k, i] of aplanar(despues)) {
    const previo = a.get(k);
    if (Boolean(previo?.alistado) !== Boolean(i.alistado)) return true;
  }
  return false;
}

function difiere(antes, despues, campos) {
  return campos.some((c) => (antes[c] ?? null) !== (despues[c] ?? null));
}

// ---------------------------------------------------------------------------
// Requerimientos: pendiente -> aprobado -> listo -> entregado
// ---------------------------------------------------------------------------

const TRANSICIONES_REQ = {
  'pendiente>aprobado': { roles: ['encargado'], accion: 'aprobar requerimientos' },
  'aprobado>listo': { roles: ['almacen'], accion: 'marcar requerimientos como listos' },
  'listo>entregado': { roles: ['empleado', 'encargado', 'almacen', 'vendedor'], accion: 'confirmar entregas' },
};
const REABRIR_REQ = new Set(['listo>aprobado', 'entregado>aprobado']);

export function validarCambioRequerimiento(req, antes, despues) {
  const u = req.usuario;
  if (antes.estado !== despues.estado) {
    const t = `${antes.estado}>${despues.estado}`;
    if (REABRIR_REQ.has(t)) {
      exigirEdicion(req); // se reabre al agregarle algo con la clave
    } else if (TRANSICIONES_REQ[t]) {
      exigirRol(u, TRANSICIONES_REQ[t].accion, ...TRANSICIONES_REQ[t].roles);
    } else {
      throw falla(400, 'Ese cambio de estado no es válido.');
    }
  }
  const edicion =
    cambioDeContenido(antes.categorias_json, despues.categorias_json) ||
    difiere(antes, despues, ['obra', 'solicitante', 'urgente', 'observaciones']);
  if (edicion) exigirEdicion(req);
  if (cambioDeAlistado(antes.categorias_json, despues.categorias_json)) {
    // Quien edita con la clave puede dejar al día lo alistado al agregar cosas.
    if (!tienePermisoEdicion(req)) exigirRol(u, 'alistar materiales', 'almacen');
  }
}

// ---------------------------------------------------------------------------
// Salidas de herramientas: registrado -> pendiente -> conforme
// ---------------------------------------------------------------------------

export function validarCambioHerramientas(req, antes, despues) {
  const u = req.usuario;
  if (antes.estado !== despues.estado) {
    const t = `${antes.estado}>${despues.estado}`;
    if (t === 'registrado>pendiente') exigirRol(u, 'confirmar salidas de herramientas', 'almacen');
    else if (t === 'pendiente>conforme') exigirRol(u, 'confirmar devoluciones', 'almacen', 'encargado');
    else if (t === 'conforme>pendiente') exigirEdicion(req);
    else throw falla(400, 'Ese cambio de estado no es válido.');
  }
  const edicion =
    cambioDeContenido(antes.categorias_json, despues.categorias_json) ||
    difiere(antes, despues, ['obra', 'responsable', 'observaciones']);
  if (edicion) exigirEdicion(req);
}

export function validarCambioCotizacion(req) {
  exigirEdicion(req);
}

export { esRol };
