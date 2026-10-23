// Pruebas de la API contra una base PostgreSQL de verdad.
// Uso:  DATABASE_ADMIN_URL=postgres://postgres@localhost:5432/postgres npm test
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import pg from 'pg';

const admin = process.env.DATABASE_ADMIN_URL || 'postgres://postgres@localhost:5432/postgres';
const nombreBase = `cotizador_test_${process.pid}`;
process.env.DATABASE_URL = admin.replace(/\/[^/]*$/, `/${nombreBase}`);
process.env.ADMIN_USUARIO = 'admin';
process.env.ADMIN_CLAVE = 'admin-clave-1';
process.env.UPLOAD_DIR = mkdtempSync(join(tmpdir(), 'subidas-'));

const { crearApp } = await import('../src/index.js');
const { prepararBase, pool } = await import('../src/db.js');

let servidor;
let base;

async function llamar(metodo, ruta, { token, edicion, cuerpo, crudo, tipo } = {}) {
  const cabeceras = {};
  if (token) cabeceras.authorization = `Bearer ${token}`;
  if (edicion) cabeceras['x-edicion'] = edicion;
  let body;
  if (crudo) {
    body = crudo;
    cabeceras['content-type'] = tipo ?? 'application/octet-stream';
  } else if (cuerpo !== undefined) {
    body = JSON.stringify(cuerpo);
    cabeceras['content-type'] = 'application/json';
  }
  const r = await fetch(`${base}${ruta}`, { method: metodo, headers: cabeceras, body });
  const texto = await r.text();
  return { estado: r.status, datos: texto ? JSON.parse(texto) : null };
}

const sesiones = {};
async function entrar(usuario, clave) {
  const r = await llamar('POST', '/api/login', { cuerpo: { usuario, clave } });
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  return r.datos.token;
}

const categorias = (items) =>
  JSON.stringify([{ nombre: '1. CONDUIT', items }, { nombre: '2. FOTOVOLTAICO', items: [{ texto: 'Conector MC4', cantidad: 20 }] }]);

async function crearReq(token, extra = {}) {
  const num = (await llamar('POST', '/api/correlativos/requerimiento', { token })).datos.valor;
  const numero = `REQ-${String(num).padStart(4, '0')}`;
  const r = await llamar('POST', '/api/requerimientos', {
    token,
    cuerpo: {
      numero, obra: 'Obra X', solicitante: 'Juan', urgente: 0, fecha_creacion: '2026-10-22T09:00:00.000',
      categorias_json: categorias([{ texto: 'Tubo Conduit 1"', cantidad: 11, precio: 19 }, { texto: 'Curva 90°', cantidad: 10, precio: 3 }]),
      ...extra,
    },
  });
  assert.equal(r.estado, 201, JSON.stringify(r.datos));
  return r.datos;
}

before(async () => {
  const c = new pg.Client({ connectionString: admin });
  await c.connect();
  await c.query(`DROP DATABASE IF EXISTS ${nombreBase}`);
  await c.query(`CREATE DATABASE ${nombreBase}`);
  await c.end();
  await prepararBase();
  await new Promise((ok) => {
    servidor = crearApp().listen(0, () => ok());
  });
  base = `http://127.0.0.1:${servidor.address().port}`;
  sesiones.admin = await entrar('admin', 'admin-clave-1');
  for (const [usuario, rol] of [['juan', 'empleado'], ['carlos', 'encargado'], ['pedro', 'almacen'], ['ana', 'almacen'], ['vera', 'vendedor'], ['fina', 'finanzas']]) {
    const r = await llamar('POST', '/api/usuarios', { token: sesiones.admin, cuerpo: { usuario, nombre: usuario.toUpperCase(), clave: 'clave-segura', rol } });
    assert.equal(r.estado, 201, JSON.stringify(r.datos));
    sesiones[usuario] = await entrar(usuario, 'clave-segura');
  }
});

after(async () => {
  servidor?.close();
  await pool.end();
  const c = new pg.Client({ connectionString: admin });
  await c.connect();
  await c.query(`DROP DATABASE IF EXISTS ${nombreBase} WITH (FORCE)`);
  await c.end();
});

