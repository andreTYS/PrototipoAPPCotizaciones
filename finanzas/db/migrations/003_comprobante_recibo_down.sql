BEGIN;
ALTER TABLE caja_fila DROP CONSTRAINT IF EXISTS caja_fila_comprobante_check;
UPDATE caja_fila SET comprobante = 'CONTRATO_TICKET' WHERE comprobante = 'RECIBO';
ALTER TABLE caja_fila ADD CONSTRAINT caja_fila_comprobante_check CHECK (comprobante IN ('FACTURA', 'BOLETA', 'CONTRATO_TICKET', 'NINGUNO'));
COMMIT;
