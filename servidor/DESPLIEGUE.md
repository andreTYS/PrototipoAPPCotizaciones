# Cotizador ICR y Finanzas en el VPS (guía paso a paso)

Qué queda funcionando al terminar:

| Dirección | Qué es |
|---|---|
| `https://cotizador.TUDOMINIO` | La app (PWA instalable en el celular). Varias personas, una sola base de datos. |
| `https://app.TUDOMINIO` | Vista general: cotizaciones, requerimientos y salidas de herramientas de todos, en tablas simples. También administra usuarios. |
| `https://api.TUDOMINIO` | La API sola (para el APK u otras apps que se hagan después). |
| `https://finanzas.TUDOMINIO` | **Finanzas**: caja diaria, caja chica, cierre del día y reportes. Varias personas a la vez, con su mismo usuario de la app. Sus datos también se ven en la pestaña **Finanzas** de `app.TUDOMINIO`. |

Todo corre en el mismo VPS con Docker: **PostgreSQL** (la base, una sola para todo), la **API** del cotizador, la **API de Finanzas** y **Caddy** (que pone el HTTPS solo).
La base de datos no se expone a internet: solo la API habla con ella.

---

## 1. DNS (en Hostinger → Dominios → DNS / Nameservers → Registros DNS)

Agrega registros **A**, todos con la IP del VPS (la ves en el panel del VPS):

| Tipo | Nombre | Apunta a |
|---|---|---|
| A | `cotizador` | IP del VPS |
| A | `app` | IP del VPS |
| A | `api` | IP del VPS |
| A | `finanzas` | IP del VPS |

No borres ni cambies los registros que ya existan (sobre todo `@`, `www` y los de correo).
Tarda de unos minutos a unas horas. Revisa en https://dnschecker.org que `cotizador.TUDOMINIO` ya muestre la IP.

## 2. Preparar el VPS (una sola vez)

Entra por SSH (panel de Hostinger → VPS → Administrar → Terminal, o `ssh root@IP`).

```bash
# Actualizar
apt update && apt upgrade -y

# Firewall: solo SSH, web y web segura
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable

# Comprobar que Docker ya está (la plantilla con Docker de Hostinger lo trae)
docker --version && docker compose version
```

Si Docker no está: `curl -fsSL https://get.docker.com | sh`.

## 3. Subir el servidor

Opción A (con el zip `servidor_icr.zip`): súbelo al VPS (SFTP o el administrador de archivos de Hostinger) y:

```bash
mkdir -p /opt/icr && cd /opt/icr
unzip -o ~/servidor_icr.zip -d /opt/icr   # deja /opt/icr/servidor/... y /opt/icr/finanzas/... (una al lado de la otra)
cd /opt/icr/servidor
```

> **Importante:** las dos carpetas, `servidor` y `finanzas`, deben quedar una al lado de la otra: la API de Finanzas se construye desde `../finanzas`.
> Si ya tenías `servidor` funcionando, `unzip -o` solo reemplaza los archivos; tus claves (`.env`), la carpeta `web` y los respaldos no se tocan.

Opción B (desde GitHub): `git clone <url-del-repositorio> /opt/icr && cd /opt/icr/servidor`
(si el repositorio es privado, hay que crear un token de acceso en GitHub).

## 4. Configurar las claves

```bash
cp .env.example .env
nano .env        # completa DOMINIO, POSTGRES_PASSWORD, ADMIN_CLAVE, CLAVE_EDICION
chmod 600 .env
```

- `DOMINIO`: tu dominio sin `www` (por ejemplo `icrenergy.tech`).
- `POSTGRES_PASSWORD`: una clave larga y única (no la volverás a escribir en ningún lado).
- `ADMIN_CLAVE`: la clave del primer administrador (usuario `admin`).
- `CLAVE_EDICION`: la clave para editar documentos ya registrados (ahora es `1234`; mejor cámbiala luego desde la vista general).

