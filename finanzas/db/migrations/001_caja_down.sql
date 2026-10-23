-- Deshace 001_caja.sql. ¡BORRA todos los datos de caja diaria y caja chica! Haz un respaldo antes:
--   pg_dump "$DATABASE_URL" -t 'caja_*' > respaldo_caja.sql
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/001_caja_down.sql
-- No toca ninguna tabla del ERP: solo las que creó la migración 001.

BEGIN;
DROP VIEW  IF EXISTS v_caja_chica_saldo;
DROP VIEW  IF EXISTS v_caja_hoja_resumen;
DROP TABLE IF EXISTS caja_adjunto;
DROP TABLE IF EXISTS caja_chica_mov;
DROP TABLE IF EXISTS caja_fila;
DROP TABLE IF EXISTS caja_transferencia;
DROP TABLE IF EXISTS caja_hoja;
DROP TABLE IF EXISTS caja_config;
COMMIT;
