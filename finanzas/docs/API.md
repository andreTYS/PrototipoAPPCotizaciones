# API de Caja diaria y Caja chica

Contrato entre la PWA (`app/`) y el servidor. La implementación está en `api/` (Node + Postgres) y corre junto a la API del Cotizador, con la **misma base de datos, los mismos usuarios y las mismas sesiones**. Las tablas están en `db/migrations/` (`001_caja.sql`, `002_cierre_auditoria.sql` y `003_comprobante_recibo.sql`).

Los nombres de campo de la API, de las tablas y del modelo de la app (`app/src/lib/caja/types.ts`) coinciden a propósito.

## Convenciones

- **Respuesta**: `{ "status": "success", "data": … }` o `{ "status": "error", "error": { "code": "…", "message": "…" } }` (mismo formato que ya usa el ERP). Las fotos (`GET /caja/adjuntos/:id`) devuelven el binario.
- **Sesión**: `Authorization: Bearer <token>`. La app obtiene el token con `POST /auth/login` `{usuario, clave}` (la API lo pasa a la API principal; devuelve `data.token`, `data.user`, `data.permisos`) y lo reenvía en cada llamada. El token es la sesión del sistema (`sesiones`): al desactivar a un usuario o cerrar su sesión, deja de valer en todas las apps.
- **En línea**: la app no guarda datos en el dispositivo ni acepta cambios sin conexión; varias personas trabajan a la vez sobre los mismos datos. Cada 6 s pregunta `GET /caja/version` (una huella) y solo recarga si cambió.
- **Ciudades**: `AQP` (Arequipa) y `MOQ` (Moquegua). Cada ciudad tiene su caja diaria y su caja chica.
- **Fechas**: `YYYY-MM-DD`, hora local de Perú. Importes: números con 2 decimales, siempre ≥ 0 (la dirección la da la columna, no el signo).
- **IDs**: los genera el **cliente** (UUID v4) y los envía en la URL. Todas las escrituras son **idempotentes**: repetir un `PUT` con el mismo id deja el mismo resultado, así un reintento por una respuesta perdida no duplica nada.
- **Cambios simultáneos**: cada fila, gasto y hoja tiene un número de `version`. Si dos personas cambian lo mismo a la vez, la segunda recibe `409 CAMBIO_CONCURRENTE` y ve lo que dejó la primera.
- **Saldos**: los calcula el servidor (vistas `v_caja_hoja_resumen` y `v_caja_chica_saldo`); la app los replica para mostrarlos al instante, y hay una prueba (`api/src/crosscheck.test.ts`) que comprueba que ambos cálculos coinciden.

## Rutas