**Guarda estas claves en un gestor de contraseñas compartido** (Bitwarden, etc.), no en una sola cabeza.

## 5. Arrancar

```bash
docker compose up -d --build
docker compose ps                 # los 4 servicios deben decir "running"/"healthy"
docker compose logs -f api        # debe decir "Datos iniciales cargados" y "escuchando en el puerto 3000"
docker compose logs finanzas-api  # debe decir "Migración aplicada: 001_caja.sql" (y 002) y "API de caja escuchando"
```

La primera vez la API crea las tablas y carga los 800 productos, las listas del checklist y las maletas.
Caddy pide solo los certificados HTTPS (necesita que el DNS ya apunte al VPS y que los puertos 80/443 estén abiertos).

## 6. Subir la app web

La app web se compila en GitHub (no en el VPS):

1. En GitHub → pestaña **Actions** → **Build web** → **Run workflow**.
2. Cuando termine, descarga el artefacto `cotizador-web` (un zip) y súbelo al VPS.
3. En el VPS:

```bash
cd /opt/icr/servidor
./scripts/actualizar_web.sh ~/cotizador-web.zip
```

(Si te pasaron el zip ya armado, es el mismo paso.) Para publicar una versión nueva en el futuro, repite estos 3 pasos;
la anterior queda en `web.anterior` por si hay que volver atrás.

## 6b. Subir la app de Finanzas

Igual que la app web, se compila en GitHub:

1. GitHub → **Actions** → **Build finanzas** → **Run workflow** (prueba la app y la API y arma la web).
2. Descarga el artefacto `finanzas-web` (un zip) y súbelo al VPS.
3. En el VPS:

```bash
cd /opt/icr/servidor
./scripts/actualizar_finanzas.sh ~/finanzas-web.zip
```

(Si te pasaron el zip ya armado, es el mismo paso.) Abre `https://finanzas.TUDOMINIO` e ingresa con un usuario de rol **Finanzas**, **Encargado** o **Administrador**.
La API de Finanzas no necesita configuración extra: usa la misma base y los mismos usuarios.

## 7. Primer ingreso

1. Abre `https://app.TUDOMINIO` e ingresa con `admin` y tu `ADMIN_CLAVE`.
2. Pestaña **Usuarios** → **Nuevo usuario** para cada persona. Roles:
   - **Empleado**: pide materiales, registra salidas de herramientas, cotiza y confirma lo que recibió.
   - **Encargado**: aprueba requerimientos y confirma devoluciones.
   - **Almacén**: alista los materiales, confirma salidas y devoluciones de herramientas.
   - **Vendedor**: cotiza y edita productos.
   - **Administrador**: todo, incluido eliminar documentos y manejar usuarios.
   - **Finanzas**: lleva la caja diaria y la caja chica en `finanzas.TUDOMINIO`: registra, corrige días anteriores y cierra el día.

   Quién puede qué en **Finanzas** (el servidor lo comprueba, no hay códigos compartidos):

   | | Admin | Finanzas | Encargado | Empleado / Almacén / Vendedor |
   |---|:-:|:-:|:-:|:-:|
   | Entrar y registrar movimientos de hoy | ✔ | ✔ | ✔ | — |
   | Corregir días anteriores | ✔ | ✔ | — | — |
   | Cerrar el día (arqueo) | ✔ | ✔ | — | — |
   | Reabrir un día cerrado (con motivo) | ✔ | — | — | — |
   | Cambiar saldos iniciales | ✔ | — | — | — |
   | Ver alertas, historial de cambios y reportes | ✔ | ✔ | ✔ | — |

   Se puede cambiar con las variables `FINANZAS_ROLES_*` del `.env` (ver `.env.example`); después `docker compose up -d`.
3. Cambia la clave del administrador (botón **Nueva clave**) y, si quieres, la **clave de edición**.
4. Cada persona abre `https://cotizador.TUDOMINIO` en su celular → menú del navegador → **Instalar app / Agregar a pantalla de inicio**.

