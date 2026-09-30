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
- **Almacén (Requerimientos y Checklist de herramientas):** los ítems del
  checklist son texto libre del Excel semilla, salvo los que se agregan
  "Del catálogo" (buscador de productos) — esos sí traen el SKU real del
  ERP. Solo esos ítems tocan inventario de verdad, usando el sistema de
  reservas/préstamos que ya tiene el ERP (`/inventory/reserve`,
  `/inventory/dispatch_reservation`, `/inventory/return_loan`):
  - Un requerimiento **aprueba** → reserva stock; **entrega** → lo despacha
    (descuenta stock físico real; si el producto es retornable, el ERP
    crea el préstamo).
  - Una salida de herramientas reserva y despacha de una sola vez; su
    **devolución** cierra el préstamo.
  - Igual que el resto de esta app, es **best-effort**: si el ERP no está
    configurado o la llamada falla, el requerimiento/checklist se sigue
    guardando local sin bloquear al usuario — ver `AlmacenState`.
  - El almacén contra el que se reserva se elige una vez en *Conexión con
    el ERP* (desplegable con los almacenes activos del ERP).
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

La app tiene tres pestañas abajo:

- **Cotización** (izquierda): los productos del catálogo (offline
  empaquetado, o el último sincronizado con el ERP real — ver sección 3),
  "Todos" o por categoría. Marca productos, ajusta cantidades y toca
  **Generar cotización** para armar el PDF con el formato de Inversiones
  ICR y completar los datos del cliente/RUC-DNI/teléfono; si el ERP está
  configurado, la cotización también se intenta enviar como Lead al CRM
  (best-effort, sin bloquear el PDF si falla). Arriba están la
  **cotización por voz** (micrófono), el **historial de cotizaciones**
  (reloj: buscar, ver detalle, compartir o eliminar) y **agregar
  producto** (+, con foto, precio, costo, unidad y referencia). Los
  productos agregados a mano se pueden editar o eliminar (⋮).
- **Inicio** (centro): lo que requiere atención — requerimientos urgentes o
  pendientes de aprobación, aprobados que falta entregar y herramientas por
  devolver — más accesos directos a Almacén y Cotización.
- **Almacén** (derecha):
  - **Requerimientos**: se crean con el checklist de siempre (categoría por
    categoría). Estados: *Pendiente aprobación* (llega una notificación al
    celular) → *Aprobado por jefe de obra* (pide el código **1234**) →
    *Entregado*. Cada uno tiene su PDF formal para ver o compartir.
  - **Checklist de herramientas**: se registra la salida (queda *Pendiente
    devolución*) y, cuando un encargado confirma que volvió todo, queda
    *Conforme*. También con su PDF.
  - Con el ícono de lista (arriba) se agregan ítems nuevos a la lista base
    de materiales o de herramientas.

Para traer el catálogo actualizado y sincronizar cotizaciones con el ERP
real de Inversiones ICR, ver la sección **3. Conectar con el ERP real**
más arriba (URL del ERP + token de servicio, sin IPs locales de por
medio).
