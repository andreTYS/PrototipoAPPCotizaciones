-- Comprobantes: "Contrato / Ticket" se reemplaza por "Recibo" (Factura, Boleta, Recibo, Sin comprobante).
BEGIN;
ALTER TABLE caja_fila DROP CONSTRAINT IF EXISTS caja_fila_comprobante_check;
UPDATE caja_fila SET comprobante = 'RECIBO' WHERE comprobante = 'CONTRATO_TICKET';
ALTER TABLE caja_fila ADD CONSTRAINT caja_fila_comprobante_check CHECK (comprobante IN ('FACTURA', 'BOLETA', 'RECIBO', 'NINGUNO'));
COMMIT;