describe('acceso', () => {
  it('rechaza claves incorrectas y pedidos sin sesión', async () => {
    assert.equal((await llamar('POST', '/api/login', { cuerpo: { usuario: 'admin', clave: 'mala' } })).estado, 401);
    assert.equal((await llamar('GET', '/api/requerimientos')).estado, 401);
    assert.equal((await llamar('GET', '/api/requerimientos', { token: 'x'.repeat(64) })).estado, 401);
  });

  it('solo el administrador gestiona usuarios', async () => {
    assert.equal((await llamar('GET', '/api/usuarios', { token: sesiones.juan })).estado, 403);
    const r = await llamar('GET', '/api/usuarios', { token: sesiones.admin });
    assert.equal(r.estado, 200);
    assert.ok(r.datos.some((u) => u.usuario === 'carlos' && u.rol === 'encargado'));
    assert.ok(r.datos.some((u) => u.usuario === 'fina' && u.rol === 'finanzas'));
    assert.equal((await llamar('POST', '/api/usuarios', { token: sesiones.admin, cuerpo: { usuario: 'juan', nombre: 'x', clave: 'clave-segura', rol: 'empleado' } })).estado, 409);
  });

  it('un usuario desactivado pierde el acceso', async () => {
    const r = await llamar('POST', '/api/usuarios', { token: sesiones.admin, cuerpo: { usuario: 'temporal', nombre: 'Temporal', clave: 'clave-segura', rol: 'empleado' } });
    const token = await entrar('temporal', 'clave-segura');
    await llamar('PUT', `/api/usuarios/${r.datos.id}`, { token: sesiones.admin, cuerpo: { activo: false } });
    assert.equal((await llamar('GET', '/api/yo', { token })).estado, 401);
    assert.equal((await llamar('POST', '/api/login', { cuerpo: { usuario: 'temporal', clave: 'clave-segura' } })).estado, 401);
  });
});

describe('datos iniciales', () => {
  it('carga los 800 productos, las listas y las maletas', async () => {
    const productos = await llamar('GET', '/api/productos', { token: sesiones.juan });
    assert.equal(productos.datos.length, 800);
    assert.ok(productos.datos[0].categoria_producto);
    const materiales = await llamar('GET', '/api/checklist-catalogo?tipo=materiales', { token: sesiones.juan });
    const herramientas = await llamar('GET', '/api/checklist-catalogo?tipo=herramientas', { token: sesiones.juan });
    assert.equal(materiales.datos.length + herramientas.datos.length, 99);
    assert.equal(materiales.datos[0].precio, 19);
    const maletas = await llamar('GET', '/api/maletas', { token: sesiones.juan });
    assert.equal(maletas.datos.length, 3);
    assert.equal(maletas.datos.flatMap((m) => m.categorias.flatMap((c) => c.items)).length, 72);
  });

  it('los números de documento no se repiten', async () => {
    const [a, b] = await Promise.all([
      llamar('POST', '/api/correlativos/cotizacion', { token: sesiones.vera }),
      llamar('POST', '/api/correlativos/cotizacion', { token: sesiones.juan }),
    ]);
    assert.notEqual(a.datos.valor, b.datos.valor);
  });
});

