# Cotizador ICR (Flutter)

App para el equipo de ventas de Inversiones ICR: checklist de productos
por categoría para armar una cotización y generar/compartir un PDF.
Funciona **offline** desde el primer momento (trae los ~830 productos
empaquetados) y se conecta al **ERP real (ICR-LOGISTICA)** para traer el
catálogo actualizado y enviar cada cotización como un Lead del CRM.

Corre como app nativa (Android/iOS) **y** como PWA instalable desde el
navegador — mismo código, misma base de datos local en ambos casos.

## Cómo funciona (arquitectura)

- **Primer arranque:** no hay red de por medio. La app lee
  `assets/productos_seed.json` (catálogo de referencia) y lo guarda en una
  base SQLite local — en Android/iOS es la base nativa; en la build web
  (PWA) es la misma base SQLite pero corriendo sobre `sqlite3` compilado a
  WebAssembly, persistida en el IndexedDB del navegador (ver
  `sqflite_common_ffi_web` en `pubspec.yaml` y el registro del factory en
  `lib/main.dart`).
- **Uso normal (armar checklist, generar PDF):** todo sale de esa base
  local. Cero llamadas a internet — el PDF se genera y se comparte
  igual sin conexión.
- **Botón "Sincronizar"** (pantalla *Conexión con el ERP*): se conecta al
  ERP real de Inversiones ICR (mismo mecanismo que usa la tienda pública
  ICR-TIENDA: `GET /inventory/products` + `/inventory/stock`, paginado y
  autenticado con un token de servicio), trae el catálogo completo y
  reemplaza lo que había en la base local.
- **Al generar una cotización:** además del PDF (que siempre se genera,
  con o sin ERP configurado), si el ERP está configurado la app intenta
  crear un **Lead real en el CRM** (`POST /crm/leads`) con el cliente, el
  RUC/DNI y el detalle de productos — best-effort: si falla (sin señal,
  token vencido), el PDF ya se generó y compartió igual, no se pierde
  nada.
- El único archivo que habla con el ERP es `lib/services/api_service.dart`
  — el resto de la app (pantallas, PDF, checklist, base local) no sabe de
  dónde vino el catálogo.

## 1. Requisitos

- Flutter SDK 3.35+ (`flutter --version` debe funcionar)
- Un token de servicio del ERP (*Administración → Tokens de servicio* en
  ICR-LOGISTICA, actuando como un usuario con rol `VENTAS`) — sin esto la
  app sigue funcionando 100% con el catálogo offline empaquetado, solo no
  podrá sincronizar ni enviar cotizaciones al CRM.

## 2. Correr la app en desarrollo

```bash
flutter pub get
flutter run                 # elige Android/iOS/Chrome cuando lo pregunte
```

Para servir localmente una build de producción de la PWA:

```bash
flutter build web --release --no-web-resources-cdn
cd build/web && python3 -m http.server 8080   # o cualquier servidor estático
```

`--no-web-resources-cdn` hace que la build sirva su propio CanvasKit en
vez de bajarlo de Google en cada carga — importante para que la PWA
funcione también con conexión limitada o filtrada en el celular del
vendedor (mismo motivo por el que la fuente Roboto también va empaquetada
localmente en `assets/fonts/`, en vez de pedirse a Google Fonts).

## 3. Conectar con el ERP real

1. Genera un token de servicio en el ERP: *Administración → Tokens de
   servicio*, eligiendo actuar como un usuario con rol `VENTAS`.
2. Abre la app → pantalla *Conexión con el ERP* (ícono de refresh arriba).
3. Completa:
   - **URL de la API del ERP**: `https://erp.inversionesicr.com/api`
   - **Token de servicio**: el que generaste en el paso 1
4. Toca **Sincronizar ahora** — trae el catálogo completo (pagina
   automáticamente hasta traer todos los productos, sin quedarse en los
   primeros 500 por el tope de página del ERP).

Desde ese momento, cada cotización generada también se intenta enviar
como Lead al CRM del ERP.

## 4. Build web / PWA (instalable desde el navegador)

```bash
flutter build web --release --no-web-resources-cdn
```

El resultado (`build/web/`) es un sitio estático completo: se puede abrir
con cualquier servidor web, y el navegador (Chrome/Edge en Android,
desktop) ofrece **"Instalar app"** automáticamente gracias al
`web/manifest.json` + service worker que genera Flutter. Una vez
instalada se abre en su propia ventana, con ícono propio, igual que una
app nativa — sin pasar por ninguna tienda de aplicaciones.

**Despliegue en el VPS** (mismo patrón que el ERP y la tienda pública,
Docker + Traefik compartido):

```bash
# En el VPS, dentro de la carpeta de este repo, con DOMAIN definido en .env
# (ej. DOMAIN=cotizador.inversionesicr.com)
docker compose up -d --build
```

`Dockerfile.web` compila la app y la sirve con nginx; `docker-compose.yml`
ya trae los labels de Traefik correctos para este VPS (red `n8n_default`,
certResolver `mytlschallenge` — ver el comentario en el propio archivo
sobre por qué no deben ser "traefik_public"/"letsencrypt").

**CI**: `.github/workflows/build_web.yml` compila la build web en cada
push a `main` y la deja como artefacto descargable en la pestaña Actions
(útil para probarla sin tener Flutter instalado localmente).
`.github/workflows/build_apk.yml` sigue generando el `.apk` de Android
igual que antes.

## 5. Habilitar tráfico HTTP local en Android (solo si usas un servidor sin HTTPS)

Si en algún momento pruebas contra un servidor propio sin HTTPS (no el ERP
de producción, que sí tiene HTTPS), Android bloquea ese tráfico por
defecto desde Android 9. Abre `android/app/src/main/AndroidManifest.xml`
y agrega dentro de `<application ...>`:

```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

No es necesario para conectar con `https://erp.inversionesicr.com`.

## 6. Usarla

1. Abre la app — ya vas a ver las categorías con los productos, sin tocar
   nada (catálogo offline empaquetado, o el último sincronizado con el
   ERP).
2. Entra a una categoría, marca los productos del checklist y ajusta
   cantidades con los botones + / -.
3. Toca el botón flotante "Cotización" para revisar lo seleccionado, pon
   el nombre del cliente si quieres, y dale a **Generar y compartir
   PDF** — se abre el menú nativo para compartir por WhatsApp, correo,
   guardar, etc. Si el ERP está configurado, también queda como Lead en
   el CRM.
