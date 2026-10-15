-- =============================================================================
-- Base de datos del Cotizador ICR para varios dispositivos
-- PostgreSQL 16 (mismo motor que ya usa el ERP de Inversiones ICR, en su
-- propio contenedor Docker aparte).
--
-- Los celulares y navegadores NO se conectan directo a Postgres: hablan con
-- una API en PHP (su propio contenedor), y la API lee y escribe en estas
-- tablas. Así todos ven lo mismo, los números de documento no se repiten
-- (S00001, REQ-0001, HER-0001) y cada cambio queda con su fecha y su autor.
--
-- Convertido desde el estructura.sql original (MySQL/MariaDB, pensado para
-- Hostinger compartido) al pasar este backend a Docker + Postgres en el VPS:
--   AUTO_INCREMENT      -> SERIAL / BIGSERIAL
--   INT UNSIGNED        -> INTEGER (Postgres no tiene UNSIGNED)
--   ENUM(...)           -> TEXT + CHECK (...)
--   TINYINT(1) 0/1      -> SMALLINT 0/1 (se deja igual a propósito: así el
--                          PHP que ya estaba probado contra MySQL no cambia)
--   DATETIME            -> TIMESTAMP (hora local, igual que antes — la app
--                          fija America/Lima tanto en PHP como en la sesión
--                          de Postgres, ver config.php)
--   INDEX dentro de CREATE TABLE -> CREATE INDEX aparte (Postgres no admite
--                          INDEX inline)
--   ENGINE=InnoDB / CHARSET -> no existen en Postgres, se quitan
--
-- Qué guarda cada grupo de tablas:
--   Acceso ........ usuarios, sesiones, configuracion
--   Productos ..... productos (catálogo de cotización)
--   Cotizaciones .. cotizaciones, cotizacion_items
--   Almacén ....... requerimientos (+items, con el alistado por material),
--                   checklists_herramientas (+items)
--   Listas ........ checklist_catalogo (materiales y herramientas), maletas (+items)
--   Control ....... correlativos, bitacora (incluye cada edición con la clave)
--
-- Las fotos no van en la base: se guardan como archivos en el servidor
-- (carpeta uploads/) y aquí solo queda su ruta relativa.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ACCESO
-- -----------------------------------------------------------------------------

