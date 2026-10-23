-- Rol "finanzas": quien lleva la caja diaria y la caja chica (cierra el día, corrige días anteriores, ve alertas e historial).
-- schema.sql crea la restricción con el nombre automático usuarios_rol_check; se vuelve a crear incluyendo el rol nuevo.
ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuarios_rol_check;
ALTER TABLE usuarios ADD CONSTRAINT usuarios_rol_check CHECK (rol IN ('admin','empleado','encargado','almacen','vendedor','finanzas'));