| Método y ruta | Qué hace |
|---|---|
| `GET /caja/estado?ciudad=` | Saldos iniciales y saldos actuales de caja, cuenta corriente y caja chica. |
| `PUT /caja/config/:ciudad` | Cambia los saldos iniciales (`saldo_inicial_caja`, `saldo_inicial_cta_cte`, `saldo_inicial_caja_chica`). Solo roles de `ADMIN_ROLES` (si no se define, cualquier usuario con sesión); `403 SIN_PERMISO` si no. |
| `POST /caja/hojas/abrir` | `{ciudad, fecha, id?}` → crea la hoja del día si no existe (una por ciudad y fecha) y la devuelve. |
| `GET /caja/hojas?ciudad=&desde=&hasta=` | Hojas del rango con sus filas, adjuntos y saldos (`saldo_anterior_*`, `saldo_final_*`). |
| `PATCH /caja/hojas/:id` | Pie de la planilla: `responsable_caja`, `obras_realizadas`, `maletas`, `escaleras`, `encargado_obra`. |
| `PUT /caja/filas/:id` | Crea o corrige una fila. Cuerpo abajo. |
| `DELETE /caja/filas/:id` | Elimina (marca `deleted_at`) y anula su reflejo en el ERP. |
| `POST /caja/transferencias` | Envía dinero de caja diaria a caja chica **en una sola transacción**: `{id, fila_id, movimiento_id, ciudad, fecha, monto, nota?}`. Crea la fila interna (salida en efectivo) y el movimiento de caja chica. `422 SALDO_INSUFICIENTE` si la caja no alcanza. |
| `DELETE /caja/transferencias/:id` | Anula un envío. `409 SALDO_CHICA_INSUFICIENTE` si caja chica ya gastó ese dinero. |
| `PUT /caja/adjuntos/:id?fila_id=` o `?movimiento_id=` | Sube la foto de un recibo (cuerpo binario, `Content-Type: image/jpeg\|png\|webp`). Máx. 10 MB por foto. |
| `GET /caja/adjuntos/:id` · `DELETE …` | Baja o quita una foto. |
| `GET /caja-chica/movimientos?ciudad=&desde=&hasta=` | `{saldo_anterior, movimientos[]}` del rango. |
| `PUT /caja-chica/movimientos/:id` | Crea o corrige un egreso: `{ciudad, fecha, descripcion, persona, categoria, subcategoria?, monto, origen}` (`origen`: `MANUAL` o `CAPTURA`). |
| `DELETE /caja-chica/movimientos/:id` | Elimina un egreso. |
| `POST /caja/erp/reintentar` | Reintenta lo que quedó pendiente de reflejar en el ERP. |
| `GET /caja/permisos` | `{usuario, permisos}`: lo que el rol de la sesión puede hacer (`acceso`, `corregir_pasado`, `cerrar`, `reabrir`, `configurar`, `revisar`). |
| `GET /caja/version` | `{version}`: huella de todos los datos de caja. |
| `POST /caja/hojas/:id/cerrar` | **Cierre del día**: `{efectivo_contado, nota?}`. Guarda saldo calculado, diferencia, quién y cuándo, y bloquea el día. La nota es obligatoria si hay diferencia. Los días se cierran en orden (`409 DIA_ANTERIOR_ABIERTO`). |
| `POST /caja/hojas/:id/reabrir` | `{motivo}`: reabre un día cerrado (solo rol con permiso `reabrir`, por defecto `admin`). |
| `GET /caja/auditoria?ciudad=&fecha=&desde=&hasta=&limite=` | **Historial de cambios**: quién, cuándo, qué, valor anterior y nuevo. Requiere `revisar`. |
| `GET /caja/alertas?ciudad=` | **Alertas de descuadre**: cajas en negativo, filas sin comprobante, días sin cerrar, diferencias de cierre. Requiere `revisar`. |
| `GET /caja/resumen` | Resumen por ciudad (saldos, hoy, últimos días con su cierre), alertas y cambios recientes. Lo usa la pestaña Finanzas del portal. |
| `GET /health` | `{ok:true}`, sin sesión. |

### Cuerpo de `PUT /caja/filas/:id`

```json
{
  "hoja_id": "uuid",
  "tipo": "VTA | OBRA | OTRO",
  "descripcion": "Venta de panel",
  "responsable": "Carlos",
  "comprobante": "FACTURA | BOLETA | RECIBO | NINGUNO",
  "caja_ingreso_efectivo": 0, "caja_ingreso_transf": 0,
  "caja_salida_efectivo": 0,  "caja_salida_transf": 0,
  "cta_cte_ingreso": 0,       "cta_cte_salida": 0,
  "categoria": "", "subcategoria": "", "interno": false
}
```

Reglas (el servidor las valida igual que la app): descripción y responsable obligatorios; al menos un importe > 0; si hay salida real (no `interno`) la `categoria` es obligatoria, y con `Gastos fijos` también la `subcategoria` (`Sueldos`, `Alquiler`, `Servicios`). Categorías: Equipos, Caja chica, Movilidad, Material, Oficina, Fletes, Viáticos, Proveedores, Gastos fijos.

## Códigos de error

`400 DATOS_INVALIDOS` · `401 NO_AUTORIZADO` · `403 SIN_ACCESO / SIN_PERMISO` · `404 HOJA_NO_ENCONTRADA / ADJUNTO_NO_ENCONTRADO / DUENO_NO_ENCONTRADO` · `409 CAMBIO_CONCURRENTE / DIA_CERRADO / DIA_POSTERIOR_CERRADO / DIA_ANTERIOR_ABIERTO / FILA_ELIMINADA / MOVIMIENTO_ELIMINADO / FILA_DE_TRANSFERENCIA / MOVIMIENTO_DE_TRANSFERENCIA / HOJA_DISTINTA / CIUDAD_DISTINTA / SALDO_CHICA_INSUFICIENTE` · `413 FOTO_MUY_GRANDE / CUERPO_MUY_GRANDE` · `415 TIPO_NO_PERMITIDO` · `422 SALDO_INSUFICIENTE`.

