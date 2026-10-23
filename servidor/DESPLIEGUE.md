# Despliegue del servidor compartido en el VPS real de Inversiones ICR

Esta carpeta (`servidor/`) trae la base de datos PostgreSQL y la API Node
del Cotizador compartido. **Adaptada** para el VPS real de Inversiones ICR,
que ya tiene Traefik sirviendo HTTPS para el ERP, la tienda, Finanzas y el
Cotizador web — por eso ya NO usa Caddy ni abre los puertos 80/443 (a
diferencia de como venía este módulo originalmente). El build web
(Flutter) lo sirve el `docker-compose.yml` de la raíz del repo (ya
desplegado, no se toca); Finanzas ya está en producción en otro repo
(`finanzas.inversionesicr.com`) y no se duplica acá.

## Pasos

```bash
cd servidor
cp .env.example .env
nano .env   # POSTGRES_PASSWORD (uno largo), y revisa DOMAIN/ERP_API_URL
docker compose up -d --build
```

La API queda disponible en `https://cotizador.inversionesicr.com/api/...`
y las fotos subidas en `.../uploads/...` — mismo dominio que ya usa la app
web, por `PathPrefix`, sin crear ningún subdominio nuevo. La primera vez
que arranca, `api/src/db.js` aplica `db/schema.sql`, las migraciones de
`db/migraciones/` y la semilla de `db/seed.sql` (productos, listas,
maletas) solo si la base está vacía.

## Login: contra el ERP real, no una clave propia

El login (`POST /api/login`, campos `usuario` = correo del ERP y `clave`)
valida contra `${ERP_API_URL}/auth/login` (ver `api/src/auth.js`) — nunca
guarda ni compara una contraseña propia. La primera vez que alguien entra,
su cuenta se "espeja" sola en la tabla `usuarios` (mismo id que en el ERP)
para las referencias de `bitacora`/`creado_por`; el rol lo decide
`mapearRolErp()` a partir del `rol_codigo` que manda el ERP:

| rol_codigo del ERP | rol acá    |
|---------------------|------------|
| ADMIN                | admin      |
| SUPERVISOR           | encargado  |
| VENTAS               | vendedor   |
| ALMACENERO           | almacen    |
| (cualquier otro)     | empleado   |

Si el ERP usa otros códigos, ajusta esa función — se puede ver la lista
real con `SELECT DISTINCT rol_codigo FROM usuarios` en la base del ERP.

No hay forma de crear cuentas "a mano" desde esta API (se quitó
`crearUsuario`/`actualizarUsuario`, que eran de la versión con clave
propia): todas las cuentas vienen del ERP.

## La app (web y APK)

La build web (ya desplegada) usa la API bajo su propio dominio
automáticamente (`/api`, mismo origen) — no necesita configuración. Para
un APK que hable con este servidor compartido (en vez de guardar todo
solo en el celular), hay que compilarlo con la URL de la API:

```bash
flutter build apk --dart-define=API_URL=https://cotizador.inversionesicr.com/api
```

Sin ese `--dart-define`, el APK queda en modo local (ver `lib/services/modo.dart`).

## Respaldos

`scripts/respaldo.sh` hace un `pg_dump` de la base; `scripts/restaurar.sh`
la restaura. `scripts/restaurar_fotos.sh` restaura el volumen de fotos
subidas (`uploads`). Revisa cada script antes de usarlo: algunos quedaron
de la versión con Caddy (p.ej. `scripts/actualizar_web.sh`,
`scripts/actualizar_finanzas.sh`, `scripts/clave_usuario.sh`) y no aplican
a este despliegue — el build web se actualiza con el flujo ya existente en
la raíz del repo (`docker compose up -d --build` del `cotizador` ahí), y
no hay clave propia que cambiar por usuario.
