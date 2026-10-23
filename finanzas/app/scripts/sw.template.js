/*
 * Service worker de ICR Finanzas (lo genera scripts/pwa.mjs al compilar; versión: __VERSION__).
 *
 * La app trabaja siempre en línea y varias personas la usan a la vez sobre los mismos datos, así que NO guarda nada
 * en caché: todo sale de la red. Este archivo solo existe para que el navegador permita instalarla en el teléfono y
 * para borrar las cachés de versiones anteriores (que sí guardaban la app para usarla sin internet).
 */
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((ks) => Promise.all(ks.filter((k) => k.startsWith("icr-finanzas-")).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

// Sin respondWith: el navegador resuelve la petición normalmente, por la red.
self.addEventListener("fetch", () => {});
