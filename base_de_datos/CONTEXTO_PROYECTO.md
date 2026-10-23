# Contexto del proyecto: Cotizador ICR (Inversiones ICR)

Pega este documento al inicio de un chat nuevo. Resume lo que ya existe, cómo está hecho y qué falta. Los archivos adjuntos (SQL y JSON) son los datos reales.

## 1. Qué es
App móvil/PWA en **Flutter 3** para **Inversiones ICR** (empresa de instalaciones eléctricas y fotovoltaicas, Perú). Tiene 3 pestañas:
- **Inicio:** resumen del trabajo, urgentes primero (en rojo).
- **Cotización:** catálogo de ~800 productos (con foto), búsqueda, agregar por voz, generar PDF formal con el formato de Inversiones ICR, historial de cotizaciones.
- **Almacén:** requerimientos de materiales, salidas/entradas de herramientas (por checklist o por maleta), Configuración.

Repositorio: `AdrianAlessandroCalderonBegazo/PrototipoAPPCotizac-n`. Rama de trabajo: `claude/checklist-productos-apk-build-xruncz`. `main` es la versión **offline** (SQLite en el dispositivo). La rama local `claude/pwa-hostinger` tuvo una versión con servidor PHP + MySQL (puede haberse borrado en GitHub).

## 2. Stack
- Flutter, Provider, `sqflite` (base local, **versión de esquema 9**), `pdf` + `printing`, `image_picker`, `path_provider`, `shared_preferences`, notificaciones locales, voz, animaciones Lottie.
- Pruebas con `sqflite_common_ffi` (`test/`: `db_helper_test.dart`, `config_flujos_test.dart`, `edicion_alistado_test.dart`).
- APK por GitHub Actions (`.github/workflows/build_apk.yml`, se dispara con push a `main` o manualmente).

## 3. Funciones ya hechas
- **Cotización:** 800 productos, voz, PDF formal, historial, agregar/editar producto con foto, **editar una cotización con clave** (regenera el PDF).
- **Requerimientos de materiales:** estados `pendiente → aprobado → listo → entregado`.
  - Datos primero (obra y solicitante obligatorios), checklist con **precios por defecto editables** (precios en `assets/precios_materiales.json`), código de jefe de obra para aprobar, notificación.
  - **Alistado por material con avance compartido:** cada ítem guarda quién lo alistó y cuándo. Una persona alista parte y guarda, otra continúa. Al alistar todo pasa solo a `listo`.
- **Salida de herramientas:** estados `registrado → pendiente → conforme`. Por checklist o por **maleta** (3 maletas hechas desde los Word de la empresa, 72 herramientas). Se confirma salida y devolución **herramienta por herramienta** (columnas SALIDA/ENTRADA del formato en papel).
- **Edición con clave `1234`** de requerimientos, salidas y cotizaciones: agregar un producto, material o herramienta olvidado o nuevo. Reglas:
  - Un requerimiento `listo`/`entregado` al que se le agrega algo vuelve a `aprobado`, y lo ya alistado se conserva.
  - Una salida `conforme` a la que se agrega una herramienta vuelve a `pendiente` y la nueva se da por salida.
  - Cada edición se anota en las observaciones (`[Editado dd/MM HH:mm] ...`).
  - Un material nuevo puede guardarse también en la lista base.
- **Configuración:** productos, maletas, listas del checklist (materiales con precio y herramientas) y historiales, todo editable.
- PDFs formales de requerimiento y de herramientas.

Clave de edición: constante `claveEdicion = '1234'` en `lib/utils/seguridad.dart`. En el servidor debe guardarse cifrada (bcrypt) en `configuracion.clave_edicion`.

## 4. Estructura del código (`lib/`)
- `models/`: producto, cotizacion_guardada, requerimiento, checklist_herramientas, checklist_categoria (incluye `ChecklistItemEntry` con `alistado`, `alistadoPor`, `fechaAlistado`, `agregadoDespues`, `salio`, `volvio`), maleta, item_catalogo_checklist, datos_almacen.
- `services/`: `db_helper.dart` (SQLite), `pdf_service.dart` (`generar`, `regenerarCotizacion`), `api_service.dart`, `notificaciones_service.dart`, `buscador_voz.dart`.
- `state/`: `almacen_state.dart` (reglas de estados, alistado, edición), `cotizacion_state.dart`, `checklist_state.dart`, `navegacion_state.dart`.
- `screens/`: una pantalla por flujo (alistar_requerimiento, editar_almacen, editar_cotizacion, revision_herramientas, datos_almacen, maleta, historial_cotizaciones, configuración, etc.).
- Requerimientos y salidas guardan sus ítems en `categorias_json` (lista de `ChecklistItemEntry` en JSON).

## 5. Base de datos local (SQLite, v9)
Tablas: `productos` (con `modificado`, `eliminado`, `clave_catalogo`), `cotizaciones_guardadas`, `checklists_guardados`, `requerimientos`, `checklists_herramientas`, `checklist_catalogo` (precio, orden, base), `maletas`, `maleta_items`.

