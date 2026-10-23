-- ICR Finanzas · Caja diaria y Caja chica
-- Migración 001. PostgreSQL 13 o superior (usa gen_random_uuid(), que ya viene incluida).
--
-- Es SOLO ADITIVA: crea tablas y vistas nuevas con el prefijo caja_ / v_caja_ y no modifica ni
-- borra nada de lo que ya existe en la base del ERP. Se puede ejecutar más de una vez sin
-- problema (IF NOT EXISTS / OR REPLACE) y corre dentro de una transacción: si algo falla, no queda nada a medias.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/001_caja.sql
--
-- Para deshacerla: db/migrations/001_caja_down.sql  (BORRA los datos de caja; haz un respaldo antes).
--
-- Los campos `created_by` / `updated_by` guardan quién hizo el cambio (id o correo del usuario del
-- ERP). No llevan llave foránea porque no conocemos el nombre de la tabla de usuarios del ERP;
-- si quieres integridad referencial, agrega la FK a tu tabla de usuarios después de esta migración.

BEGIN;

-- ---------------------------------------------------------------------------------------------
-- Configuración por ciudad: saldos con los que arranca cada caja.
-- Todos los demás saldos se DERIVAN de estos más los movimientos (ver las vistas al final), así que
-- el saldo "anterior" de cada día siempre cuadra con el cierre del día previo, aunque se corrija un día pasado.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja_config (
  ciudad                    text PRIMARY KEY CHECK (ciudad IN ('AQP', 'MOQ')),
  saldo_inicial_caja        numeric(14,2) NOT NULL DEFAULT 0,
  saldo_inicial_cta_cte     numeric(14,2) NOT NULL DEFAULT 0,
  saldo_inicial_caja_chica  numeric(14,2) NOT NULL DEFAULT 0,
  updated_by                text,
  updated_at                timestamptz NOT NULL DEFAULT now()
);

INSERT INTO caja_config (ciudad) VALUES ('AQP'), ('MOQ') ON CONFLICT (ciudad) DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- Hoja: la planilla "CAJA DIARIO" de un día en una ciudad. Una por (ciudad, fecha).
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja_hoja (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ciudad            text NOT NULL REFERENCES caja_config (ciudad),
  fecha             date NOT NULL,
  responsable_caja  text NOT NULL DEFAULT '',
  -- Pie de la planilla (OBSERVACIONES)
  obras_realizadas  text NOT NULL DEFAULT '',
  maletas           text NOT NULL DEFAULT '',
  escaleras         text NOT NULL DEFAULT '',
  encargado_obra    text NOT NULL DEFAULT '',
  created_by        text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        text,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ciudad, fecha)
);

-- ---------------------------------------------------------------------------------------------
-- Transferencia de la caja diaria a la caja chica. Es el padre de DOS registros que se crean y se
-- anulan juntos: una fila de salida en la hoja del día y un ingreso en la caja chica.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja_transferencia (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ciudad      text NOT NULL REFERENCES caja_config (ciudad),
  fecha       date NOT NULL,
  monto       numeric(14,2) NOT NULL CHECK (monto > 0),
  nota        text NOT NULL DEFAULT '',
  created_by  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  deleted_by  text
);

