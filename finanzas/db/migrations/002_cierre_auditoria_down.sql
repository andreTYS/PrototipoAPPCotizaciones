-- Deshace 002_cierre_auditoria.sql. ¡BORRA el historial de cambios y los cierres! Haz un respaldo antes.
BEGIN;
DROP TABLE IF EXISTS caja_auditoria;
ALTER TABLE caja_hoja DROP COLUMN IF EXISTS cerrada_en, DROP COLUMN IF EXISTS cerrada_por, DROP COLUMN IF EXISTS cerrada_por_id,
  DROP COLUMN IF EXISTS efectivo_contado, DROP COLUMN IF EXISTS saldo_calculado, DROP COLUMN IF EXISTS diferencia,
  DROP COLUMN IF EXISTS nota_cierre, DROP COLUMN IF EXISTS version;
ALTER TABLE caja_fila DROP COLUMN IF EXISTS version;
ALTER TABLE caja_chica_mov DROP COLUMN IF EXISTS version;
COMMIT;
