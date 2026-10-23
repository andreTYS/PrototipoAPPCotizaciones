# ICR Finanzas — Caja diaria, Caja chica y Reportes

PWA de Inversiones ICR para llevar la **caja diaria** (la planilla de papel «CAJA DIARIO»), la **caja chica**, cerrar el día y sacar **reportes**, por ciudad (Arequipa y Moquegua). Es una app **en línea**: varias personas la usan a la vez sobre los mismos datos (los de la base compartida del sistema), cada una con su propio usuario. Se instala en la pantalla de inicio, pero **no guarda nada en el teléfono ni acepta cambios sin internet**. Diseño ICR (Manrope · teal #0E7490 · cyan #12A3B8 · navy #124C8C).

Se publica en `https://finanzas.TUDOMINIO` y sus datos también se ven en la pestaña **Finanzas** de la vista general (`https://app.TUDOMINIO`). La guía de despliegue es **[../servidor/DESPLIEGUE.md](../servidor/DESPLIEGUE.md)**; el contrato de la API, **[docs/API.md](docs/API.md)**.

```
app/              La PWA (Expo · React Native Web · TypeScript)
api/              API (Node + Postgres): usa los usuarios y sesiones del sistema; Dockerfile incluido
db/migrations/    Tablas de caja (001), cierre del día, versiones e historial de cambios (002)
docs/API.md       Contrato de la API
design/           Diseño original exportado de Claude Design
```

## Qué hace

- **Caja diaria**: una hoja por día y ciudad, igual a la planilla de papel (saldo anterior, filas con tipo, responsable, comprobante, ingresos y salidas en efectivo/Yape/cuenta corriente, totales y observaciones). Cada fila admite fotos del recibo. Se puede **enviar dinero a caja chica**.
- **Caja chica**: egresos con foto del recibo (se lee con OCR y rellena el formulario) o a mano.
- **Cierre del día**: se escribe el efectivo contado, la app muestra la diferencia con el saldo calculado (la nota es obligatoria si hay diferencia) y el día queda **bloqueado para todos**. Los días se cierran en orden. Solo un administrador puede reabrirlo, con un motivo.
- **Historial de cambios**: cada alta, corrección, eliminación, cierre y reapertura guarda quién, cuándo y **cómo estaba antes**. Se ve con «Ver cambios del día» y en la pestaña Finanzas del portal.
- **Roles reales en el servidor** (sin códigos compartidos): `admin`, `finanzas` y `encargado` entran; solo `admin` y `finanzas` corrigen días anteriores y cierran; solo `admin` reabre y cambia saldos iniciales. Los demás roles (empleado, almacén, vendedor) no ven Finanzas. Se ajusta con las variables `FINANZAS_ROLES_*` (ver `servidor/.env.example`).
- **Alertas de descuadre** (Historial y portal): cajas en negativo, filas sin comprobante, días sin cerrar y cierres con diferencia.
- **Historial** de días anteriores y **Reportes** por día o rango, una ciudad o ambas, en Excel (.xlsx) o CSV.
- **Varias personas a la vez**: la app consulta cada 6 s si algo cambió y se actualiza sola; si dos personas cambian lo mismo, la segunda recibe un aviso y ve lo que dejó la primera.
- Lo que es ingreso o gasto real puede reflejarse en el ERP (Contabilidad → Flujo de caja) si se define `ERP_API_URL`; si no, no se refleja nada.
- **Respaldo**: `servidor/scripts/respaldo.sh` guarda cada noche la base **y** la carpeta de fotos de recibos (las fotos no están en la base).

## Desarrollo

```bash
cd app && npm ci
npm run web                  # servidor de desarrollo
npm run typecheck && npm test
npm run build:web            # exporta la web y la convierte en PWA (dist/)

cd ../api && npm ci
AUTH_MODE=dev npm start      # API con base en memoria y login de prueba, en :8787
npm test                     # incluye las migraciones sobre Postgres (PGlite) y pruebas con varias personas a la vez
```

## Reflejo en el ERP (Contabilidad → Flujo de caja)

Solo si se define `ERP_API_URL`. Cada fila y cada egreso de caja chica **reales** se registran también en el ERP; lo demás no:

| Origen | Ingreso al ERP | Gasto al ERP |
|---|---|---|
| Fila de caja diaria (no `interno`) | `caja_ingreso_efectivo + caja_ingreso_transf + cta_cte_ingreso` | `caja_salida_efectivo + caja_salida_transf + cta_cte_salida` |
| Fila `interno` (depósito al banco, retiro, envío a caja chica) | — | — |
| Egreso de caja chica | — | `monto` |
| Envío a caja chica (transferencia) | — | — (sería contar dos veces el mismo dinero) |

Si el ERP no responde, la fila queda con `erp_pendiente = true` y se reintenta con `POST /caja/erp/reintentar`; la caja **nunca** se bloquea por culpa del ERP. Detalles y supuestos por verificar en `docs/API.md`.

## APK

No se usa: la app es una PWA.