-- ---------------------------------------------------------------------------------------------
-- Fila: una línea de la planilla. Los seis importes son las columnas del papel:
--   CAJA  · INGRESO (efectivo, yape/transf)   · SALIDA (efectivo, yape/transfer)
--   CTA CTE · INGRESO · SALIDA
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja_fila (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hoja_id                uuid NOT NULL REFERENCES caja_hoja (id) ON DELETE CASCADE,
  orden                  integer NOT NULL DEFAULT 0,
  tipo                   text NOT NULL CHECK (tipo IN ('VTA', 'OBRA', 'OTRO')),
  descripcion            text NOT NULL,
  responsable            text NOT NULL DEFAULT '',
  comprobante            text NOT NULL DEFAULT 'NINGUNO' CHECK (comprobante IN ('FACTURA', 'BOLETA', 'CONTRATO_TICKET', 'NINGUNO')),
  caja_ingreso_efectivo  numeric(14,2) NOT NULL DEFAULT 0 CHECK (caja_ingreso_efectivo >= 0),
  caja_ingreso_transf    numeric(14,2) NOT NULL DEFAULT 0 CHECK (caja_ingreso_transf >= 0),
  caja_salida_efectivo   numeric(14,2) NOT NULL DEFAULT 0 CHECK (caja_salida_efectivo >= 0),
  caja_salida_transf     numeric(14,2) NOT NULL DEFAULT 0 CHECK (caja_salida_transf >= 0),
  cta_cte_ingreso        numeric(14,2) NOT NULL DEFAULT 0 CHECK (cta_cte_ingreso >= 0),
  cta_cte_salida         numeric(14,2) NOT NULL DEFAULT 0 CHECK (cta_cte_salida >= 0),
  -- Categoría del gasto (la misma lista que Caja chica). Obligatoria si la fila tiene una salida real.
  categoria              text,
  subcategoria           text,
  -- TRUE = mueve dinero entre cajas (depósito al banco, retiro, envío a caja chica): no es ingreso ni
  -- gasto real y NO debe reflejarse en Contabilidad → Flujo de caja.
  interno                boolean NOT NULL DEFAULT false,
  transferencia_id       uuid REFERENCES caja_transferencia (id),
  -- Ids de los registros que esta fila generó en el ERP (Flujo de caja), para poder actualizarlos o anularlos.
  ingreso_erp_id         text,
  gasto_erp_id           text,
  -- TRUE si el reflejo en el ERP falló (ERP caído, rechazo): el dato SÍ quedó guardado aquí y se reintenta.
  erp_pendiente          boolean NOT NULL DEFAULT false,
  erp_error              text,
  created_by             text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             text,
  updated_at             timestamptz NOT NULL DEFAULT now(),
  deleted_at             timestamptz,
  deleted_by             text,
  CONSTRAINT caja_fila_con_importe CHECK (
    caja_ingreso_efectivo + caja_ingreso_transf + caja_salida_efectivo + caja_salida_transf + cta_cte_ingreso + cta_cte_salida > 0
  )
);

-- ---------------------------------------------------------------------------------------------
-- Caja chica: gastos menores (EGRESO) y dinero recibido desde la caja diaria (TRANSFERENCIA).
-- `monto` es siempre positivo; el tipo decide si suma o resta.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja_chica_mov (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ciudad            text NOT NULL REFERENCES caja_config (ciudad),
  fecha             date NOT NULL,
  tipo              text NOT NULL CHECK (tipo IN ('EGRESO', 'TRANSFERENCIA')),
  descripcion       text NOT NULL,
  persona           text NOT NULL DEFAULT '',
  categoria         text,
  subcategoria      text,
  monto             numeric(14,2) NOT NULL CHECK (monto > 0),
  origen            text NOT NULL DEFAULT 'MANUAL' CHECK (origen IN ('MANUAL', 'CAPTURA', 'TRANSFERENCIA')),
  transferencia_id  uuid REFERENCES caja_transferencia (id),
  gasto_erp_id      text,
  erp_pendiente     boolean NOT NULL DEFAULT false,
  erp_error         text,
  created_by        text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        text,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  deleted_by        text,
  CONSTRAINT caja_chica_transferencia_coherente CHECK ((tipo = 'TRANSFERENCIA') = (transferencia_id IS NOT NULL))
);

-- ---------------------------------------------------------------------------------------------
-- Adjuntos: fotos de recibos. Cuelgan de una fila o de un movimiento de caja chica (uno solo).
-- `archivo` es la ruta/clave del archivo en el almacenamiento (disco o S3), no los bytes.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja_adjunto (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fila_id        uuid REFERENCES caja_fila (id) ON DELETE CASCADE,
  movimiento_id  uuid REFERENCES caja_chica_mov (id) ON DELETE CASCADE,
  archivo        text NOT NULL,
  mime           text NOT NULL,
  bytes          integer NOT NULL CHECK (bytes > 0),
  nombre         text,
  created_by     text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT caja_adjunto_un_dueno CHECK ((fila_id IS NOT NULL)::int + (movimiento_id IS NOT NULL)::int = 1)
);

