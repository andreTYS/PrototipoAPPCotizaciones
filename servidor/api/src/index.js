import { existsSync } from 'node:fs';
import express from 'express';
import { ErrorApi } from './errores.js';
import { prepararBase } from './db.js';
import { carpetaSubidas, crearRutas } from './rutas.js';

export function crearApp() {
  const app = express();
  app.set('trust proxy', true);
  app.disable('x-powered-by');
  app.use(express.json({ limit: '5mb' }));

  app.use('/api', crearRutas());
  app.use('/uploads', express.static(carpetaSubidas, { maxAge: '7d', immutable: true }));

  // La vista general (portal) la puede servir la misma API.
  const portal = process.env.PORTAL_DIR;
  if (portal && existsSync(portal)) app.use(express.static(portal));

  app.use('/api', (_req, res) => res.status(404).json({ error: 'No existe esa dirección.' }));

  // eslint-disable-next-line no-unused-vars
  app.use((e, _req, res, _next) => {
    if (e instanceof ErrorApi) return res.status(e.codigo).json({ error: e.message });
    if (e?.type === 'entity.parse.failed') return res.status(400).json({ error: 'El pedido no tiene un formato válido.' });
    if (e?.type === 'entity.too.large') return res.status(413).json({ error: 'El archivo es demasiado grande.' });
    if (e?.code === '23505') return res.status(409).json({ error: 'Ese registro ya existe.' });
    if (e?.code === '22007' || e?.code === '22008' || e?.code === '22P02') return res.status(400).json({ error: 'Hay un dato con formato no válido.' });
    console.error(e);
    res.status(500).json({ error: 'El servidor tuvo un problema. Intenta de nuevo.' });
  });
  return app;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await prepararBase();
  const puerto = Number(process.env.PORT || 3000);
  crearApp().listen(puerto, () => console.log(`API del Cotizador ICR escuchando en el puerto ${puerto}`));
}