describe('requerimientos compartidos entre usuarios', () => {
  it('recorrido completo: pedir, aprobar, alistar entre dos personas, entregar', async () => {
    const creado = await crearReq(sesiones.juan);
    assert.equal(creado.estado, 'pendiente');
    assert.equal(creado.version, 1);
    assert.equal(typeof creado.categorias_json, 'string');

    // Otra persona ve el mismo requerimiento
    const visto = (await llamar('GET', '/api/requerimientos', { token: sesiones.carlos })).datos.find((r) => r.id === creado.id);
    assert.equal(visto.solicitante, 'Juan');

    // Un empleado no puede aprobar; el encargado sí
    const aprobar = (token, v) => llamar('PUT', `/api/requerimientos/${creado.id}`, {
      token, cuerpo: { ...creado, version: v, estado: 'aprobado', aprobado_por: 'Carlos', fecha_aprobacion: '2026-10-22T10:00:00.000' },
    });
    assert.equal((await aprobar(sesiones.juan, 1)).estado, 403);
    const aprobado = await aprobar(sesiones.carlos, 1);
    assert.equal(aprobado.estado, 200);
    assert.equal(aprobado.datos.estado, 'aprobado');
    assert.equal(aprobado.datos.version, 2);

    // Pedro alista 2 de 3 (solo almacén puede)
    const cats = JSON.parse(aprobado.datos.categorias_json);
    const marcar = (cs, hasta, quien) => cs.flatMap((c) => c.items).slice(0, hasta).forEach((i) => Object.assign(i, { alistado: true, alistado_por: quien, fecha_alistado: '2026-10-22T11:00:00.000' }));
    marcar(cats, 2, 'Pedro');
    const intento = (token, v, cs, estado = 'aprobado') =>
      llamar('PUT', `/api/requerimientos/${creado.id}`, { token, cuerpo: { ...aprobado.datos, version: v, estado, categorias_json: JSON.stringify(cs) } });
    assert.equal((await intento(sesiones.juan, 2, cats)).estado, 403);
    const parcial = await intento(sesiones.pedro, 2, cats);
    assert.equal(parcial.estado, 200);
    assert.equal(parcial.datos.estado, 'aprobado');

    // Ana, con la lista vieja, no pisa a Pedro: recibe aviso de conflicto
    const sinActualizar = await intento(sesiones.ana, 2, JSON.parse(aprobado.datos.categorias_json));
    assert.equal(sinActualizar.estado, 409);

    // Ana continúa donde quedó Pedro y termina
    const recargado = (await llamar('GET', '/api/requerimientos', { token: sesiones.ana })).datos.find((r) => r.id === creado.id);
    const cats2 = JSON.parse(recargado.categorias_json);
    cats2.flatMap((c) => c.items).filter((i) => !i.alistado).forEach((i) => Object.assign(i, { alistado: true, alistado_por: 'Ana', fecha_alistado: '2026-10-22T15:00:00.000' }));
    const listo = await llamar('PUT', `/api/requerimientos/${creado.id}`, {
      token: sesiones.ana, cuerpo: { ...recargado, estado: 'listo', alistado_por: 'Pedro, Ana', fecha_listo: '2026-10-22T15:00:00.000', categorias_json: JSON.stringify(cats2) },
    });
    assert.equal(listo.estado, 200);
    assert.equal(listo.datos.estado, 'listo');
    assert.equal(listo.datos.version, 4);

    // El solicitante confirma la entrega
    const entregado = await llamar('PUT', `/api/requerimientos/${creado.id}`, {
      token: sesiones.juan, cuerpo: { ...listo.datos, estado: 'entregado', recibido_por: 'Juan', fecha_entrega: '2026-10-22T16:00:00.000' },
    });
    assert.equal(entregado.estado, 200);
    assert.equal(entregado.datos.estado, 'entregado');
  });

  it('editar (agregar un material) pide la clave y reabre el requerimiento', async () => {
    const creado = await crearReq(sesiones.juan);
    const cats = JSON.parse(creado.categorias_json);
    cats[0].items.push({ texto: 'Abrazaderas', cantidad: 20, precio: 2, es_extra: true, agregado_despues: true });
    const cuerpo = { ...creado, categorias_json: JSON.stringify(cats), observaciones: '[Editado 22/10 10:00] + Abrazaderas × 20' };

    // sin clave: rechazado
    assert.equal((await llamar('PUT', `/api/requerimientos/${creado.id}`, { token: sesiones.juan, cuerpo })).estado, 403);

    // clave incorrecta y correcta
    assert.equal((await llamar('POST', '/api/clave-edicion', { token: sesiones.juan, cuerpo: { clave: '0000' } })).estado, 403);
    const permiso = await llamar('POST', '/api/clave-edicion', { token: sesiones.juan, cuerpo: { clave: '1234' } });
    assert.equal(permiso.estado, 200);

    // el permiso de otra persona no sirve
    assert.equal((await llamar('PUT', `/api/requerimientos/${creado.id}`, { token: sesiones.carlos, edicion: permiso.datos.token_edicion, cuerpo })).estado, 403);

    const editado = await llamar('PUT', `/api/requerimientos/${creado.id}`, { token: sesiones.juan, edicion: permiso.datos.token_edicion, cuerpo });
    assert.equal(editado.estado, 200);
    assert.equal(JSON.parse(editado.datos.categorias_json)[0].items.length, 3);
    assert.match(editado.datos.observaciones, /Editado/);
  });

  it('solo el administrador elimina', async () => {
    const creado = await crearReq(sesiones.juan);
    assert.equal((await llamar('DELETE', `/api/requerimientos/${creado.id}`, { token: sesiones.juan })).estado, 403);
    assert.equal((await llamar('DELETE', `/api/requerimientos/${creado.id}`, { token: sesiones.admin })).estado, 200);
  });

  it('rechaza saltarse estados y datos incompletos', async () => {
    const creado = await crearReq(sesiones.juan);
    const salto = await llamar('PUT', `/api/requerimientos/${creado.id}`, { token: sesiones.admin, cuerpo: { ...creado, estado: 'entregado' } });
    assert.equal(salto.estado, 400);
    const sinObra = await llamar('POST', '/api/requerimientos', { token: sesiones.juan, cuerpo: { numero: 'REQ-9999', obra: '', solicitante: 'x', fecha_creacion: '2026-10-22T09:00:00.000' } });
    assert.equal(sinObra.estado, 400);
  });
});

