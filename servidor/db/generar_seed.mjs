// Genera db/seed.sql a partir de los datos que ya trae la app (assets/):
// los 800 productos, las listas del checklist con sus precios y las maletas.
// Uso (desde la raíz del repositorio):  node servidor/db/generar_seed.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const leer = (ruta) => JSON.parse(readFileSync(join(raiz, 'assets', ruta), 'utf8'));
const q = (v) => (v === null || v === undefined || v === '' ? 'NULL' : `'${String(v).replaceAll("'", "''")}'`);
const n = (v) => (v === null || v === undefined ? 'NULL' : Number(v));
const dart = (v) => (v === null || v === undefined ? '' : Number.isInteger(v) ? `${v}.0` : `${v}`);

const sal = [];
sal.push('-- Datos iniciales (generado por generar_seed.mjs; no editar a mano).');
sal.push('SET client_encoding = \'UTF8\';');

// Productos: la identidad de cada uno (clave_catalogo) igual que en la app.
const productos = leer('productos_seed.json');
sal.push('INSERT INTO productos (nombre, categoria_producto, precio_venta, costo, referencia_interna, unidad_medida, archivo_imagen, origen, clave_catalogo) VALUES');
sal.push(
  productos
    .map((p) => {
      const clave = `${String(p.nombre ?? '').trim().toLowerCase()}|${p.referencia_interna ?? ''}|${p.categoria_producto ?? ''}|${dart(p.costo)}|${dart(p.precio_venta)}`;
      return `  (${q(p.nombre)}, ${q(p.categoria_producto ?? 'SIN CATEGORIA')}, ${n(p.precio_venta)}, ${n(p.costo)}, ${q(p.referencia_interna)}, ${q(p.unidad_medida)}, ${q(p.archivo_imagen)}, 'catalogo', ${q(clave)})`;
    })
    .join(',\n') + ';',
);

// Listas del checklist: la de HERRAMIENTAS es de herramientas, el resto materiales.
const lista = leer('checklist_seed.json');
const precios = Object.fromEntries(Object.entries(leer('precios_materiales.json')).map(([k, v]) => [k.toLowerCase(), v]));
const filas = [];
for (const c of lista) {
  const tipo = c.categoria.toUpperCase().includes('HERRAMIENTA') ? 'herramientas' : 'materiales';
  c.items.forEach((nombre, i) => {
    const precio = tipo === 'materiales' ? precios[nombre.toLowerCase()] : null;
    filas.push(`  (${q(tipo)}, ${q(c.categoria)}, ${q(nombre)}, ${n(precio)}, ${c.orden * 1000 + i}, TRUE)`);
  });
}
sal.push('INSERT INTO checklist_catalogo (tipo, categoria, nombre, precio, orden, base) VALUES');
sal.push(filas.join(',\n') + ';');

// Maletas con sus herramientas por nivel.
const maletas = leer('maletas/maletas.json');
maletas.forEach((m, idx) => {
  sal.push(`INSERT INTO maletas (nombre, orden) VALUES (${q(m.nombre)}, ${idx});`);
  const items = [];
  let orden = 0;
  for (const c of m.categorias) {
    for (const i of c.items) {
      const foto = i.imagen ? `assets/maletas/${m.carpeta}/${i.imagen}` : null;
      items.push(`  ((SELECT max(id) FROM maletas), ${q(c.nombre)}, ${q(i.nombre)}, ${q(foto)}, ${orden++})`);
    }
  }
  sal.push('INSERT INTO maleta_items (maleta_id, nivel, nombre, imagen, orden) VALUES');
  sal.push(items.join(',\n') + ';');
});

writeFileSync(join(raiz, 'servidor', 'db', 'seed.sql'), sal.join('\n') + '\n');
console.log(`seed.sql: ${productos.length} productos, ${filas.length} ítems de lista, ${maletas.length} maletas`);
