-- Base de datos compartida del Cotizador ICR (PostgreSQL 14+).
-- Todos los usuarios leen y escriben aquí a través de la API. Se puede volver
-- a ejecutar sin riesgo (todo es IF NOT EXISTS). Más tablas se agregan en
-- archivos nuevos dentro de db/migraciones/ (se aplican en orden al iniciar).

CREATE TABLE IF NOT EXISTS usuarios (
  id         SERIAL PRIMARY KEY,
  usuario    VARCHAR(60)  NOT NULL UNIQUE,
  nombre     VARCHAR(120) NOT NULL,
  clave_hash VARCHAR(100) NOT NULL,
  rol        VARCHAR(20)  NOT NULL DEFAULT 'empleado'
             CHECK (rol IN ('admin','empleado','encargado','almacen','vendedor','finanzas')),
  activo     BOOLEAN      NOT NULL DEFAULT TRUE,
  creado_en  TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima')
);

CREATE TABLE IF NOT EXISTS sesiones (
  token      CHAR(64)  PRIMARY KEY,
  usuario_id INTEGER   NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  dispositivo VARCHAR(120),
  creado_en  TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima'),
  expira_en  TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sesiones_expira ON sesiones (expira_en);

CREATE TABLE IF NOT EXISTS configuracion (
  clave VARCHAR(60) PRIMARY KEY,
  valor TEXT NOT NULL,
  actualizado_en TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima')
);

-- Siguiente número de cada documento (S00001, REQ-0001, HER-0001). La API lo
-- aumenta en una sola sentencia atómica: dos personas nunca sacan el mismo.
CREATE TABLE IF NOT EXISTS correlativos (
  clave VARCHAR(40) PRIMARY KEY,
  valor INTEGER NOT NULL DEFAULT 0
);

-- Quién hizo qué y cuándo (altas, ediciones con clave, cambios de estado...).
CREATE TABLE IF NOT EXISTS bitacora (
  id          BIGSERIAL PRIMARY KEY,
  fecha       TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima'),
  usuario_id  INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  usuario     VARCHAR(120),
  accion      VARCHAR(40) NOT NULL,
  tabla       VARCHAR(40) NOT NULL,
  registro_id INTEGER,
  detalle     TEXT
);
CREATE INDEX IF NOT EXISTS idx_bitacora_registro ON bitacora (tabla, registro_id);

-- Catálogo de productos de cotización. origen: catalogo | erp | local.
-- eliminado = TRUE no borra la fila (las cotizaciones antiguas la usan).
CREATE TABLE IF NOT EXISTS productos (
  id                 SERIAL PRIMARY KEY,
  codigo_erp         VARCHAR(60) UNIQUE,
  nombre             VARCHAR(255) NOT NULL,
  categoria_producto VARCHAR(120) NOT NULL DEFAULT 'SIN CATEGORIA',
  precio_venta       NUMERIC(12,2),
  costo              NUMERIC(12,2),
  referencia_interna VARCHAR(120),
  unidad_medida      VARCHAR(40),
  archivo_imagen     VARCHAR(255),
  imagen_url         VARCHAR(500),
  origen             VARCHAR(10) NOT NULL DEFAULT 'catalogo' CHECK (origen IN ('catalogo','erp','local')),
  modificado         BOOLEAN NOT NULL DEFAULT FALSE,
  eliminado          BOOLEAN NOT NULL DEFAULT FALSE,
  clave_catalogo     TEXT,
  actualizado_en     TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima')
);
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos (categoria_producto) WHERE NOT eliminado;
CREATE INDEX IF NOT EXISTS idx_productos_nombre ON productos (lower(nombre));

-- Cotizaciones generadas. items_json guarda los productos con el nombre y el
-- precio DEL MOMENTO. version sube con cada cambio: si dos personas editan a
-- la vez, la segunda recibe un aviso en vez de pisar a la primera.
CREATE TABLE IF NOT EXISTS cotizaciones (
  id             SERIAL PRIMARY KEY,
  numero         VARCHAR(20) NOT NULL UNIQUE,
  cliente        VARCHAR(255) NOT NULL DEFAULT '',
  ruc_dni        VARCHAR(20),
  telefono       VARCHAR(40),
  vendedor       VARCHAR(120),
  banco          VARCHAR(80),
  moneda         VARCHAR(20),
  nro_cuenta     VARCHAR(60),
  cci            VARCHAR(60),
  fecha          TIMESTAMP NOT NULL,
  total          NUMERIC(12,2) NOT NULL DEFAULT 0,
  archivo_pdf    TEXT NOT NULL DEFAULT '',
  items_json     JSONB NOT NULL DEFAULT '[]',
  version        INTEGER NOT NULL DEFAULT 1,
  creado_por     INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  actualizado_en TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima'),
  actualizado_por VARCHAR(120)
);
CREATE INDEX IF NOT EXISTS idx_cotizaciones_fecha ON cotizaciones (fecha DESC);

-- Requerimientos de materiales. estado: pendiente -> aprobado -> listo -> entregado.
-- categorias_json: lo pedido por categoría; cada material guarda si ya se
-- alistó, quién y cuándo (alistado, alistado_por, fecha_alistado).
CREATE TABLE IF NOT EXISTS requerimientos (
  id               SERIAL PRIMARY KEY,
  numero           VARCHAR(20) NOT NULL UNIQUE,
  obra             VARCHAR(255) NOT NULL,
  solicitante      VARCHAR(120) NOT NULL,
  urgente          BOOLEAN NOT NULL DEFAULT FALSE,
  estado           VARCHAR(12) NOT NULL DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente','aprobado','listo','entregado')),
  fecha_creacion   TIMESTAMP NOT NULL,
  fecha_aprobacion TIMESTAMP,
  aprobado_por     VARCHAR(120),
  fecha_listo      TIMESTAMP,
  alistado_por     VARCHAR(120),
  fecha_entrega    TIMESTAMP,
  recibido_por     VARCHAR(120),
  observaciones    TEXT,
  categorias_json  JSONB NOT NULL DEFAULT '[]',
  version          INTEGER NOT NULL DEFAULT 1,
  creado_por       INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  actualizado_en   TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima'),
  actualizado_por  VARCHAR(120)
);
CREATE INDEX IF NOT EXISTS idx_requerimientos_estado ON requerimientos (estado, urgente);
CREATE INDEX IF NOT EXISTS idx_requerimientos_fecha ON requerimientos (fecha_creacion DESC);

-- Salidas de herramientas (por checklist o por maleta).
-- estado: registrado -> pendiente (almacén confirmó la salida) -> conforme (devolución).
CREATE TABLE IF NOT EXISTS checklists_herramientas (
  id                        SERIAL PRIMARY KEY,
  numero                    VARCHAR(20) NOT NULL UNIQUE,
  obra                      VARCHAR(255) NOT NULL,
  responsable               VARCHAR(120) NOT NULL,
  maleta                    VARCHAR(120),
  estado                    VARCHAR(12) NOT NULL DEFAULT 'registrado'
                            CHECK (estado IN ('registrado','pendiente','conforme')),
  fecha_salida              TIMESTAMP NOT NULL,
  fecha_confirmacion_salida TIMESTAMP,
  salida_confirmada_por     VARCHAR(120),
  fecha_devolucion          TIMESTAMP,
  encargado                 VARCHAR(120),
  observaciones             TEXT,
  observaciones_devolucion  TEXT,
  categorias_json           JSONB NOT NULL DEFAULT '[]',
  version                   INTEGER NOT NULL DEFAULT 1,
  creado_por                INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  actualizado_en            TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima'),
  actualizado_por           VARCHAR(120)
);
CREATE INDEX IF NOT EXISTS idx_herramientas_estado ON checklists_herramientas (estado);
CREATE INDEX IF NOT EXISTS idx_herramientas_fecha ON checklists_herramientas (fecha_salida DESC);

-- Listas editables del checklist (materiales con precio; herramientas).
CREATE TABLE IF NOT EXISTS checklist_catalogo (
  id        SERIAL PRIMARY KEY,
  tipo      VARCHAR(12) NOT NULL CHECK (tipo IN ('materiales','herramientas')),
  categoria VARCHAR(120) NOT NULL,
  nombre    VARCHAR(255) NOT NULL,
  unidad    VARCHAR(40),
  fecha     TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'America/Lima'),
  precio    NUMERIC(12,2),
  orden     INTEGER NOT NULL DEFAULT 0,
  base      BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_catalogo_tipo_orden ON checklist_catalogo (tipo, orden, id);

CREATE TABLE IF NOT EXISTS maletas (
  id     SERIAL PRIMARY KEY,
  nombre VARCHAR(120) NOT NULL,
  orden  INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS maleta_items (
  id        SERIAL PRIMARY KEY,
  maleta_id INTEGER NOT NULL REFERENCES maletas(id) ON DELETE CASCADE,
  nivel     VARCHAR(80) NOT NULL,
  nombre    VARCHAR(255) NOT NULL,
  imagen    VARCHAR(255),
  orden     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_maleta_items ON maleta_items (maleta_id, orden, id);

-- -----------------------------------------------------------------------------
-- Vistas planas (una fila por ítem) para reportes y para la vista general.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_requerimiento_items AS
SELECT r.id AS requerimiento_id, r.numero, r.obra, r.estado,
       c->>'nombre' AS categoria, i->>'texto' AS material,
       (i->>'cantidad')::int AS cantidad, i->>'unidad' AS unidad,
       (i->>'precio')::numeric AS precio_unitario,
       COALESCE((i->>'alistado')::boolean, FALSE) AS alistado,
       i->>'alistado_por' AS alistado_por, (i->>'fecha_alistado')::timestamp AS fecha_alistado,
       COALESCE((i->>'agregado_despues')::boolean, FALSE) AS agregado_despues
FROM requerimientos r,
     jsonb_array_elements(r.categorias_json) c,
     jsonb_array_elements(c->'items') i;

CREATE OR REPLACE VIEW v_herramientas_items AS
SELECT h.id AS checklist_id, h.numero, h.obra, h.responsable, h.estado,
       c->>'nombre' AS categoria, i->>'texto' AS herramienta,
       (i->>'cantidad')::int AS cantidad,
       (i->>'salio')::boolean AS salio, (i->>'volvio')::boolean AS volvio,
       COALESCE((i->>'agregado_despues')::boolean, FALSE) AS agregado_despues
FROM checklists_herramientas h,
     jsonb_array_elements(h.categorias_json) c,
     jsonb_array_elements(c->'items') i;

CREATE OR REPLACE VIEW v_cotizacion_items AS
SELECT q.id AS cotizacion_id, q.numero, q.cliente, q.fecha,
       i->>'nombre' AS producto, (i->>'cantidad')::numeric AS cantidad,
       (i->>'precio_unitario')::numeric AS precio_unitario
FROM cotizaciones q, jsonb_array_elements(q.items_json) i;

INSERT INTO correlativos (clave, valor) VALUES
  ('cotizacion', 0), ('requerimiento', 0), ('herramientas', 0)
ON CONFLICT (clave) DO NOTHING;