CREATE INDEX IF NOT EXISTS caja_hoja_ciudad_fecha_idx   ON caja_hoja (ciudad, fecha);
CREATE INDEX IF NOT EXISTS caja_fila_hoja_idx           ON caja_fila (hoja_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS caja_fila_transferencia_idx  ON caja_fila (transferencia_id) WHERE transferencia_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS caja_chica_ciudad_fecha_idx  ON caja_chica_mov (ciudad, fecha) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS caja_chica_transf_idx        ON caja_chica_mov (transferencia_id) WHERE transferencia_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS caja_fila_erp_pend_idx       ON caja_fila (erp_pendiente) WHERE erp_pendiente AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS caja_chica_erp_pend_idx      ON caja_chica_mov (erp_pendiente) WHERE erp_pendiente AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS caja_adjunto_fila_idx        ON caja_adjunto (fila_id);
CREATE INDEX IF NOT EXISTS caja_adjunto_mov_idx         ON caja_adjunto (movimiento_id);

-- ---------------------------------------------------------------------------------------------
-- Vistas con los saldos derivados.
--
-- v_caja_hoja_resumen: totales de cada hoja y sus saldos de apertura. El saldo anterior de una hoja
--   = saldo inicial de la ciudad + neto de todas las hojas ANTERIORES (por eso cada día nuevo arranca
--   limpio con el cierre del día previo). saldo_final = saldo_anterior + neto del día.
-- v_caja_chica_saldo: saldo actual de la caja chica de cada ciudad.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_caja_hoja_resumen AS
WITH base AS (
  SELECT
    h.id, h.ciudad, h.fecha,
    COALESCE(SUM(f.caja_ingreso_efectivo), 0)::numeric(14,2) AS ing_efectivo,
    COALESCE(SUM(f.caja_ingreso_transf),   0)::numeric(14,2) AS ing_transf,
    COALESCE(SUM(f.caja_salida_efectivo),  0)::numeric(14,2) AS sal_efectivo,
    COALESCE(SUM(f.caja_salida_transf),    0)::numeric(14,2) AS sal_transf,
    COALESCE(SUM(f.cta_cte_ingreso),       0)::numeric(14,2) AS cta_ingreso,
    COALESCE(SUM(f.cta_cte_salida),        0)::numeric(14,2) AS cta_salida
  FROM caja_hoja h
  LEFT JOIN caja_fila f ON f.hoja_id = h.id AND f.deleted_at IS NULL
  GROUP BY h.id, h.ciudad, h.fecha
),
neto AS (
  SELECT b.*,
    (b.ing_efectivo + b.ing_transf - b.sal_efectivo - b.sal_transf) AS neto_caja,
    (b.cta_ingreso - b.cta_salida) AS neto_cta
  FROM base b
)
SELECT
  n.id, n.ciudad, n.fecha,
  n.ing_efectivo, n.ing_transf, n.sal_efectivo, n.sal_transf, n.cta_ingreso, n.cta_salida,
  (c.saldo_inicial_caja + COALESCE(SUM(n.neto_caja) OVER w, 0))::numeric(14,2)    AS saldo_anterior_caja,
  (c.saldo_inicial_cta_cte + COALESCE(SUM(n.neto_cta) OVER w, 0))::numeric(14,2)  AS saldo_anterior_cta_cte,
  (c.saldo_inicial_caja + COALESCE(SUM(n.neto_caja) OVER w, 0) + n.neto_caja)::numeric(14,2)   AS saldo_final_caja,
  (c.saldo_inicial_cta_cte + COALESCE(SUM(n.neto_cta) OVER w, 0) + n.neto_cta)::numeric(14,2)  AS saldo_final_cta_cte
FROM neto n
JOIN caja_config c ON c.ciudad = n.ciudad
WINDOW w AS (PARTITION BY n.ciudad ORDER BY n.fecha ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING);

CREATE OR REPLACE VIEW v_caja_chica_saldo AS
SELECT
  c.ciudad,
  (c.saldo_inicial_caja_chica
    + COALESCE(SUM(CASE m.tipo WHEN 'TRANSFERENCIA' THEN m.monto ELSE -m.monto END), 0))::numeric(14,2) AS saldo
FROM caja_config c
LEFT JOIN caja_chica_mov m ON m.ciudad = c.ciudad AND m.deleted_at IS NULL
GROUP BY c.ciudad, c.saldo_inicial_caja_chica;

COMMIT;
