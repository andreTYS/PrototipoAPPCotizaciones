import { randomBytes } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import express, { Router } from 'express';
import {
  actualizarUsuario, cambiarClaveEdicion, cambiarMiClave, cerrarSesion, crearUsuario, exigirRol, exigirSesion,
  iniciarSesion, listarUsuarios, publico, verificarClaveEdicion,
} from './auth.js';
import { consulta, enTransaccion } from './db.js';
import {
  filaCatalogo, filaCotizacion, filaHerramientas, filaProducto, filaRequerimiento, jsonDeEntrada,
  validarCambioCotizacion, validarCambioHerramientas, validarCambioRequerimiento,
} from './documentos.js';
import { falla } from './errores.js';

export const carpetaSubidas = process.env.UPLOAD_DIR || join(process.cwd(), 'uploads');

const nulo = (v) => (v === undefined || v === '' ? null : v);
const entero = (v) => {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) throw falla(400, 'Identificador no válido.');
  return n;
};
const texto = (v, mensaje) => {
  const t = String(v ?? '').trim();
  if (!t) throw falla(400, mensaje);
  return t;
};

async function bitacora(req, accion, tabla, registroId, detalle) {
  await consulta(
    'INSERT INTO bitacora (usuario_id, usuario, accion, tabla, registro_id, detalle) VALUES ($1,$2,$3,$4,$5,$6)',
    [req.usuario?.id ?? null, req.usuario?.nombre ?? null, accion, tabla, registroId ?? null, detalle ?? null],
  );
}

const conflicto = () =>
  falla(409, 'Otra persona modificó esto mientras lo estabas viendo. Se actualizó la lista: revisa y vuelve a intentarlo.');

