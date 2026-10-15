# Backend del Cotizador ICR — Docker + PostgreSQL

API en PHP plano (sin framework) + PostgreSQL, en Docker detrás de Traefik —
mismo patrón que el resto del ecosistema ICR en tu VPS (icr-almacen-mvp: un
contenedor Postgres propio + un contenedor de la API, por detrás de Traefik).
Ya **no** es para Hostinger compartido ni MySQL — eso quedó descartado.

Login **nunca** guarda ni compara claves propias: valida contra el ERP real
(`https://erp.inversionesicr.com/api/auth/login`, llamada servidor-a-servidor
por su dominio público) y recién ahí crea la sesión local.

## Qué incluye

- `../base_de_datos/estructura.sql` / `datos_iniciales.sql` — esquema
  (Postgres 16) + semilla (checklist de materiales/herramientas, maletas, los
  800 productos). El `docker-compose.yml` de acá los monta directo de ahí —
  no hay copias sueltas de esos archivos dentro de esta carpeta.
- `config.php` — conexión a Postgres (todo por variables de entorno) + helpers
  de respuesta JSON.
- `auth_helper.php` — valida el token de sesión y el rol en cada llamada.
- `bitacora_helper.php` — quién hizo qué y cuándo; números de documento sin
  repetirse aunque dos dispositivos pidan uno a la vez.
- `login.php` — valida contra el ERP, espeja el usuario, crea la sesión.
- `requerimientos.php`, `cotizaciones.php`, `checklists_herramientas.php`,
  `checklist_catalogo.php`, `maletas.php`, `productos.php` — las 4 fases
  completas (requerimientos con sus 4 roles, cotizaciones editables con
  clave, salidas de herramientas, listas y catálogo de productos).
- `Dockerfile` — `php:8.3-apache` + `pdo_pgsql`.
- `docker-compose.yml` — contenedor `db` (Postgres 16) + contenedor `backend`,
  con las labels de Traefik ya puestas.
- `.env.example` — cópialo a `.env` y completa los valores reales.

**Probado de punta a punta contra PostgreSQL real** (no MySQL): los 4 roles
de un requerimiento completo (crear → aprobar → alistar ítem por ítem →
listo → entregar), el candado de "no pasa a listo si falta un material",
control de versión optimista (conflicto 409 real), bitácora completa,
cotizaciones con su correlativo (`S00001`), productos (800 cargados,
búsqueda) y una salida de herramientas completa (registrado → pendiente →
conforme).

## Los dominios (ninguno nuevo — va todo bajo el que ya existe)

| Servicio | Dominio |
|---|---|
| ERP (Node/Express + Postgres) | `erp.inversionesicr.com` |
| Tienda | `tienda.inversionesicr.com` |
| Finanzas | `finanzas.inversionesicr.com` |
| Cotizador (app Flutter, web) | `cotizador.inversionesicr.com` |
| **Este backend** | **`cotizador.inversionesicr.com/api`** — mismo dominio, sin DNS nuevo |

Nada de subdominio aparte: este backend vive bajo `/api` del mismo
`cotizador.inversionesicr.com` que ya usa la app. El `docker-compose.yml` de
acá agrega un router de Traefik con `Host(cotizador.inversionesicr.com) &&
PathPrefix(/api)` — más específico que el router de la app (que solo matchea
el Host a secas, en el otro `docker-compose.yml` de la raíz del repo) — con
un `StripPrefix` que le saca el `/api` antes de pasarle la ruta al PHP
(`/api/login.php` en el navegador llega como `/login.php` al contenedor). El
certificado de ese dominio ya existe (lo emitió el router de la app web);
Traefik lo reusa para este router también.

La llamada de este backend al ERP (`login.php`, vía `ERP_API_URL`) es
servidor-a-servidor por el dominio público de siempre — no hace falta unir
redes Docker ni tocar el `ALLOWED_ORIGIN`/CORS del ERP (eso es solo para
llamadas desde el navegador, como la que ya hace el Cotizador web).

## Desplegar en el VPS

Todo esto vive en el mismo repo del Cotizador (`origin/main`) — en el VPS es
puro `git pull`, nada de copiar archivos a mano desde tu PC.

1. En el VPS, donde ya tienes `~/PrototipoAPPCotizaciones` clonado (el mismo
   repo del build web): `cd ~/PrototipoAPPCotizaciones && git pull`.
2. `cd backend-api && cp .env.example .env` y completa `DB_PASSWORD` (una
   clave nueva) y confirma `DOMAIN`/`ERP_API_URL`.
3. Verifica que la red externa de Traefik exista (ya debería, la usan el
   ERP/tienda/Cotizador web): `docker network ls | grep n8n_default`.
4. `docker compose up -d --build`
   - La primera vez, Postgres corre `../base_de_datos/estructura.sql` y
     `datos_iniciales.sql` automáticamente (son los
     `docker-entrypoint-initdb.d/*`, solo se ejecutan si el volumen está
     vacío).
5. Sube las fotos reales a `uploads/` **dentro del volumen** del contenedor
   `backend` (no hace falta rebuild para esto):
   ```bash
   docker cp ../assets/productos icr_cotizador_backend:/var/www/html/uploads/
   docker cp ../assets/maletas   icr_cotizador_backend:/var/www/html/uploads/
   ```
6. Prueba: `https://cotizador.inversionesicr.com/api/requerimientos.php` con
   un token válido debería responder `{"status":"ok","data":{"items":[]}}`.
   Sin token da 401 (así confirmas que el `/api` sí está llegando a este
   contenedor y no al de la app web).

Si ya desplegaste antes con `cotizador-api.inversionesicr.com` como
`DOMAIN`: edita el `.env` (no lo toca `git pull`, hay que entrar a mano) con
`DOMAIN=cotizador.inversionesicr.com` y `docker compose up -d` de nuevo para
que Traefik vea las labels nuevas. El registro DNS tipo A que hayas creado
para `cotizador-api` ya no hace falta, puedes borrarlo del hPanel.

## Del lado de Flutter

`CotizadorApiService`/`SesionService`/`LoginScreen` ya están en el repo del
Cotizador (`origin/main`, commit `818de0f`) apuntando a lo que el usuario
configure como "servidor" en el login — ahí va
`https://cotizador-api.inversionesicr.com` (sin `/api` al final, el PHP vive
en la raíz). Falta cablear `AlmacenState` para que use este cliente en vez
de `db_helper.dart` local — ver conversación.
