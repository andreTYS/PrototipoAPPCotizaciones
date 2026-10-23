# Migraciones: agregar tablas o columnas nuevas

Cuando haya que cambiar la base (una tabla nueva, una columna), **no** se edita `schema.sql`.
Se crea un archivo nuevo aquí, con un número que siga al último:

```
db/migraciones/001_proveedores.sql
db/migraciones/002_finanzas_pagos.sql
```

La API los aplica **una sola vez cada uno y en orden** al arrancar (queda anotado en la tabla
`migraciones`). Cada archivo corre dentro de una transacción: si algo falla, no queda a medias.

Ejemplo (`001_proveedores.sql`):

```sql
CREATE TABLE proveedores (
  id        SERIAL PRIMARY KEY,
  nombre    VARCHAR(255) NOT NULL,
  ruc       VARCHAR(20) UNIQUE,
  creado_en TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima')
);
ALTER TABLE requerimientos ADD COLUMN proveedor_id INTEGER REFERENCES proveedores(id);
```

Después de subir el archivo al servidor: `docker compose up -d --build` y listo.
Nunca cambies un archivo de migración que ya se aplicó; crea otro nuevo.