export function crearRutas() {
  const r = Router();

  // -------------------------------------------------------------------------
  // Públicas
  // -------------------------------------------------------------------------
  r.get('/salud', async (_req, res) => {
    await consulta('SELECT 1');
    res.json({ ok: true });
  });

  r.post('/login', async (req, res) => {
    res.json(await iniciarSesion(req.ip, req.body?.usuario, req.body?.clave, req.get('user-agent')));
  });

  // -------------------------------------------------------------------------
  // Todo lo demás pide sesión
  // -------------------------------------------------------------------------
  r.use(exigirSesion);

  r.post('/logout', async (req, res) => {
    await cerrarSesion(req.token);
    res.json({ ok: true });
  });
  r.get('/yo', (req, res) => res.json(publico(req.usuario)));
  r.post('/yo/clave', async (req, res) => {
    await cambiarMiClave(req.usuario, req.body?.actual, req.body?.nueva);
    res.json({ ok: true });
  });

  // Usuarios (solo administrador)
  r.get('/usuarios', async (req, res) => {
    exigirRol(req.usuario, 'ver los usuarios');
    res.json(await listarUsuarios());
  });
  r.post('/usuarios', async (req, res) => {
    exigirRol(req.usuario, 'crear usuarios');
    const u = await crearUsuario(req.body ?? {});
    await bitacora(req, 'crear', 'usuarios', u.id, `${u.usuario} (${u.rol})`);
    res.status(201).json(u);
  });
  r.put('/usuarios/:id', async (req, res) => {
    exigirRol(req.usuario, 'cambiar usuarios');
    const u = await actualizarUsuario(entero(req.params.id), req.body ?? {}, req.usuario.id);
    await bitacora(req, 'editar', 'usuarios', u.id, `${u.usuario} (${u.rol}${u.activo ? '' : ', desactivado'})`);
    res.json(u);
  });

  // Clave de edición
  r.post('/clave-edicion', async (req, res) => {
    res.json(await verificarClaveEdicion(req.usuario, req.body?.clave));
  });
  r.put('/clave-edicion', async (req, res) => {
    exigirRol(req.usuario, 'cambiar la clave de edición');
    await cambiarClaveEdicion(req.body?.nueva);
    await bitacora(req, 'editar', 'configuracion', null, 'clave de edición cambiada');
    res.json({ ok: true });
  });

  // Números de documento (S00001, REQ-0001, HER-0001) sin repetirse
  r.post('/correlativos/:clave', async (req, res) => {
    const { rows } = await consulta('UPDATE correlativos SET valor = valor + 1 WHERE clave = $1 RETURNING valor', [req.params.clave]);
    if (rows.length === 0) throw falla(404, 'Ese correlativo no existe.');
    res.json({ valor: rows[0].valor });
  });

  // -------------------------------------------------------------------------
  // Productos
  // -------------------------------------------------------------------------
  r.get('/productos', async (_req, res) => {
    const { rows } = await consulta('SELECT * FROM productos WHERE NOT eliminado ORDER BY categoria_producto, nombre');
    res.json(rows.map(filaProducto));
  });

  const camposProducto = (b) => [
    texto(b.nombre, 'Escribe el nombre del producto.'),
    nulo(b.categoria_producto) ?? 'SIN CATEGORIA',
    nulo(b.precio_venta), nulo(b.costo), nulo(b.referencia_interna), nulo(b.unidad_medida),
    nulo(b.archivo_imagen), nulo(b.imagen_url),
  ];

  r.post('/productos', async (req, res) => {
    const { rows } = await consulta(
      `INSERT INTO productos (nombre, categoria_producto, precio_venta, costo, referencia_interna, unidad_medida, archivo_imagen, imagen_url, origen)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'local') RETURNING *`,
      camposProducto(req.body ?? {}),
    );
    await bitacora(req, 'crear', 'productos', rows[0].id, rows[0].nombre);
    res.status(201).json(filaProducto(rows[0]));
  });

  r.put('/productos/:id', async (req, res) => {
    exigirRol(req.usuario, 'editar productos', 'encargado', 'vendedor');
    const { rows } = await consulta(
      `UPDATE productos SET nombre=$2, categoria_producto=$3, precio_venta=$4, costo=$5, referencia_interna=$6,
         unidad_medida=$7, archivo_imagen=$8, imagen_url=$9, modificado=TRUE,
         actualizado_en = now() AT TIME ZONE 'America/Lima'
       WHERE id=$1 AND NOT eliminado RETURNING *`,
      [entero(req.params.id), ...camposProducto(req.body ?? {})],
    );
    if (rows.length === 0) throw falla(404, 'No existe ese producto.');
    await bitacora(req, 'editar', 'productos', rows[0].id, rows[0].nombre);
    res.json(filaProducto(rows[0]));
  });

  r.delete('/productos/:id', async (req, res) => {
    exigirRol(req.usuario, 'eliminar productos', 'encargado', 'vendedor');
    const id = entero(req.params.id);
    // Los agregados desde la app se borran; los del catálogo se marcan como
    // eliminados (para que no vuelvan al actualizar el catálogo).
    await consulta("DELETE FROM productos WHERE id=$1 AND origen='local'", [id]);
    await consulta("UPDATE productos SET eliminado=TRUE, modificado=TRUE WHERE id=$1 AND origen<>'local'", [id]);
    await bitacora(req, 'eliminar', 'productos', id);
    res.json({ ok: true });
  });

  // -------------------------------------------------------------------------
  // Cotizaciones
  // -------------------------------------------------------------------------
  r.get('/cotizaciones', async (_req, res) => {
    const { rows } = await consulta('SELECT * FROM cotizaciones ORDER BY fecha DESC');
    res.json(rows.map(filaCotizacion));
  });

  const camposCotizacion = (b) => [
    String(b.cliente ?? ''), nulo(b.ruc_dni), nulo(b.telefono), nulo(b.vendedor), nulo(b.banco), nulo(b.moneda),
    nulo(b.nro_cuenta), nulo(b.cci), b.fecha, Number(b.total ?? 0), String(b.archivo_pdf ?? ''),
    JSON.stringify(jsonDeEntrada(b.items_json)),
  ];

  r.post('/cotizaciones', async (req, res) => {
    const b = req.body ?? {};
    if (!/^S\d{5,}$/.test(String(b.numero ?? ''))) throw falla(400, 'El número de cotización no es válido.');
    if (!b.fecha) throw falla(400, 'Falta la fecha de la cotización.');
    const { rows } = await consulta(
      `INSERT INTO cotizaciones (numero, cliente, ruc_dni, telefono, vendedor, banco, moneda, nro_cuenta, cci, fecha, total,
         archivo_pdf, items_json, creado_por, actualizado_por)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING *`,
      [b.numero, ...camposCotizacion(b), req.usuario.id, req.usuario.nombre],
    );
    await bitacora(req, 'crear', 'cotizaciones', rows[0].id, `${rows[0].numero} · ${rows[0].cliente}`);
    res.status(201).json(filaCotizacion(rows[0]));
  });

  r.put('/cotizaciones/:id', async (req, res) => {
    validarCambioCotizacion(req);
    const b = req.body ?? {};
    const { rows } = await consulta(
      `UPDATE cotizaciones SET cliente=$3, ruc_dni=$4, telefono=$5, vendedor=$6, banco=$7, moneda=$8, nro_cuenta=$9, cci=$10,
         fecha=$11, total=$12, archivo_pdf=$13, items_json=$14, version=version+1,
         actualizado_en = now() AT TIME ZONE 'America/Lima', actualizado_por=$15
       WHERE id=$1 AND version=$2 RETURNING *`,
      [entero(req.params.id), Number(b.version), ...camposCotizacion(b), req.usuario.nombre],
    );
    if (rows.length === 0) {
      if ((await consulta('SELECT 1 FROM cotizaciones WHERE id=$1', [req.params.id])).rowCount === 0) throw falla(404, 'No existe esa cotización.');
      throw conflicto();
    }
    await bitacora(req, 'editar', 'cotizaciones', rows[0].id, `${rows[0].numero} editada · total S/ ${rows[0].total}`);
    res.json(filaCotizacion(rows[0]));
  });

  r.delete('/cotizaciones/:id', async (req, res) => {
    exigirRol(req.usuario, 'eliminar cotizaciones');
    const id = entero(req.params.id);
    await consulta('DELETE FROM cotizaciones WHERE id=$1', [id]);
    await bitacora(req, 'eliminar', 'cotizaciones', id);
    res.json({ ok: true });
  });

  // -------------------------------------------------------------------------
  // Requerimientos
  // -------------------------------------------------------------------------
  r.get('/requerimientos', async (_req, res) => {
    const { rows } = await consulta('SELECT * FROM requerimientos ORDER BY fecha_creacion DESC');
    res.json(rows.map(filaRequerimiento));
  });

  r.post('/requerimientos', async (req, res) => {
    const b = req.body ?? {};
    if (!/^REQ-\d{4,}$/.test(String(b.numero ?? ''))) throw falla(400, 'El número del requerimiento no es válido.');
    const { rows } = await consulta(
      `INSERT INTO requerimientos (numero, obra, solicitante, urgente, estado, fecha_creacion, observaciones, categorias_json, creado_por, actualizado_por)
       VALUES ($1,$2,$3,$4,'pendiente',$5,$6,$7,$8,$9) RETURNING *`,
      [
        b.numero, texto(b.obra, 'Escribe la obra.'), texto(b.solicitante, 'Escribe quién solicita.'), Boolean(b.urgente),
        b.fecha_creacion, nulo(b.observaciones), JSON.stringify(jsonDeEntrada(b.categorias_json)), req.usuario.id, req.usuario.nombre,
      ],
    );
    await bitacora(req, 'crear', 'requerimientos', rows[0].id, `${rows[0].numero} · ${rows[0].obra}`);
    res.status(201).json(filaRequerimiento(rows[0]));
  });

  r.put('/requerimientos/:id', async (req, res) => {
    const b = req.body ?? {};
    const id = entero(req.params.id);
    const salida = await enTransaccion(async (c) => {
      const previo = (await c.query('SELECT * FROM requerimientos WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!previo) throw falla(404, 'No existe ese requerimiento.');
      if (previo.version !== Number(b.version)) throw conflicto();
      const nuevo = {
        ...previo,
        obra: texto(b.obra, 'Escribe la obra.'), solicitante: texto(b.solicitante, 'Escribe quién solicita.'),
        urgente: Boolean(b.urgente), estado: String(b.estado ?? previo.estado),
        fecha_aprobacion: nulo(b.fecha_aprobacion), aprobado_por: nulo(b.aprobado_por),
        fecha_listo: nulo(b.fecha_listo), alistado_por: nulo(b.alistado_por),
        fecha_entrega: nulo(b.fecha_entrega), recibido_por: nulo(b.recibido_por),
        observaciones: nulo(b.observaciones), categorias_json: jsonDeEntrada(b.categorias_json),
      };
      validarCambioRequerimiento(req, previo, nuevo);
      const { rows } = await c.query(
        `UPDATE requerimientos SET obra=$2, solicitante=$3, urgente=$4, estado=$5, fecha_aprobacion=$6, aprobado_por=$7,
           fecha_listo=$8, alistado_por=$9, fecha_entrega=$10, recibido_por=$11, observaciones=$12, categorias_json=$13,
           version=version+1, actualizado_en = now() AT TIME ZONE 'America/Lima', actualizado_por=$14
         WHERE id=$1 RETURNING *`,
        [
          id, nuevo.obra, nuevo.solicitante, nuevo.urgente, nuevo.estado, nuevo.fecha_aprobacion, nuevo.aprobado_por,
          nuevo.fecha_listo, nuevo.alistado_por, nuevo.fecha_entrega, nuevo.recibido_por, nuevo.observaciones,
          JSON.stringify(nuevo.categorias_json), req.usuario.nombre,
        ],
      );
      return { fila: rows[0], previo };
    });
    const { fila, previo } = salida;
    const detalle = previo.estado !== fila.estado ? `${fila.numero}: ${previo.estado} → ${fila.estado}` : `${fila.numero} actualizado`;
    await bitacora(req, 'editar', 'requerimientos', fila.id, detalle);
    res.json(filaRequerimiento(fila));
  });

  r.delete('/requerimientos/:id', async (req, res) => {
    exigirRol(req.usuario, 'eliminar requerimientos');
    const id = entero(req.params.id);
    await consulta('DELETE FROM requerimientos WHERE id=$1', [id]);
    await bitacora(req, 'eliminar', 'requerimientos', id);
    res.json({ ok: true });
  });

  // -------------------------------------------------------------------------
  // Salidas de herramientas
  // -------------------------------------------------------------------------
  r.get('/herramientas', async (_req, res) => {
    const { rows } = await consulta('SELECT * FROM checklists_herramientas ORDER BY fecha_salida DESC');
    res.json(rows.map(filaHerramientas));
  });

  r.post('/herramientas', async (req, res) => {
    const b = req.body ?? {};
    if (!/^HER-\d{4,}$/.test(String(b.numero ?? ''))) throw falla(400, 'El número de la salida no es válido.');
    const { rows } = await consulta(
      `INSERT INTO checklists_herramientas (numero, obra, responsable, maleta, estado, fecha_salida, observaciones, categorias_json, creado_por, actualizado_por)
       VALUES ($1,$2,$3,$4,'registrado',$5,$6,$7,$8,$9) RETURNING *`,
      [
        b.numero, texto(b.obra, 'Escribe la obra.'), texto(b.responsable, 'Escribe quién se lleva las herramientas.'),
        nulo(b.maleta), b.fecha_salida, nulo(b.observaciones), JSON.stringify(jsonDeEntrada(b.categorias_json)),
        req.usuario.id, req.usuario.nombre,
      ],
    );
    await bitacora(req, 'crear', 'checklists_herramientas', rows[0].id, `${rows[0].numero} · ${rows[0].obra}`);
    res.status(201).json(filaHerramientas(rows[0]));
  });

  r.put('/herramientas/:id', async (req, res) => {
    const b = req.body ?? {};
    const id = entero(req.params.id);
    const salida = await enTransaccion(async (c) => {
      const previo = (await c.query('SELECT * FROM checklists_herramientas WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!previo) throw falla(404, 'No existe esa salida de herramientas.');
      if (previo.version !== Number(b.version)) throw conflicto();
      const nuevo = {
        ...previo,
        obra: texto(b.obra, 'Escribe la obra.'), responsable: texto(b.responsable, 'Escribe el responsable.'),
        maleta: nulo(b.maleta), estado: String(b.estado ?? previo.estado),
        fecha_confirmacion_salida: nulo(b.fecha_confirmacion_salida), salida_confirmada_por: nulo(b.salida_confirmada_por),
        fecha_devolucion: nulo(b.fecha_devolucion), encargado: nulo(b.encargado),
        observaciones: nulo(b.observaciones), observaciones_devolucion: nulo(b.observaciones_devolucion),
        categorias_json: jsonDeEntrada(b.categorias_json),
      };
      validarCambioHerramientas(req, previo, nuevo);
      const { rows } = await c.query(
        `UPDATE checklists_herramientas SET obra=$2, responsable=$3, maleta=$4, estado=$5, fecha_confirmacion_salida=$6,
           salida_confirmada_por=$7, fecha_devolucion=$8, encargado=$9, observaciones=$10, observaciones_devolucion=$11,
           categorias_json=$12, version=version+1, actualizado_en = now() AT TIME ZONE 'America/Lima', actualizado_por=$13
         WHERE id=$1 RETURNING *`,
        [
          id, nuevo.obra, nuevo.responsable, nuevo.maleta, nuevo.estado, nuevo.fecha_confirmacion_salida,
          nuevo.salida_confirmada_por, nuevo.fecha_devolucion, nuevo.encargado, nuevo.observaciones,
          nuevo.observaciones_devolucion, JSON.stringify(nuevo.categorias_json), req.usuario.nombre,
        ],
      );
      return { fila: rows[0], previo };
    });
    const { fila, previo } = salida;
    const detalle = previo.estado !== fila.estado ? `${fila.numero}: ${previo.estado} → ${fila.estado}` : `${fila.numero} actualizado`;
    await bitacora(req, 'editar', 'checklists_herramientas', fila.id, detalle);
    res.json(filaHerramientas(fila));
  });

  r.delete('/herramientas/:id', async (req, res) => {
    exigirRol(req.usuario, 'eliminar salidas de herramientas');
    const id = entero(req.params.id);
    await consulta('DELETE FROM checklists_herramientas WHERE id=$1', [id]);
    await bitacora(req, 'eliminar', 'checklists_herramientas', id);
    res.json({ ok: true });
  });

  // -------------------------------------------------------------------------
  // Listas del checklist (materiales y herramientas)
  // -------------------------------------------------------------------------
  const tipoLista = (v) => {
    if (v !== 'materiales' && v !== 'herramientas') throw falla(400, 'Tipo de lista no válido.');
    return v;
  };
  const GESTION = ['encargado', 'almacen'];

  /** Orden al final de la categoría, o una categoría nueva al final de la lista. */
  async function ordenAlFinal(tipo, categoria) {
    const enCategoria = (await consulta('SELECT MAX(orden) AS m FROM checklist_catalogo WHERE tipo=$1 AND categoria=$2', [tipo, categoria])).rows[0].m;
    if (enCategoria !== null) return enCategoria + 1;
    const total = (await consulta('SELECT MAX(orden) AS m FROM checklist_catalogo WHERE tipo=$1', [tipo])).rows[0].m ?? 0;
    return (Math.floor(total / 1000) + 1) * 1000;
  }

  r.get('/checklist-catalogo', async (req, res) => {
    const { rows } = await consulta('SELECT * FROM checklist_catalogo WHERE tipo=$1 ORDER BY orden, id', [tipoLista(req.query.tipo)]);
    res.json(rows.map(filaCatalogo));
  });

  r.post('/checklist-catalogo', async (req, res) => {
    const b = req.body ?? {};
    const tipo = tipoLista(b.tipo);
    const categoria = texto(b.categoria, 'Falta la categoría.');
    const orden = b.orden ?? (await ordenAlFinal(tipo, categoria));
    const { rows } = await consulta(
      `INSERT INTO checklist_catalogo (tipo, categoria, nombre, unidad, precio, orden, base)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [tipo, categoria, texto(b.nombre, 'Escribe el nombre.'), nulo(b.unidad), nulo(b.precio), orden, b.base === 1 || b.base === true],
    );
    res.status(201).json(filaCatalogo(rows[0]));
  });

  r.put('/checklist-catalogo/:id', async (req, res) => {
    exigirRol(req.usuario, 'editar las listas', ...GESTION);
    const b = req.body ?? {};
    const id = entero(req.params.id);
    const previo = (await consulta('SELECT * FROM checklist_catalogo WHERE id=$1', [id])).rows[0];
    if (!previo) throw falla(404, 'No existe ese ítem.');
    const categoria = texto(b.categoria, 'Falta la categoría.');
    const orden = categoria !== previo.categoria ? await ordenAlFinal(previo.tipo, categoria) : previo.orden;
    const { rows } = await consulta(
      'UPDATE checklist_catalogo SET categoria=$2, nombre=$3, unidad=$4, precio=$5, orden=$6 WHERE id=$1 RETURNING *',
      [id, categoria, texto(b.nombre, 'Escribe el nombre.'), nulo(b.unidad), nulo(b.precio), orden],
    );
    res.json(filaCatalogo(rows[0]));
  });

  r.post('/checklist-catalogo/renombrar-categoria', async (req, res) => {
    exigirRol(req.usuario, 'editar las listas', ...GESTION);
    const b = req.body ?? {};
    await consulta('UPDATE checklist_catalogo SET categoria=$3 WHERE tipo=$1 AND categoria=$2', [
      tipoLista(b.tipo), texto(b.anterior, 'Falta la categoría.'), texto(b.nueva, 'Escribe el nombre nuevo.'),
    ]);
    res.json({ ok: true });
  });

  r.delete('/checklist-catalogo/:id', async (req, res) => {
    exigirRol(req.usuario, 'editar las listas', ...GESTION);
    await consulta('DELETE FROM checklist_catalogo WHERE id=$1', [entero(req.params.id)]);
    res.json({ ok: true });
  });

  // -------------------------------------------------------------------------
  // Maletas
  // -------------------------------------------------------------------------
  r.get('/maletas', async (_req, res) => {
    const maletas = (await consulta('SELECT * FROM maletas ORDER BY orden, id')).rows;
    const items = (await consulta('SELECT * FROM maleta_items ORDER BY orden, id')).rows;
    res.json(
      maletas.map((m) => {
        const niveles = new Map();
        for (const i of items.filter((x) => x.maleta_id === m.id)) {
          if (!niveles.has(i.nivel)) niveles.set(i.nivel, []);
          niveles.get(i.nivel).push({ id: i.id, nombre: i.nombre, imagen: i.imagen });
        }
        return { id: m.id, nombre: m.nombre, categorias: [...niveles].map(([nombre, its]) => ({ nombre, items: its })) };
      }),
    );
  });

  async function ordenItemMaleta(maletaId, nivel) {
    const enNivel = (await consulta('SELECT MAX(orden) AS m FROM maleta_items WHERE maleta_id=$1 AND nivel=$2', [maletaId, nivel])).rows[0].m;
    if (enNivel !== null) return enNivel + 1;
    const total = (await consulta('SELECT MAX(orden) AS m FROM maleta_items WHERE maleta_id=$1', [maletaId])).rows[0].m ?? -1;
    return (Math.floor(total / 1000) + 1) * 1000;
  }

  r.post('/maletas', async (req, res) => {
    exigirRol(req.usuario, 'crear maletas', ...GESTION);
    const max = (await consulta('SELECT COALESCE(MAX(orden), -1) AS m FROM maletas')).rows[0].m;
    const { rows } = await consulta('INSERT INTO maletas (nombre, orden) VALUES ($1,$2) RETURNING id', [texto(req.body?.nombre, 'Escribe el nombre de la maleta.'), max + 1]);
    res.status(201).json({ id: rows[0].id });
  });
  r.put('/maletas/:id', async (req, res) => {
    exigirRol(req.usuario, 'editar maletas', ...GESTION);
    await consulta('UPDATE maletas SET nombre=$2 WHERE id=$1', [entero(req.params.id), texto(req.body?.nombre, 'Escribe el nombre de la maleta.')]);
    res.json({ ok: true });
  });
  r.delete('/maletas/:id', async (req, res) => {
    exigirRol(req.usuario, 'eliminar maletas', ...GESTION);
    await consulta('DELETE FROM maletas WHERE id=$1', [entero(req.params.id)]);
    res.json({ ok: true });
  });
  r.post('/maletas/:id/items', async (req, res) => {
    exigirRol(req.usuario, 'editar maletas', ...GESTION);
    const b = req.body ?? {};
    const id = entero(req.params.id);
    const nivel = texto(b.nivel, 'Falta el nivel.');
    const { rows } = await consulta(
      'INSERT INTO maleta_items (maleta_id, nivel, nombre, imagen, orden) VALUES ($1,$2,$3,$4,$5) RETURNING id',
      [id, nivel, texto(b.nombre, 'Escribe el nombre de la herramienta.'), nulo(b.imagen), await ordenItemMaleta(id, nivel)],
    );
    res.status(201).json({ id: rows[0].id });
  });
  r.put('/maleta-items/:id', async (req, res) => {
    exigirRol(req.usuario, 'editar maletas', ...GESTION);
    const b = req.body ?? {};
    const id = entero(req.params.id);
    const previo = (await consulta('SELECT * FROM maleta_items WHERE id=$1', [id])).rows[0];
    if (!previo) throw falla(404, 'No existe esa herramienta.');
    const nivel = texto(b.nivel, 'Falta el nivel.');
    const orden = nivel !== previo.nivel ? await ordenItemMaleta(previo.maleta_id, nivel) : previo.orden;
    await consulta('UPDATE maleta_items SET nivel=$2, nombre=$3, imagen=$4, orden=$5 WHERE id=$1', [
      id, nivel, texto(b.nombre, 'Escribe el nombre de la herramienta.'), nulo(b.imagen), orden,
    ]);
    res.json({ ok: true });
  });
  r.delete('/maleta-items/:id', async (req, res) => {
    exigirRol(req.usuario, 'editar maletas', ...GESTION);
    await consulta('DELETE FROM maleta_items WHERE id=$1', [entero(req.params.id)]);
    res.json({ ok: true });
  });
  r.post('/maletas/:id/niveles/renombrar', async (req, res) => {
    exigirRol(req.usuario, 'editar maletas', ...GESTION);
    const b = req.body ?? {};
    await consulta('UPDATE maleta_items SET nivel=$3 WHERE maleta_id=$1 AND nivel=$2', [
      entero(req.params.id), texto(b.anterior, 'Falta el nivel.'), texto(b.nuevo, 'Escribe el nombre nuevo.'),
    ]);
    res.json({ ok: true });
  });

  // -------------------------------------------------------------------------
  // Fotos (productos, herramientas): se guardan como archivos
  // -------------------------------------------------------------------------
  const FIRMAS = { jpg: [0xff, 0xd8, 0xff], png: [0x89, 0x50, 0x4e, 0x47], webp: [0x52, 0x49, 0x46, 0x46] };
  r.post('/subidas', express.raw({ type: () => true, limit: '8mb' }), async (req, res) => {
    const ext = String(req.query.ext ?? 'jpg').toLowerCase().replace('jpeg', 'jpg');
    const firma = FIRMAS[ext];
    const bytes = req.body;
    if (!firma || !Buffer.isBuffer(bytes) || bytes.length < 16 || !firma.every((b, i) => bytes[i] === b)) {
      throw falla(400, 'La foto debe ser una imagen JPG, PNG o WEBP.');
    }
    mkdirSync(carpetaSubidas, { recursive: true });
    const nombre = `${randomBytes(12).toString('hex')}.${ext}`;
    writeFileSync(join(carpetaSubidas, nombre), bytes);
    res.status(201).json({ ruta: `/uploads/${nombre}` });
  });

  // -------------------------------------------------------------------------
  // Resumen para la vista general
  // -------------------------------------------------------------------------
  r.get('/resumen', async (_req, res) => {
    const contar = async (tabla, columna) =>
      Object.fromEntries((await consulta(`SELECT ${columna} AS k, COUNT(*)::int AS n FROM ${tabla} GROUP BY 1`)).rows.map((f) => [f.k, f.n]));
    const cot = (
      await consulta(
        `SELECT COUNT(*)::int AS total,
                COUNT(*) FILTER (WHERE date_trunc('month', fecha) = date_trunc('month', now() AT TIME ZONE 'America/Lima'))::int AS este_mes,
                COALESCE(SUM(total) FILTER (WHERE date_trunc('month', fecha) = date_trunc('month', now() AT TIME ZONE 'America/Lima')), 0) AS monto_mes
         FROM cotizaciones`,
      )
    ).rows[0];
    const urgentes = (await consulta("SELECT COUNT(*)::int AS n FROM requerimientos WHERE urgente AND estado <> 'entregado'")).rows[0].n;
    res.json({
      requerimientos: await contar('requerimientos', 'estado'),
      urgentes,
      herramientas: await contar('checklists_herramientas', 'estado'),
      cotizaciones: cot,
    });
  });

  r.get('/bitacora', async (req, res) => {
    exigirRol(req.usuario, 'ver la bitácora', 'encargado');
    const { rows } = await consulta('SELECT * FROM bitacora ORDER BY id DESC LIMIT 200');
    res.json(rows);
  });

  return r;
}