describe('salidas de herramientas', () => {
  it('registrar, confirmar salida, devolver y volver a abrir al editar', async () => {
    const num = (await llamar('POST', '/api/correlativos/herramientas', { token: sesiones.juan })).datos.valor;
    const cats = JSON.stringify([{ nombre: 'Primer nivel', items: [{ texto: 'Taladro', cantidad: 1 }] }]);
    const creado = (await llamar('POST', '/api/herramientas', {
      token: sesiones.juan,
      cuerpo: { numero: `HER-${String(num).padStart(4, '0')}`, obra: 'Obra Y', responsable: 'Luis', fecha_salida: '2026-10-22T08:00:00.000', categorias_json: cats },
    })).datos;
    assert.equal(creado.estado, 'registrado');

    const put = (token, extra, edicion) => llamar('PUT', `/api/herramientas/${extra.version}`.replace(/\d+$/, creado.id), { token, edicion, cuerpo: { ...creado, ...extra } });
    const salida = { estado: 'pendiente', version: 1, salida_confirmada_por: 'Pedro', fecha_confirmacion_salida: '2026-10-22T09:00:00.000',
      categorias_json: JSON.stringify([{ nombre: 'Primer nivel', items: [{ texto: 'Taladro', cantidad: 1, salio: true }] }]) };
    assert.equal((await put(sesiones.juan, salida)).estado, 403); // un empleado no confirma salidas
    const pendiente = await put(sesiones.pedro, salida);
    assert.equal(pendiente.estado, 200);

    const devolucion = { ...pendiente.datos, estado: 'conforme', encargado: 'Carlos', fecha_devolucion: '2026-10-23T09:00:00.000',
      categorias_json: JSON.stringify([{ nombre: 'Primer nivel', items: [{ texto: 'Taladro', cantidad: 1, salio: true, volvio: true }] }]) };
    const conforme = await llamar('PUT', `/api/herramientas/${creado.id}`, { token: sesiones.carlos, cuerpo: devolucion });
    assert.equal(conforme.estado, 200);
    assert.equal(conforme.datos.estado, 'conforme');

    // Agregar una herramienta olvidada (con clave) la deja pendiente de nuevo
    const permiso = (await llamar('POST', '/api/clave-edicion', { token: sesiones.juan, cuerpo: { clave: '1234' } })).datos.token_edicion;
    const cats2 = JSON.parse(conforme.datos.categorias_json);
    cats2[0].items.push({ texto: 'Amoladora', cantidad: 1, salio: true, agregado_despues: true });
    const reabierta = await llamar('PUT', `/api/herramientas/${creado.id}`, {
      token: sesiones.juan, edicion: permiso, cuerpo: { ...conforme.datos, estado: 'pendiente', fecha_devolucion: null, categorias_json: JSON.stringify(cats2) },
    });
    assert.equal(reabierta.estado, 200);
    assert.equal(reabierta.datos.estado, 'pendiente');
  });
});

