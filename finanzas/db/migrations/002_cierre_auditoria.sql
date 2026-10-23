-- ICR Finanzas · Migración 002: cierre del día, historial de cambios y control de cambios simultáneos.
-- Solo ADITIVA (columnas y tabla nuevas). Se puede ejecutar más de una vez. Su reversa: 002_cierre_auditoria_down.sql.

BEGIN;

-- ---------------------------------------------------------------------------------------------
-- Cierre / arqueo del día. Una hoja cerrada queda bloqueada para todos (salvo que un administrador la reabra).
--   efectivo_contado = lo que la persona contó físicamente; saldo_calculado = el saldo de caja que calculó el
--   sistema en el momento del cierre; diferencia = contado − calculado (positivo sobra, negativo falta).
-- ---------------------------------------------------------------------------------------------
ALTER TABLE caja_hoja ADD COLUMN IF NOT EXISTS cerrada_en       timestamptz;
ALTER TABLE caja_hoja ADD COLUMN IF NOT EXISTS cerrada_por      text;
ALTER TABLE caja_hoja ADD COLUMN IF NOT EXISTS cerrada_por_id   text;
ALTER TABLE caja_hoja ADD COLUMN IF NOT EXISTS efectivo_contado numeric(14,2);
ALTER TABLE caja_hoja ADD COLUMN IF NOT EXISTS saldo_calculado  numeric(14,2);
ALTER TABLE caja_hoja ADD COLUMN IF NOT EXISTS diferencia       numeric(14,2);
ALTER TABLE caja_hoja ADD COLUMN IF NOT EXISTS nota_cierre      text;

-- ---------------------------------------------------------------------------------------------
-- Versión de cada registro: sube con cada cambio. Si dos personas editan lo mismo a la vez, la segunda recibe un
-- aviso (CAMBIO_CONCURRENTE) en vez de pisar el cambio de la primera.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE caja_hoja      ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;
ALTER TABLE caja_fila      ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;
ALTER TABLE caja_chica_mov ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;

-- ---------------------------------------------------------------------------------------------
-- Historial de cambios: qué, quién, cuándo y cómo estaba antes. Responde "¿por qué cambió el saldo de ayer?".
-- Nunca se edita ni se borra desde la API. `antes` es NULL cuando algo se crea y `despues` es NULL cuando se elimina.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja_auditoria (
  id          bigserial PRIMARY KEY,
  creado_en   timestamptz NOT NULL DEFAULT now(),
  usuario_id  text,
  usuario     text,
  rol         text,
  accion      text NOT NULL,   -- crear | editar | eliminar | cerrar | reabrir | anular | config | subir_foto | quitar_foto
  entidad     text NOT NULL,   -- fila | hoja | mov_chica | transferencia | config | adjunto
  entidad_id  text,
  ciudad      text,
  fecha_dia   date,            -- el día de la hoja o del movimiento al que afecta
  antes       jsonb,
  despues     jsonb,
  motivo      text
);
CREATE INDEX IF NOT EXISTS caja_auditoria_dia_idx    ON caja_auditoria (ciudad, fecha_dia, id DESC);
CREATE INDEX IF NOT EXISTS caja_auditoria_fecha_idx  ON caja_auditoria (creado_en DESC);
CREATE INDEX IF NOT EXISTS caja_auditoria_entidad_idx ON caja_auditoria (entidad, entidad_id);

COMMIT;
