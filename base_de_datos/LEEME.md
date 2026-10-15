# Base de datos para varios dispositivos

Base **PostgreSQL 16** — mismo motor que ya usa el ERP (icr-almacen-mvp), en
Docker en el VPS, no MySQL/Hostinger (así empezó este archivo originalmente,
se migró de ahí). Los dispositivos no se conectan a la base: hablan con la
API en `backend-api/` (Docker, PHP + PDO pgsql) que lee y escribe en estas
tablas, así todos ven lo mismo.

| Archivo | Qué es |
|---|---|
| `estructura.sql` | Las 15 tablas (acceso, productos, cotizaciones, almacén, listas, maletas, control), sintaxis Postgres. |
| `datos_iniciales.sql` | Listas del checklist con precios (99 ítems), 3 maletas (72 herramientas) y los 800 productos. |

## Cómo se carga

No a mano: `backend-api/docker-compose.yml` monta estos dos archivos como
`docker-entrypoint-initdb.d/*` del contenedor `db` (Postgres) — se ejecutan
solos la primera vez que ese volumen está vacío. Ver `backend-api/LEEME.md`
para el despliegue completo (dominios, `.env`, `docker compose up`).

## Tablas

- **Acceso:** `usuarios`, `sesiones`, `configuracion`
- **Productos:** `productos` (con `codigo_erp` para enlazar con el ERP)
- **Cotizaciones:** `cotizaciones`, `cotizacion_items` (guardan nombre y precio del momento)
- **Almacén:** `requerimientos` + `requerimiento_items` (con precio unitario y el **alistado por material**:
  `alistado`, `alistado_por`, `fecha_alistado`),
  `checklists_herramientas` + `checklist_herramientas_items` (con `salio` / `volvio` por herramienta)
- **Listas:** `checklist_catalogo` (materiales con precio y herramientas), `maletas` + `maleta_items`
- **Control:** `correlativos` (números S, REQ, HER sin repetirse), `bitacora` (quién cambió qué)

## Pensada para varios dispositivos

- Los números de documento los reparte el servidor con una transacción: dos
  celulares nunca sacan el mismo.
- `requerimientos` y `checklists_herramientas` tienen `version`: si dos
  dispositivos cambian el mismo registro a la vez, el segundo recibe un aviso
  en lugar de pisar al primero.
- Los estados nuevos están completos: requerimiento
  `pendiente → aprobado → listo → entregado`; herramientas
  `registrado → pendiente → conforme`.
- **Alistado compartido:** cada material del requerimiento guarda si ya se alistó, quién y
  cuándo. Una persona alista parte y guarda; otra continúa con lo que falta. Cuando todos
  están alistados el requerimiento pasa solo a `listo`.
- **Edición con clave:** cotizaciones, requerimientos y salidas de herramientas se pueden
  editar (agregar un producto, material o herramienta olvidado o de último momento) tras
  ingresar la clave, guardada cifrada en `configuracion.clave_edicion` (de inicio `1234`).
  Cada tabla guarda `editado_en` / `editado_por`, los ítems agregados así quedan con
  `agregado_en_edicion = 1`, y el detalle del cambio va a `bitacora`. Un requerimiento
  `listo`/`entregado` al que se le agrega algo vuelve a `aprobado` (falta alistar lo nuevo);
  una salida `conforme` a la que se agrega una herramienta vuelve a `pendiente`.
- Nada importante se borra de verdad (`activo = 0`); al eliminar una maleta o
  un producto, el historial queda intacto.