## 6. Base de datos MySQL/MariaDB para varios dispositivos
Archivos: `estructura.sql` (15 tablas) y `datos_iniciales.sql` (800 productos, 99 ítems de lista, 3 maletas). Probados en MariaDB 10.11.
- Acceso: `usuarios` (rol: admin, vendedor, jefe_obra, almacen), `sesiones`, `configuracion` (igv, zona_horaria, clave_edicion).
- Control: `correlativos` (S00001, REQ-0001, HER-0001 sin repetirse, vía `LAST_INSERT_ID(valor+1)`), `bitacora`.
- `productos`, `cotizaciones` + `cotizacion_items` (guardan nombre y precio del momento).
- Listas: `checklist_catalogo`, `maletas`, `maleta_items`.
- Almacén: `requerimientos` + `requerimiento_items` (con `alistado`, `alistado_por`, `fecha_alistado`), `checklists_herramientas` + `checklist_herramientas_items` (con `salio`, `volvio`).
- Control de concurrencia con `version` (si dos dispositivos editan lo mismo, el segundo recibe aviso). Campos `editado_en`, `editado_por` y `agregado_en_edicion` para las ediciones.
- Las fotos van como archivos en `uploads/`, la base solo guarda la ruta.

## 7. Archivos de datos de cotización (`assets/`)
- `productos_seed.json`: 800 productos. Campos: `nombre`, `categoria_producto`, `costo`, `precio_venta`, `referencia_interna`, `unidad_medida`, `archivo_imagen`, `imagen_url`.
- `checklist_seed.json` y `precios_materiales.json`: lista base de materiales con precios.

## 8. Decisiones y requerimientos del negocio
- **Todo debe compartir una sola base de datos.** Varias personas participan a la vez: cualquier empleado envía el requerimiento, el encargado lo aprueba, el almacenero lo alista, el empleado confirma que lo recibió. Todos ven los mismos datos; los **roles** solo limitan las acciones, no los datos.
- Inicio de sesión: usar el mismo del ERP de la empresa.
- Falta un rol `empleado` y renombrar `jefe_obra` a `encargado` en `usuarios.rol`.
- La empresa tiene **~50 empleados**. Su ERP (con inventarios) corre sobre **Postgres**. Los 800 productos ya están en el ERP; conectar el catálogo se hará después (`productos.codigo_erp` está previsto para eso).
- Infraestructura: antes tenían un VPS en Hostinger administrado por una sola persona que se va. Plan: VPS **KVM 8 de Hostinger** (8 vCPU, 32 GB) a 24 meses con Docker, Postgres único compartido, respaldos diarios externos, dominio a nombre de la empresa y dos administradores. No comprar servidor físico por ahora.

## 9. Pendiente
- Adaptar la API (PHP) y la app al esquema nuevo: endpoints de alistado (`POST requerimientos/{id}/alistar`) y de edición (`PUT` de requerimientos, herramientas, cotizaciones) con clave y `version`.
- **Pasar el esquema de MySQL a Postgres** si todo va a vivir junto al ERP.
- Roles `empleado` / `encargado` y login con el ERP.
- Ordenar ramas: `main` (offline) y una rama de producción.
- Traer los productos del ERP.
- Migración de dominios y respaldos del servidor actual.

## 10. Servidor compartido en el VPS (carpeta `servidor/`)
Hecho después de lo anterior; reemplaza a la idea de MySQL/PHP:
- **PostgreSQL** (`servidor/db/schema.sql`, datos iniciales `seed.sql`, generados con `generar_seed.mjs`; tablas nuevas en `db/migraciones/`).
  Documentos (`requerimientos`, `checklists_herramientas`, `cotizaciones`) guardan los ítems en JSONB y tienen `version`; vistas planas `v_requerimiento_items`, `v_herramientas_items`, `v_cotizacion_items`.
- **API Node/Express** (`servidor/api/`): login con usuarios y roles (admin, empleado, encargado, almacén, vendedor), reglas de estado por rol
  (encargado aprueba, almacén alista, empleado confirma la recepción), clave de edición verificada por el servidor (permiso de 15 min),
  aviso de conflicto 409 si dos personas cambian lo mismo, bitácora y subida de fotos. 16 pruebas contra PostgreSQL real.
- **App Flutter**: `DbHelper` es una interfaz con `DbLocal` (SQLite, sin servidor) y `DbApi` (servidor). La web usa siempre el servidor
  (misma dirección, `/api`); el APK lo usa con `--dart-define=API_URL=https://api.DOMINIO/api`. Login, actualización automática cada 20 s y botones según el rol.
  Prueba de punta a punta: `test/integracion_api_test.dart` (necesita una API de prueba corriendo).
- **Vista general** (`servidor/portal/index.html`): tablas simples de lo que hace todo el equipo, detalle por ítem, usuarios y bitácora.
- **Despliegue**: `servidor/docker-compose.yml` (db + api + Caddy con HTTPS), `Caddyfile`, scripts de respaldo/restauración, guía `servidor/DESPLIEGUE.md`.
- **Finanzas** (carpeta `finanzas/`): PWA Expo/React Native Web en línea (no offline; varias personas a la vez) + API Node/TS (`finanzas/api`) que comparte la base, los usuarios y las sesiones de la API principal. Rol nuevo `finanzas`. Incluye cierre del día (arqueo con efectivo contado, día bloqueado), historial de cambios (`caja_auditoria` con valor anterior), roles en el servidor (`FINANZAS_ROLES_*`), alertas de descuadre, concurrencia con `version` y refresco cada 6 s. Se publica en `finanzas.icrenergy.tech` (`/api-caja`), y la pestaña **Finanzas** del portal (`app.`) muestra saldos, alertas, cierres y cambios. El respaldo incluye la base y las fotos de recibos.
- Dominio: `icrenergy.tech` (subdominios cotizador., app., api., finanzas.). VPS KVM 4 de Hostinger, IP 200.141.24.38.
- Pendiente: probar el despliegue real en el VPS (Docker no se pudo probar en el entorno de desarrollo), roles/login con el ERP, productos desde el ERP,
  respaldo externo, revisar el plazo del VPS (la caducidad mostraba 2026-11-22).