describe('cotizaciones, productos y listas', () => {
  it('crear una cotización, verla desde otro usuario y editarla con la clave', async () => {
    const num = (await llamar('POST', '/api/correlativos/cotizacion', { token: sesiones.vera })).datos.valor;
    const cuerpo = {
      numero: `S${String(num).padStart(5, '0')}`, cliente: 'Cliente SAC', fecha: '2026-10-22T09:30:00.000', total: 200,
      items_json: JSON.stringify([{ nombre: 'Panel 100W', cantidad: 2, precio_unitario: 100 }]),
    };
    const creada = await llamar('POST', '/api/cotizaciones', { token: sesiones.vera, cuerpo });
    assert.equal(creada.estado, 201);
    assert.equal(creada.datos.total, 200);

    const lista = (await llamar('GET', '/api/cotizaciones', { token: sesiones.juan })).datos;
    assert.ok(lista.some((c) => c.numero === cuerpo.numero));

    const editar = (edicion) => llamar('PUT', `/api/cotizaciones/${creada.datos.id}`, { token: sesiones.vera, edicion, cuerpo: { ...creada.datos, total: 250 } });
    assert.equal((await editar(undefined)).estado, 403);
    const permiso = (await llamar('POST', '/api/clave-edicion', { token: sesiones.vera, cuerpo: { clave: '1234' } })).datos.token_edicion;
    const ok = await editar(permiso);
    assert.equal(ok.estado, 200);
    assert.equal(ok.datos.total, 250);
    assert.equal(ok.datos.version, 2);
    assert.equal((await editar(permiso)).estado, 409); // versión vieja
  });

  it('agregar, editar y eliminar productos', async () => {
    const nuevo = await llamar('POST', '/api/productos', { token: sesiones.juan, cuerpo: { nombre: 'Cable especial', categoria_producto: 'CABLES', precio_venta: 50 } });
    assert.equal(nuevo.estado, 201);
    assert.equal(nuevo.datos.origen, 'local');
    assert.equal((await llamar('PUT', `/api/productos/${nuevo.datos.id}`, { token: sesiones.juan, cuerpo: { ...nuevo.datos, precio_venta: 55 } })).estado, 403);
    const edit = await llamar('PUT', `/api/productos/${nuevo.datos.id}`, { token: sesiones.vera, cuerpo: { ...nuevo.datos, precio_venta: 55 } });
    assert.equal(edit.datos.precio_venta, 55);
    await llamar('DELETE', `/api/productos/${nuevo.datos.id}`, { token: sesiones.vera });
    const todos = (await llamar('GET', '/api/productos', { token: sesiones.juan })).datos;
    assert.equal(todos.length, 800);
    // Uno del catálogo se marca como eliminado y deja de salir
    await llamar('DELETE', `/api/productos/${todos[0].id}`, { token: sesiones.vera });
    assert.equal((await llamar('GET', '/api/productos', { token: sesiones.juan })).datos.length, 799);
  });

  it('listas del checklist y maletas se pueden agregar y editar', async () => {
    const item = await llamar('POST', '/api/checklist-catalogo', { token: sesiones.juan, cuerpo: { tipo: 'materiales', categoria: '1. CONDUIT', nombre: 'Cinta aislante', precio: 4.5 } });
    assert.equal(item.estado, 201);
    assert.equal(item.datos.precio, 4.5);
    assert.equal((await llamar('DELETE', `/api/checklist-catalogo/${item.datos.id}`, { token: sesiones.juan })).estado, 403);
    assert.equal((await llamar('DELETE', `/api/checklist-catalogo/${item.datos.id}`, { token: sesiones.pedro })).estado, 200);

    const m = await llamar('POST', '/api/maletas', { token: sesiones.pedro, cuerpo: { nombre: 'Maleta nueva' } });
    const it = await llamar('POST', `/api/maletas/${m.datos.id}/items`, { token: sesiones.pedro, cuerpo: { nivel: 'Primer nivel', nombre: 'Alicate' } });
    assert.equal(it.estado, 201);
    const maletas = (await llamar('GET', '/api/maletas', { token: sesiones.juan })).datos;
    assert.equal(maletas.find((x) => x.id === m.datos.id).categorias[0].items[0].nombre, 'Alicate');
  });

  it('sube fotos válidas y rechaza archivos que no son imágenes', async () => {
    const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)]);
    const ok = await llamar('POST', '/api/subidas?ext=png', { token: sesiones.juan, crudo: png, tipo: 'image/png' });
    assert.equal(ok.estado, 201);
    assert.match(ok.datos.ruta, /^\/uploads\/[0-9a-f]{24}\.png$/);
    const malo = await llamar('POST', '/api/subidas?ext=png', { token: sesiones.juan, crudo: Buffer.from('<?php echo 1; ?>'.repeat(4)), tipo: 'image/png' });
    assert.equal(malo.estado, 400);
    const archivo = await fetch(`${base}${ok.datos.ruta}`);
    assert.equal(archivo.status, 200);
  });
});

describe('vista general', () => {
  it('resume cuántos documentos hay en cada estado', async () => {
    const r = await llamar('GET', '/api/resumen', { token: sesiones.juan });
    assert.equal(r.estado, 200);
    assert.ok(r.datos.requerimientos.entregado >= 1);
    assert.ok(r.datos.cotizaciones.total >= 1);
    assert.ok(r.datos.herramientas.pendiente >= 1);
  });

  it('deja registro de quién hizo cada cambio', async () => {
    const r = await llamar('GET', '/api/bitacora', { token: sesiones.carlos });
    assert.equal(r.estado, 200);
    assert.ok(r.datos.some((f) => f.accion === 'editar' && f.tabla === 'requerimientos' && f.usuario === 'PEDRO'));
    assert.equal((await llamar('GET', '/api/bitacora', { token: sesiones.juan })).estado, 403);
  });
});