La app trata un `4xx` como definitivo (muestra el mensaje y vuelve a cargar lo que hay en el servidor) y un error de red o `5xx` como temporal (reintenta). Una anulación rechazada hace que el elemento vuelva a aparecer en la siguiente carga.

## Reflejo en el ERP (Contabilidad → Flujo de caja)

Cada fila y cada egreso de caja chica **reales** se registran también en el ERP; lo demás no:

| Origen | Ingreso al ERP | Gasto al ERP |
|---|---|---|
| Fila de caja diaria (no `interno`) | `caja_ingreso_efectivo + caja_ingreso_transf + cta_cte_ingreso` | `caja_salida_efectivo + caja_salida_transf + cta_cte_salida` |
| Fila `interno` (depósito al banco, retiro, envío a caja chica) | — | — |
| Egreso de caja chica | — | `monto` |
| Envío a caja chica (transferencia) | — | — (sería contar dos veces el mismo dinero) |

- `tipo` de la fila → tipo de ingreso: `VTA→VENTA`, `OBRA→OBRA_PROYECTO`, `OTRO→OTRO`.
- Categoría → `EQUIPOS_OBRA`, `MOVILIDAD`, `MATERIAL`, `OFICINA`, `FLETES`, `VIATICOS`, `OTROS` (Caja chica, Proveedores); `Gastos fijos` → `SUELDO`, `ALQUILER` o `SERVICIOS` según la subcategoría. `channel: "web"`.
- Si el ERP no responde, la fila queda con `erp_pendiente = true` (y `erp_error`) y se reintenta con `POST /caja/erp/reintentar`. La caja **nunca** se bloquea por culpa del ERP.
- Al corregir o eliminar una fila ya reflejada se actualiza o anula el registro del ERP (`ingreso_erp_id`, `gasto_erp_id`).

## Roles (en el servidor)

Los roles son los de `usuarios.rol` del sistema: `admin`, `finanzas`, `encargado`, `almacen`, `empleado`, `vendedor`. El servidor decide; la app solo esconde los botones que no corresponden. Valores por defecto (cambiables con `FINANZAS_ROLES_*`, ver `api/src/permisos.ts`):

| Permiso | Roles |
|---|---|
| Entrar y registrar movimientos de hoy | `admin`, `finanzas`, `encargado` |
| Corregir días anteriores | `admin`, `finanzas` |
| Cerrar el día | `admin`, `finanzas` |
| Reabrir un día cerrado | `admin` |
| Cambiar saldos iniciales | `admin` |
| Ver alertas, historial de cambios y reportes | `admin`, `finanzas`, `encargado` |

Un día cerrado (o anterior a uno cerrado) no se puede cambiar por nadie hasta que un administrador lo reabra; la reapertura pide un motivo y queda en el historial de cambios.

## ⚠ Supuestos que hay que verificar contra el ERP real

1. **Sesión**: la API valida el token contra la tabla `sesiones` de la base compartida y crea la sesión llamando a la API principal (`MAIN_API_URL`). Si la integración con el ERP cambia el inicio de sesión, solo hay que ajustar `api/src/auth.ts` y `api/src/login.ts`.
2. **Reflejo**: crear usa `POST /income` y `POST /expenses` (así lo hace la app hoy y está verificado). Actualizar y anular usan `PUT`/`DELETE` sobre `/income/:id` y `/expenses/:id`: **no sabemos si existen**. Si la API vive dentro del ERP, lo correcto es escribir directo en sus tablas.
3. **Valor `channel`**: se usa `"web"`; si el ERP tiene un canal propio para la caja, se cambia en `api/src/erp.ts` (`CHANNEL`).
4. **CORS**: la PWA y la API se publican bajo el mismo origen (`finanzas.…/api-caja`), así que no hace falta. `CORS_ORIGIN` solo si algún día viven separadas.
5. **Base de datos**: `created_by`/`updated_by` guardan el id del usuario del token; si el ERP usa otro tipo de id, ajustar el tipo de columna en la migración antes de aplicarla.
