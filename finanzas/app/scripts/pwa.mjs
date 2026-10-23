/**
 * Convierte la exportación web de Expo en una PWA instalable (siempre en línea, sin caché):
 *   1. genera dist/sw.js (solo limpia cachés viejas; no guarda nada),
 *   2. agrega al index.html el manifest, los metadatos para instalarla y el registro del service worker.
 * Uso: node scripts/pwa.mjs dist
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dist = path.resolve(process.argv[2] || "dist");
const aqui = path.dirname(fileURLToPath(import.meta.url));
if (!fs.existsSync(path.join(dist, "index.html"))) throw new Error(`No hay ${dist}/index.html: corre antes "expo export -p web".`);

for (const f of ["manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png", "icons/icon-maskable-512.png", "icons/apple-touch-icon.png"])
  if (!fs.existsSync(path.join(dist, f))) throw new Error(`Falta ${f} en ${dist}: debe estar en app/public/.`);

const SALTAR = new Set(["sw.js", "metadata.json"]);
const archivos = [];
(function recorrer(dir) {
  for (const n of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, n.name);
    if (n.isDirectory()) recorrer(p);
    else {
      const rel = path.relative(dist, p).split(path.sep).join("/");
      if (!SALTAR.has(rel) && !rel.endsWith(".map")) archivos.push(rel);
    }
  }
})(dist);
archivos.sort();

const hash = createHash("sha1");
for (const rel of archivos) hash.update(rel).update(fs.readFileSync(path.join(dist, rel)));
const version = hash.digest("hex").slice(0, 12);

const sw = fs.readFileSync(path.join(aqui, "sw.template.js"), "utf8").replaceAll("__VERSION__", () => version);
if (/__VERSION__/.test(sw)) throw new Error("sw.js quedó con marcadores sin reemplazar.");
fs.writeFileSync(path.join(dist, "sw.js"), sw);

const REGISTRO = `<script>
if ("serviceWorker" in navigator) {
  window.addEventListener("load", function () {
    navigator.serviceWorker.register("/sw.js").catch(function () {});
  });
}
</script>`;

const META = `<link rel="manifest" href="/manifest.webmanifest" />
    <meta name="theme-color" content="#0E7490" />
    <meta name="mobile-web-app-capable" content="yes" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <meta name="apple-mobile-web-app-title" content="ICR Finanzas" />
    <meta name="apple-mobile-web-app-status-bar-style" content="default" />
    <link rel="apple-touch-icon" href="/icons/apple-touch-icon.png" />`;

const ruta = path.join(dist, "index.html");
let html = fs.readFileSync(ruta, "utf8");
if (html.includes("manifest.webmanifest")) throw new Error("index.html ya tiene el manifest: no lo corras dos veces sobre la misma carpeta.");
const antes = html;
html = html.replace('<html lang="en">', '<html lang="es">').replace("</head>", `  ${META}\n  </head>`).replace("</body>", `  ${REGISTRO}\n</body>`);
if (html === antes || !html.includes("manifest.webmanifest") || !html.includes("serviceWorker")) throw new Error("No se pudo parchear index.html (¿cambió su estructura?).");
fs.writeFileSync(ruta, html);

console.log(`PWA lista (en línea, sin caché): ${archivos.length} archivos · versión ${version}`);