## 8. Respaldos (importante)

```bash
cd /opt/icr/servidor
./scripts/respaldo.sh      # prueba: crea respaldos/cotizador_FECHA.sql.gz y las fotos
```

Cada respaldo tiene tres archivos: la **base** (`cotizador_*.sql.gz`, con todo: cotizaciones, almacén y finanzas), las **fotos de la app** (`fotos_*.tar.gz`) y las **fotos de recibos de Finanzas** (`fotos_finanzas_*.tar.gz`).
Las fotos no están dentro de la base, por eso van aparte. Si algo falla, el script termina con error y lo dice.
Para restaurar fotos: `./scripts/restaurar_fotos.sh respaldos/fotos_finanzas_FECHA.tar.gz finanzas` (o `api` para las de la app).

Prográmalo cada noche:

```bash
crontab -e
# agrega esta línea:
30 2 * * *  cd /opt/icr/servidor && ./scripts/respaldo.sh >> respaldos/respaldo.log 2>&1
```

Guarda 14 días en el mismo VPS. **No basta**: copia también a otro proveedor (Backblaze B2, Google Drive...):
instala `rclone`, corre `rclone config` una vez y define `RCLONE_DESTINO=nombre:carpeta` en el cron.
Una vez al mes **prueba restaurar** en otro lado (`./scripts/restaurar.sh archivo.sql.gz`).

## 9. Actualizar el servidor

```bash
cd /opt/icr/servidor
git pull                       # o sube los archivos nuevos
docker compose up -d --build   # reconstruye la API; las migraciones nuevas se aplican solas
```

## 10. Agregar tablas nuevas más adelante

Se crea un archivo en `db/migraciones/` (ver el `LEEME.md` de esa carpeta). No se toca `schema.sql`.
Las tablas de Finanzas viven en `finanzas/db/migrations/` y la API de Finanzas las aplica sola al arrancar.

## Problemas comunes

| Síntoma | Qué mirar |
|---|---|
| El navegador dice "no es seguro" / no hay HTTPS | `docker compose logs caddy`. Casi siempre es que el DNS todavía no apunta al VPS, o los puertos 80/443 están cerrados. |
| `cotizador.` muestra "404" o página en blanco | Falta subir la app web (paso 6). |
| `finanzas.` muestra "404" o página en blanco | Falta subir la app de Finanzas (paso 6b). |
| Finanzas dice "Sin acceso" | Esa cuenta tiene rol Empleado, Almacén o Vendedor. Un administrador le asigna el rol Finanzas o Encargado (Usuarios). |
| Finanzas dice "Sin conexión" | La app de Finanzas **solo funciona con internet** (varias personas comparten los datos). Nada se guarda sin conexión; al volver, se repite el registro. |
| `docker compose` falla con "../finanzas not found" | Falta la carpeta `finanzas` al lado de `servidor` (paso 3). |
| No me deja entrar | Revisa el usuario/clave. Tras 10 intentos fallidos se bloquea 15 minutos. Un administrador puede poner una clave nueva en la vista general. |
| "Otra persona modificó esto..." | Es normal: alguien más cambió el mismo documento. Se actualiza solo; revisa y repite el cambio. |
| Olvidé la clave del administrador | `./scripts/clave_usuario.sh admin` pone una clave nueva. Lo más fácil es tener **dos administradores** desde el inicio. |

## Cómo se conecta el ERP después

El ERP puede correr en el mismo VPS (otro contenedor, subdominio `erp.TUDOMINIO` con otra entrada en el `Caddyfile`).
Para compartir los usuarios y los productos se conectará a esta API o a la base de datos (ya está previsto
`productos.codigo_erp`). Eso se define cuando se sepa qué ERP es.

## APK conectado al servidor (opcional)

La app de celular también puede usar el servidor en vez de su base local:

```bash
flutter build apk --release --dart-define=API_URL=https://api.TUDOMINIO/api
```
