-- =============================================================================
-- Base de datos del Cotizador ICR para varios dispositivos
-- MySQL 5.7+ / MariaDB 10.3+ (la de Hostinger). Codificación utf8mb4.
--
-- Los celulares y navegadores NO se conectan directo a MySQL: hablan con una
-- API en el servidor (PHP en el mismo Hostinger), y la API lee y escribe en
-- estas tablas. Así todos ven lo mismo, los números de documento no se repiten
-- (S00001, REQ-0001, HER-0001) y cada cambio queda con su fecha y su autor.
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

SET NAMES utf8mb4;

-- -----------------------------------------------------------------------------
-- ACCESO
-- -----------------------------------------------------------------------------

-- Personas que entran a la app. rol: admin | vendedor | jefe_obra | almacen.
-- La clave se guarda cifrada (hash), nunca en texto.
CREATE TABLE IF NOT EXISTS usuarios (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario     VARCHAR(60)  NOT NULL UNIQUE,
  nombre      VARCHAR(120) NOT NULL,
  clave_hash  VARCHAR(255) NOT NULL,
  rol         ENUM('admin','vendedor','jefe_obra','almacen') NOT NULL DEFAULT 'vendedor',
  activo      TINYINT(1)   NOT NULL DEFAULT 1,
  creado_en   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Una sesión por dispositivo con sesión iniciada. Al desactivar a un usuario
-- se borran sus sesiones y queda fuera en todos sus dispositivos.
CREATE TABLE IF NOT EXISTS sesiones (
  token       CHAR(64)     PRIMARY KEY,
  usuario_id  INT UNSIGNED NOT NULL,
  dispositivo VARCHAR(120) NULL,
  creado_en   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expira_en   DATETIME     NOT NULL,
  CONSTRAINT fk_sesion_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE,
  INDEX idx_sesiones_expira (expira_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Ajustes del sistema (clave → valor). Ej.: 'codigo_jefe_obra' con el código
-- que se pide para aprobar requerimientos (se valida en el servidor, no en el
-- celular), 'igv' = 0.18, 'zona_horaria' = America/Lima.
CREATE TABLE IF NOT EXISTS configuracion (
  clave          VARCHAR(60)  PRIMARY KEY,
  valor          VARCHAR(255) NOT NULL,
  actualizado_en DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- CONTROL
-- -----------------------------------------------------------------------------

-- Siguiente número de cada documento. El servidor lo aumenta dentro de una
-- transacción (UPDATE ... valor = LAST_INSERT_ID(valor + 1)), así dos
-- dispositivos nunca sacan el mismo número. clave: 'cotizacion',
-- 'requerimiento', 'herramientas'.
CREATE TABLE IF NOT EXISTS correlativos (
  clave  VARCHAR(40)   PRIMARY KEY,
  valor  INT UNSIGNED  NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Quién hizo qué y cuándo: cambios en Configuración (precios, productos,
-- maletas, listas), aprobaciones, entregas, eliminaciones. Como todo se puede
-- modificar desde varios dispositivos, aquí queda el rastro.
CREATE TABLE IF NOT EXISTS bitacora (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fecha       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_id  INT UNSIGNED NULL,
  accion      VARCHAR(40)  NOT NULL,          -- crear | editar | eliminar | aprobar | confirmar...
  tabla       VARCHAR(40)  NOT NULL,
  registro_id INT UNSIGNED NULL,
  detalle     TEXT         NULL,              -- antes/después, en texto o JSON
  CONSTRAINT fk_bitacora_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_bitacora_tabla (tabla, registro_id),
  INDEX idx_bitacora_fecha (fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- PRODUCTOS (catálogo de cotización)
-- -----------------------------------------------------------------------------

-- origen: catalogo (los 800 del Excel) | erp (traídos del ERP de la empresa) |
-- local (agregados desde la app). Todos se pueden editar; "activo" = 0 es
-- eliminado (no se borra la fila para no romper cotizaciones antiguas).
-- codigo_erp enlaza el producto con el ERP: la sincronización actualiza por
-- ese código sin tocar lo demás.
CREATE TABLE IF NOT EXISTS productos (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo_erp         VARCHAR(60)   NULL UNIQUE,
  nombre             VARCHAR(255)  NOT NULL,
  categoria          VARCHAR(120)  NOT NULL,
  precio_venta       DECIMAL(12,2) NULL,
  costo              DECIMAL(12,2) NULL,
  referencia_interna VARCHAR(120)  NULL,
  unidad_medida      VARCHAR(40)   NULL,
  imagen             VARCHAR(255)  NULL,       -- ruta relativa en uploads/ (ej. productos/MPPT_100_20.jpg)
  origen             ENUM('catalogo','erp','local') NOT NULL DEFAULT 'local',
  activo             TINYINT(1)    NOT NULL DEFAULT 1,
  creado_por         INT UNSIGNED  NULL,
  creado_en          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_producto_usuario FOREIGN KEY (creado_por) REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_productos_categoria (categoria),
  INDEX idx_productos_nombre (nombre(100)),
  INDEX idx_productos_referencia (referencia_interna)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- COTIZACIONES
-- -----------------------------------------------------------------------------

-- Cabecera de cada cotización (el historial). numero: S00001, S00002...
CREATE TABLE IF NOT EXISTS cotizaciones (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
  fecha       DATETIME      NOT NULL,
  creado_por  INT UNSIGNED  NULL,
  version     INT UNSIGNED  NOT NULL DEFAULT 1,           -- sube con cada edición
  editado_en  DATETIME      NULL,                         -- última edición con la clave
  editado_por VARCHAR(120)  NULL,
  CONSTRAINT fk_cotizacion_usuario FOREIGN KEY (creado_por) REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_cotizaciones_fecha (fecha),
  INDEX idx_cotizaciones_cliente (cliente(100))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Un renglón por producto cotizado. Guarda nombre, precio y foto DEL MOMENTO:
-- si mañana cambia el catálogo, la cotización antigua sigue igual.
CREATE TABLE IF NOT EXISTS cotizacion_items (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  cotizacion_id      INT UNSIGNED  NOT NULL,
  orden              SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  producto_id        INT UNSIGNED  NULL,
  nombre             VARCHAR(255)  NOT NULL,
  referencia_interna VARCHAR(120)  NULL,
  cantidad           DECIMAL(12,2) NOT NULL,
  precio_unitario    DECIMAL(12,2) NOT NULL,
  unidad_medida      VARCHAR(40)   NULL,
  imagen             VARCHAR(255)  NULL,
  agregado_en_edicion TINYINT(1)   NOT NULL DEFAULT 0,    -- se agregó después, editando
  CONSTRAINT fk_item_cotizacion FOREIGN KEY (cotizacion_id) REFERENCES cotizaciones(id) ON DELETE CASCADE,
  CONSTRAINT fk_item_producto   FOREIGN KEY (producto_id)   REFERENCES productos(id)    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- LISTAS DEL CHECKLIST (materiales y herramientas) — se editan en Configuración
-- -----------------------------------------------------------------------------

-- Todo lo que aparece al armar un requerimiento (tipo = materiales, con su
-- precio por defecto) o un checklist de herramientas (tipo = herramientas).
-- Las categorías salen en el orden de su primer ítem; dentro, por "orden".
-- base = 1: viene de la lista de la empresa; 0: se agregó desde la app.
CREATE TABLE IF NOT EXISTS checklist_catalogo (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tipo           ENUM('materiales','herramientas') NOT NULL,
  categoria      VARCHAR(120)  NOT NULL,
  nombre         VARCHAR(255)  NOT NULL,
  unidad         VARCHAR(40)   NULL,
  precio         DECIMAL(12,2) NULL,                 -- solo materiales
  orden          INT UNSIGNED  NOT NULL DEFAULT 0,
  base           TINYINT(1)    NOT NULL DEFAULT 0,
  activo         TINYINT(1)    NOT NULL DEFAULT 1,
  creado_en      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_catalogo_tipo_orden (tipo, orden)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Maletas de herramientas ya armadas (Maleta 1, Maleta 2, TLD-AML...).
CREATE TABLE IF NOT EXISTS maletas (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre         VARCHAR(120) NOT NULL,
  orden          SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  activo         TINYINT(1)   NOT NULL DEFAULT 1,
  actualizado_en DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Lo que lleva cada maleta, por nivel, con su foto.
CREATE TABLE IF NOT EXISTS maleta_items (
  id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  maleta_id INT UNSIGNED  NOT NULL,
  nivel     VARCHAR(80)   NOT NULL,                 -- Primer nivel, Segundo nivel...
  nombre    VARCHAR(255)  NOT NULL,
  imagen    VARCHAR(255)  NULL,                     -- ruta relativa en uploads/
  orden     INT UNSIGNED  NOT NULL DEFAULT 0,
  CONSTRAINT fk_maleta_item FOREIGN KEY (maleta_id) REFERENCES maletas(id) ON DELETE CASCADE,
  INDEX idx_maleta_orden (maleta_id, orden)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  numero           VARCHAR(20)  NOT NULL UNIQUE,         -- REQ-0001
  obra             VARCHAR(255) NOT NULL,
  solicitante      VARCHAR(120) NOT NULL,
  urgente          TINYINT(1)   NOT NULL DEFAULT 0,
  estado           ENUM('pendiente','aprobado','listo','entregado') NOT NULL DEFAULT 'pendiente',
  observaciones    TEXT         NULL,
  fecha_creacion   DATETIME     NOT NULL,
  fecha_aprobacion DATETIME     NULL,
  aprobado_por     VARCHAR(120) NULL,
  fecha_listo      DATETIME     NULL,
  alistado_por     VARCHAR(120) NULL,
  fecha_entrega    DATETIME     NULL,
  recibido_por     VARCHAR(120) NULL,
  total_estimado   DECIMAL(12,2) NOT NULL DEFAULT 0,
  version          INT UNSIGNED NOT NULL DEFAULT 1,
  editado_en       DATETIME     NULL,                   -- última edición con la clave
  editado_por      VARCHAR(120) NULL,
  creado_por       INT UNSIGNED NULL,
  actualizado_en   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_requerimiento_usuario FOREIGN KEY (creado_por) REFERENCES usuarios(id) ON DELETE SET NULL,
  INDEX idx_requerimientos_estado (estado, urgente),
  INDEX idx_requerimientos_fecha (fecha_creacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Materiales pedidos, por categoría, con la cantidad y el precio unitario
-- (el de la lista por defecto o el que se cambió en ese requerimiento).
CREATE TABLE IF NOT EXISTS requerimiento_items (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  requerimiento_id INT UNSIGNED  NOT NULL,
  orden            SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  categoria        VARCHAR(120)  NOT NULL,
  nombre           VARCHAR(255)  NOT NULL,
  cantidad         INT UNSIGNED  NOT NULL,
  unidad           VARCHAR(40)   NULL,
  precio_unitario  DECIMAL(12,2) NULL,
  es_extra         TINYINT(1)    NOT NULL DEFAULT 0,    -- agregado solo a este requerimiento
  es_producto      TINYINT(1)    NOT NULL DEFAULT 0,    -- vino del catálogo de productos
  alistado         TINYINT(1)    NOT NULL DEFAULT 0,    -- almacén ya lo alistó
  alistado_por     VARCHAR(120)  NULL,                  -- quién lo alistó
  fecha_alistado   DATETIME      NULL,
  agregado_en_edicion TINYINT(1) NOT NULL DEFAULT 0,    -- se agregó después, editando
  CONSTRAINT fk_item_requerimiento FOREIGN KEY (requerimiento_id) REFERENCES requerimientos(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- ALMACÉN: SALIDAS DE HERRAMIENTAS (checklist o maleta)
-- -----------------------------------------------------------------------------

-- estado: registrado → pendiente (almacén confirmó la salida; esperan
-- devolución) → conforme (el encargado confirmó la devolución).
-- Si salió una maleta, maleta_id apunta a ella y maleta_nombre guarda su
-- nombre del momento (por si luego se renombra o elimina).
CREATE TABLE IF NOT EXISTS checklists_herramientas (
  id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  numero                    VARCHAR(20)  NOT NULL UNIQUE,   -- HER-0001
  obra                      VARCHAR(255) NOT NULL,
  responsable               VARCHAR(120) NOT NULL,          -- quien se las lleva
  maleta_id                 INT UNSIGNED NULL,
  maleta_nombre             VARCHAR(120) NULL,
  estado                    ENUM('registrado','pendiente','conforme') NOT NULL DEFAULT 'registrado',
  observaciones             TEXT         NULL,
  fecha_registro            DATETIME     NOT NULL,
  fecha_confirmacion_salida DATETIME     NULL,
  salida_confirmada_por     VARCHAR(120) NULL,              -- quien entrega en almacén
  fecha_devolucion          DATETIME     NULL,
  encargado                 VARCHAR(120) NULL,              -- quien recibe la devolución
  observaciones_devolucion  TEXT         NULL,
  version                   INT UNSIGNED NOT NULL DEFAULT 1,
  editado_en                DATETIME     NULL,              -- última edición con la clave
  editado_por               VARCHAR(120) NULL,
  creado_por                INT UNSIGNED NULL,
  actualizado_en            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_herramientas_usuario FOREIGN KEY (creado_por) REFERENCES usuarios(id) ON DELETE SET NULL,
  CONSTRAINT fk_herramientas_maleta  FOREIGN KEY (maleta_id)  REFERENCES maletas(id)  ON DELETE SET NULL,
  INDEX idx_herramientas_estado (estado),
  INDEX idx_herramientas_fecha (fecha_registro)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cada herramienta de la salida. salio / volvio = lo marcado herramienta por
-- herramienta al confirmar la salida y la devolución (columnas SALIDA /
-- ENTRADA del formato en papel): NULL = aún sin revisar, 1 = sí, 0 = no
-- (no salió / no volvió). Los faltantes salen de aquí.
CREATE TABLE IF NOT EXISTS checklist_herramientas_items (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  checklist_id INT UNSIGNED  NOT NULL,
  orden        SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  categoria    VARCHAR(120)  NOT NULL,                      -- categoría o nivel de la maleta
  nombre       VARCHAR(255)  NOT NULL,
  cantidad     INT UNSIGNED  NOT NULL DEFAULT 1,
  unidad       VARCHAR(40)   NULL,
  imagen       VARCHAR(255)  NULL,
  salio        TINYINT(1)    NULL,
  volvio       TINYINT(1)    NULL,
  es_extra     TINYINT(1)    NOT NULL DEFAULT 0,
  es_producto  TINYINT(1)    NOT NULL DEFAULT 0,
  agregado_en_edicion TINYINT(1) NOT NULL DEFAULT 0,        -- se agregó después, editando
  CONSTRAINT fk_item_herramientas FOREIGN KEY (checklist_id) REFERENCES checklists_herramientas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Contadores iniciales de los números de documento.
INSERT IGNORE INTO correlativos (clave, valor) VALUES
  ('cotizacion', 0), ('requerimiento', 0), ('herramientas', 0);

INSERT IGNORE INTO configuracion (clave, valor) VALUES
  ('igv', '0.18'),
  ('zona_horaria', 'America/Lima');

-- Clave para EDITAR cotizaciones, requerimientos y salidas de herramientas
-- (agregar productos, materiales o herramientas olvidados). Se guarda cifrada
-- (bcrypt) y vale "1234"; cámbiala desde la app o con:
--   UPDATE configuracion SET valor = '<password_hash de PHP>' WHERE clave = 'clave_edicion';
INSERT IGNORE INTO configuracion (clave, valor) VALUES
  ('clave_edicion', '$2y$12$iiv3c3uZo5p7lEnS76KQseP69gWYfQ0mY627YZUfTrjj09yKyxAMe');
-- El código del jefe de obra y el primer administrador los crea el instalador.