-- Personas que entran a la app. rol: admin | vendedor | jefe_obra | almacen.
-- La clave se guarda cifrada (hash), nunca en texto.
CREATE TABLE IF NOT EXISTS usuarios (
  id          SERIAL PRIMARY KEY,
  usuario     VARCHAR(60)  NOT NULL UNIQUE,
  nombre      VARCHAR(120) NOT NULL,
  clave_hash  VARCHAR(255) NOT NULL,
  rol         TEXT NOT NULL DEFAULT 'vendedor' CHECK (rol IN ('admin','vendedor','jefe_obra','almacen')),
  activo      SMALLINT     NOT NULL DEFAULT 1,
  creado_en   TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Una sesión por dispositivo con sesión iniciada. Al desactivar a un usuario
-- se borran sus sesiones y queda fuera en todos sus dispositivos.
CREATE TABLE IF NOT EXISTS sesiones (
  token       CHAR(64)  PRIMARY KEY,
  usuario_id  INTEGER   NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  dispositivo VARCHAR(120) NULL,
  creado_en   TIMESTAMP NOT NULL DEFAULT NOW(),
  expira_en   TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sesiones_expira ON sesiones (expira_en);

-- Ajustes del sistema (clave → valor). Ej.: 'codigo_jefe_obra' con el código
-- que se pide para aprobar requerimientos (se valida en el servidor, no en el
-- celular), 'igv' = 0.18, 'zona_horaria' = America/Lima.
CREATE TABLE IF NOT EXISTS configuracion (
  clave          VARCHAR(60)  PRIMARY KEY,
  valor          VARCHAR(255) NOT NULL,
  actualizado_en TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- CONTROL
-- -----------------------------------------------------------------------------

-- Siguiente número de cada documento. El servidor lo aumenta dentro de una
-- transacción (UPDATE ... SET valor = valor + 1, luego SELECT), así dos
-- dispositivos nunca sacan el mismo número. clave: 'cotizacion',
-- 'requerimiento', 'herramientas'.
CREATE TABLE IF NOT EXISTS correlativos (
  clave  VARCHAR(40) PRIMARY KEY,
  valor  INTEGER     NOT NULL DEFAULT 0
);

-- Quién hizo qué y cuándo: cambios en Configuración (precios, productos,
-- maletas, listas), aprobaciones, entregas, eliminaciones. Como todo se puede
-- modificar desde varios dispositivos, aquí queda el rastro.
CREATE TABLE IF NOT EXISTS bitacora (
  id          BIGSERIAL PRIMARY KEY,
  fecha       TIMESTAMP   NOT NULL DEFAULT NOW(),
  usuario_id  INTEGER     NULL REFERENCES usuarios(id) ON DELETE SET NULL,
  accion      VARCHAR(40) NOT NULL,          -- crear | editar | eliminar | aprobar | confirmar...
  tabla       VARCHAR(40) NOT NULL,
  registro_id INTEGER     NULL,
  detalle     TEXT        NULL               -- antes/después, en texto o JSON
);
CREATE INDEX IF NOT EXISTS idx_bitacora_tabla ON bitacora (tabla, registro_id);
CREATE INDEX IF NOT EXISTS idx_bitacora_fecha ON bitacora (fecha);

-- -----------------------------------------------------------------------------
-- PRODUCTOS (catálogo de cotización)
-- -----------------------------------------------------------------------------

-- origen: catalogo (los 800 del Excel) | erp (traídos del ERP de la empresa) |
-- local (agregados desde la app). Todos se pueden editar; "activo" = 0 es
-- eliminado (no se borra la fila para no romper cotizaciones antiguas).
-- codigo_erp enlaza el producto con el ERP: la sincronización actualiza por
-- ese código sin tocar lo demás.
CREATE TABLE IF NOT EXISTS productos (
  id                 SERIAL        PRIMARY KEY,
  codigo_erp         VARCHAR(60)   NULL UNIQUE,
  nombre             VARCHAR(255)  NOT NULL,
  categoria          VARCHAR(120)  NOT NULL,
  precio_venta       DECIMAL(12,2) NULL,
  costo              DECIMAL(12,2) NULL,
  referencia_interna VARCHAR(120)  NULL,
  unidad_medida      VARCHAR(40)   NULL,
  imagen             VARCHAR(255)  NULL,       -- ruta relativa en uploads/ (ej. productos/MPPT_100_20.jpg)
  origen             TEXT NOT NULL DEFAULT 'local' CHECK (origen IN ('catalogo','erp','local')),
  activo             SMALLINT      NOT NULL DEFAULT 1,
  creado_por         INTEGER       NULL REFERENCES usuarios(id) ON DELETE SET NULL,
  creado_en          TIMESTAMP     NOT NULL DEFAULT NOW(),
  actualizado_en     TIMESTAMP     NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos (categoria);
CREATE INDEX IF NOT EXISTS idx_productos_nombre ON productos (nombre);
CREATE INDEX IF NOT EXISTS idx_productos_referencia ON productos (referencia_interna);

-- -----------------------------------------------------------------------------
-- COTIZACIONES
-- -----------------------------------------------------------------------------

-- Cabecera de cada cotización (el historial). numero: S00001, S00002...
CREATE TABLE IF NOT EXISTS cotizaciones (
  id          SERIAL        PRIMARY KEY,
  numero      VARCHAR(20)   NOT NULL UNIQUE,
  cliente     VARCHAR(255)  NOT NULL DEFAULT '',
  ruc_dni     VARCHAR(20)   NULL,
  telefono    VARCHAR(40)   NULL,
  vendedor    VARCHAR(120)  NULL,
  banco       VARCHAR(80)   NULL,
  moneda      VARCHAR(20)   NULL,
  nro_cuenta  VARCHAR(60)   NULL,
  cci         VARCHAR(60)   NULL,
  total       DECIMAL(12,2) NOT NULL DEFAULT 0,
  fecha       TIMESTAMP     NOT NULL,
  creado_por  INTEGER       NULL REFERENCES usuarios(id) ON DELETE SET NULL,
  version     INTEGER       NOT NULL DEFAULT 1,           -- sube con cada edición
  editado_en  TIMESTAMP     NULL,                         -- última edición con la clave
  editado_por VARCHAR(120)  NULL
);
CREATE INDEX IF NOT EXISTS idx_cotizaciones_fecha ON cotizaciones (fecha);
CREATE INDEX IF NOT EXISTS idx_cotizaciones_cliente ON cotizaciones (cliente);

-- Un renglón por producto cotizado. Guarda nombre, precio y foto DEL MOMENTO:
-- si mañana cambia el catálogo, la cotización antigua sigue igual.
CREATE TABLE IF NOT EXISTS cotizacion_items (
  id                  SERIAL        PRIMARY KEY,
  cotizacion_id       INTEGER       NOT NULL REFERENCES cotizaciones(id) ON DELETE CASCADE,
  orden               SMALLINT      NOT NULL DEFAULT 0,
  producto_id         INTEGER       NULL REFERENCES productos(id) ON DELETE SET NULL,
  nombre              VARCHAR(255)  NOT NULL,
  referencia_interna  VARCHAR(120)  NULL,
  cantidad            DECIMAL(12,2) NOT NULL,
  precio_unitario     DECIMAL(12,2) NOT NULL,
  unidad_medida       VARCHAR(40)   NULL,
  imagen              VARCHAR(255)  NULL,
  agregado_en_edicion SMALLINT      NOT NULL DEFAULT 0    -- se agregó después, editando
);

-- -----------------------------------------------------------------------------
-- LISTAS DEL CHECKLIST (materiales y herramientas) — se editan en Configuración
-- -----------------------------------------------------------------------------

-- Todo lo que aparece al armar un requerimiento (tipo = materiales, con su
-- precio por defecto) o un checklist de herramientas (tipo = herramientas).
-- Las categorías salen en el orden de su primer ítem; dentro, por "orden".
-- base = 1: viene de la lista de la empresa; 0: se agregó desde la app.
CREATE TABLE IF NOT EXISTS checklist_catalogo (
  id             SERIAL        PRIMARY KEY,
  tipo           TEXT NOT NULL CHECK (tipo IN ('materiales','herramientas')),
  categoria      VARCHAR(120)  NOT NULL,
  nombre         VARCHAR(255)  NOT NULL,
  unidad         VARCHAR(40)   NULL,
  precio         DECIMAL(12,2) NULL,                 -- solo materiales
  orden          INTEGER       NOT NULL DEFAULT 0,
  base           SMALLINT      NOT NULL DEFAULT 0,
  activo         SMALLINT      NOT NULL DEFAULT 1,
  creado_en      TIMESTAMP     NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMP     NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_catalogo_tipo_orden ON checklist_catalogo (tipo, orden);

-- Maletas de herramientas ya armadas (Maleta 1, Maleta 2, TLD-AML...).
CREATE TABLE IF NOT EXISTS maletas (
  id             SERIAL       PRIMARY KEY,
  nombre         VARCHAR(120) NOT NULL,
  orden          SMALLINT     NOT NULL DEFAULT 0,
  activo         SMALLINT     NOT NULL DEFAULT 1,
  actualizado_en TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Lo que lleva cada maleta, por nivel, con su foto.
CREATE TABLE IF NOT EXISTS maleta_items (
  id        SERIAL       PRIMARY KEY,
  maleta_id INTEGER      NOT NULL REFERENCES maletas(id) ON DELETE CASCADE,
  nivel     VARCHAR(80)  NOT NULL,                 -- Primer nivel, Segundo nivel...
  nombre    VARCHAR(255) NOT NULL,
  imagen    VARCHAR(255) NULL,                     -- ruta relativa en uploads/
  orden     INTEGER      NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_maleta_orden ON maleta_items (maleta_id, orden);

-- -----------------------------------------------------------------------------
-- ALMACÉN: REQUERIMIENTOS DE MATERIALES
-- -----------------------------------------------------------------------------

-- estado: pendiente (espera al jefe de obra) → aprobado (con su código; el
-- almacenero lo ve como "pendiente de alistar") → listo (el almacenero lo
-- alistó) → entregado. Cada paso guarda quién y cuándo.
-- version sube con cada cambio: si dos dispositivos tocan el mismo
-- requerimiento a la vez, el segundo recibe un aviso en vez de pisar al primero
-- (UPDATE ... WHERE id = ? AND version = ?).
CREATE TABLE IF NOT EXISTS requerimientos (
  id               SERIAL       PRIMARY KEY,
  numero           VARCHAR(20)  NOT NULL UNIQUE,         -- REQ-0001
  obra             VARCHAR(255) NOT NULL,
  solicitante      VARCHAR(120) NOT NULL,
  urgente          SMALLINT     NOT NULL DEFAULT 0,
  estado           TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobado','listo','entregado')),
  observaciones    TEXT         NULL,
  fecha_creacion   TIMESTAMP    NOT NULL,
  fecha_aprobacion TIMESTAMP    NULL,
  aprobado_por     VARCHAR(120) NULL,
  fecha_listo      TIMESTAMP    NULL,
  alistado_por     VARCHAR(120) NULL,
  fecha_entrega    TIMESTAMP    NULL,
  recibido_por     VARCHAR(120) NULL,
  total_estimado   DECIMAL(12,2) NOT NULL DEFAULT 0,
  version          INTEGER      NOT NULL DEFAULT 1,
  editado_en       TIMESTAMP    NULL,                   -- última edición con la clave
  editado_por      VARCHAR(120) NULL,
  creado_por       INTEGER      NULL REFERENCES usuarios(id) ON DELETE SET NULL,
  actualizado_en   TIMESTAMP    NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_requerimientos_estado ON requerimientos (estado, urgente);
CREATE INDEX IF NOT EXISTS idx_requerimientos_fecha ON requerimientos (fecha_creacion);

-- Materiales pedidos, por categoría, con la cantidad y el precio unitario
-- (el de la lista por defecto o el que se cambió en ese requerimiento).
CREATE TABLE IF NOT EXISTS requerimiento_items (
  id                  SERIAL       PRIMARY KEY,
  requerimiento_id    INTEGER      NOT NULL REFERENCES requerimientos(id) ON DELETE CASCADE,
  orden               SMALLINT     NOT NULL DEFAULT 0,
  categoria           VARCHAR(120) NOT NULL,
  nombre              VARCHAR(255) NOT NULL,
  cantidad            INTEGER      NOT NULL,
  unidad              VARCHAR(40)  NULL,
  precio_unitario     DECIMAL(12,2) NULL,
  es_extra            SMALLINT     NOT NULL DEFAULT 0,    -- agregado solo a este requerimiento
  es_producto         SMALLINT     NOT NULL DEFAULT 0,    -- vino del catálogo de productos
  alistado            SMALLINT     NOT NULL DEFAULT 0,    -- almacén ya lo alistó
  alistado_por        VARCHAR(120) NULL,                  -- quién lo alistó
  fecha_alistado      TIMESTAMP    NULL,
  agregado_en_edicion SMALLINT     NOT NULL DEFAULT 0     -- se agregó después, editando
);

-- -----------------------------------------------------------------------------
-- ALMACÉN: SALIDAS DE HERRAMIENTAS (checklist o maleta)
-- -----------------------------------------------------------------------------

-- estado: registrado → pendiente (almacén confirmó la salida; esperan
-- devolución) → conforme (el encargado confirmó la devolución).
-- Si salió una maleta, maleta_id apunta a ella y maleta_nombre guarda su
-- nombre del momento (por si luego se renombra o elimina).
CREATE TABLE IF NOT EXISTS checklists_herramientas (
  id                        SERIAL       PRIMARY KEY,
  numero                    VARCHAR(20)  NOT NULL UNIQUE,   -- HER-0001
  obra                      VARCHAR(255) NOT NULL,
  responsable               VARCHAR(120) NOT NULL,          -- quien se las lleva
  maleta_id                 INTEGER      NULL REFERENCES maletas(id) ON DELETE SET NULL,
  maleta_nombre             VARCHAR(120) NULL,
  estado                    TEXT NOT NULL DEFAULT 'registrado' CHECK (estado IN ('registrado','pendiente','conforme')),
  observaciones             TEXT         NULL,
  fecha_registro            TIMESTAMP    NOT NULL,
  fecha_confirmacion_salida TIMESTAMP    NULL,
  salida_confirmada_por     VARCHAR(120) NULL,              -- quien entrega en almacén
  fecha_devolucion          TIMESTAMP    NULL,
  encargado                 VARCHAR(120) NULL,              -- quien recibe la devolución
  observaciones_devolucion  TEXT         NULL,
  version                   INTEGER      NOT NULL DEFAULT 1,
  editado_en                TIMESTAMP    NULL,              -- última edición con la clave
  editado_por               VARCHAR(120) NULL,
  creado_por                INTEGER      NULL REFERENCES usuarios(id) ON DELETE SET NULL,
  actualizado_en            TIMESTAMP    NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_herramientas_estado ON checklists_herramientas (estado);
CREATE INDEX IF NOT EXISTS idx_herramientas_fecha ON checklists_herramientas (fecha_registro);

-- Cada herramienta de la salida. salio / volvio = lo marcado herramienta por
-- herramienta al confirmar la salida y la devolución (columnas SALIDA /
-- ENTRADA del formato en papel): NULL = aún sin revisar, 1 = sí, 0 = no
-- (no salió / no volvió). Los faltantes salen de aquí.
CREATE TABLE IF NOT EXISTS checklist_herramientas_items (
  id                  SERIAL       PRIMARY KEY,
  checklist_id        INTEGER      NOT NULL REFERENCES checklists_herramientas(id) ON DELETE CASCADE,
  orden               SMALLINT     NOT NULL DEFAULT 0,
  categoria           VARCHAR(120) NOT NULL,                      -- categoría o nivel de la maleta
  nombre              VARCHAR(255) NOT NULL,
  cantidad            INTEGER      NOT NULL DEFAULT 1,
  unidad              VARCHAR(40)  NULL,
  imagen              VARCHAR(255) NULL,
  salio               SMALLINT     NULL,
  volvio              SMALLINT     NULL,
  es_extra            SMALLINT     NOT NULL DEFAULT 0,
  es_producto         SMALLINT     NOT NULL DEFAULT 0,
  agregado_en_edicion SMALLINT     NOT NULL DEFAULT 0            -- se agregó después, editando
);

-- Contadores iniciales de los números de documento.
INSERT INTO correlativos (clave, valor) VALUES
  ('cotizacion', 0), ('requerimiento', 0), ('herramientas', 0)
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor) VALUES
  ('igv', '0.18'),
  ('zona_horaria', 'America/Lima')
ON CONFLICT (clave) DO NOTHING;

-- Clave para EDITAR cotizaciones, requerimientos y salidas de herramientas
-- (agregar productos, materiales o herramientas olvidados). Se guarda cifrada
-- (bcrypt) y vale "1234"; cámbiala desde la app o con:
--   UPDATE configuracion SET valor = '<password_hash de PHP>' WHERE clave = 'clave_edicion';
INSERT INTO configuracion (clave, valor) VALUES
  ('clave_edicion', '$2y$12$iiv3c3uZo5p7lEnS76KQseP69gWYfQ0mY627YZUfTrjj09yKyxAMe')
ON CONFLICT (clave) DO NOTHING;
-- El código del jefe de obra y el primer administrador los crea el instalador.
