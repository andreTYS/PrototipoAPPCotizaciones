import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_guardado.dart';
import '../models/checklist_herramientas.dart';
import '../models/cotizacion_guardada.dart';
import '../models/item_catalogo_checklist.dart';
import '../models/producto.dart';
import '../models/requerimiento.dart';

/// Toda la app le pide productos a este helper, sin saber si vienen del
/// JSON semilla (primer arranque) o de una sincronización con el servidor.
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'cotizador_icr.db');
    return openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await _crearTablaProductos(db);
        await _crearTablaCotizacionesGuardadas(db);
        await _crearTablaChecklistsGuardados(db);
        await _crearTablasAlmacen(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // No se borra la tabla productos: no hay que perder un catálogo que
        // el usuario ya sincronizó con su servidor, ni lo que haya agregado
        // a mano (ver columna "origen").
        if (oldVersion < 2) {
          await _crearTablaCotizacionesGuardadas(db);
        }
        if (oldVersion < 3) {
          await _crearTablaChecklistsGuardados(db);
        }
        if (oldVersion < 4) {
          await _agregarColumnasDetalle(db);
        }
        if (oldVersion < 5) {
          await _agregarColumnaOrigenProducto(db);
        }
        if (oldVersion < 6) {
          await _crearTablasAlmacen(db);
        }
      },
    );
  }

  Future<void> _crearTablaProductos(Database db) async {
    await db.execute('''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY,
        costo REAL,
        nombre TEXT NOT NULL,
        precio_venta REAL,
        referencia_interna TEXT,
        unidad_medida TEXT,
        categoria_producto TEXT,
        archivo_imagen TEXT,
        imagen_url TEXT,
        origen TEXT NOT NULL DEFAULT 'catalogo'
      )
    ''');
  }

  Future<void> _crearTablaCotizacionesGuardadas(Database db) async {
    await db.execute('''
      CREATE TABLE cotizaciones_guardadas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero TEXT NOT NULL,
        cliente TEXT NOT NULL,
        ruc_dni TEXT,
        telefono TEXT,
        vendedor TEXT,
        banco TEXT,
        moneda TEXT,
        nro_cuenta TEXT,
        cci TEXT,
        fecha TEXT NOT NULL,
        total REAL NOT NULL,
        archivo_pdf TEXT NOT NULL,
        items_json TEXT
      )
    ''');
  }

  Future<void> _crearTablaChecklistsGuardados(Database db) async {
    await db.execute('''
      CREATE TABLE checklists_guardados (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        responsable TEXT NOT NULL,
        fecha TEXT NOT NULL,
        total_items INTEGER NOT NULL,
        items_marcados INTEGER NOT NULL,
        resumen_texto TEXT NOT NULL,
        archivo_pdf TEXT,
        categorias_json TEXT
      )
    ''');
  }

  /// Pestaña Almacén: requerimientos de materiales, salidas de herramientas
  /// y los ítems que se agregan a la lista base de esos checklists. Con IF
  /// NOT EXISTS porque se llama tanto al crear la base desde cero como al
  /// actualizar desde una versión anterior (donde no existían).
  Future<void> _crearTablasAlmacen(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS requerimientos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero TEXT NOT NULL,
        obra TEXT NOT NULL,
        solicitante TEXT NOT NULL,
        urgente INTEGER NOT NULL DEFAULT 0,
        estado TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_aprobacion TEXT,
        aprobado_por TEXT,
        fecha_entrega TEXT,
        recibido_por TEXT,
        observaciones TEXT,
        categorias_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checklists_herramientas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero TEXT NOT NULL,
        obra TEXT NOT NULL,
        responsable TEXT NOT NULL,
        estado TEXT NOT NULL,
        fecha_salida TEXT NOT NULL,
        fecha_devolucion TEXT,
        encargado TEXT,
        observaciones TEXT,
        observaciones_devolucion TEXT,
        categorias_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checklist_catalogo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        categoria TEXT NOT NULL,
        nombre TEXT NOT NULL,
        unidad TEXT,
        fecha TEXT NOT NULL
      )
    ''');
  }

  /// Upgrade desde una versión anterior a la 4: agrega las columnas nuevas
  /// de detalle a las tablas que ya existían, sin tocar las filas que ya
  /// había (ALTER TABLE ADD COLUMN no borra nada, solo agrega la columna
  /// vacía). Si una columna ya existe (por ejemplo, porque la tabla se
  /// creó recién con el esquema nuevo en este mismo upgrade) se ignora.
  Future<void> _agregarColumnasDetalle(Database db) async {
    const columnasCotizacion = [
      'telefono',
      'vendedor',
      'banco',
      'moneda',
      'nro_cuenta',
      'cci',
      'items_json',
    ];
    for (final columna in columnasCotizacion) {
      try {
        await db.execute('ALTER TABLE cotizaciones_guardadas ADD COLUMN $columna TEXT');
      } catch (_) {
        // La columna ya existe.
      }
    }
    try {
      await db.execute('ALTER TABLE checklists_guardados ADD COLUMN categorias_json TEXT');
    } catch (_) {
      // La columna ya existe.
    }
  }

  /// Upgrade desde una versión anterior a la 5: todo lo que ya había en la
  /// tabla productos (catálogo semilla o sincronizado con un servidor) pasa
  /// a marcarse como "catalogo" — nadie había agregado nada a mano todavía,
  /// porque esa función no existía antes de esta versión.
  Future<void> _agregarColumnaOrigenProducto(Database db) async {
    try {
      await db.execute("ALTER TABLE productos ADD COLUMN origen TEXT NOT NULL DEFAULT 'catalogo'");
    } catch (_) {
      // La columna ya existe.
    }
  }

  Future<int> countTotal() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM productos');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Reemplaza el catálogo (usado tanto por el seed inicial como por la
  /// sincronización con el servidor) — SOLO los productos de origen
  /// "catalogo". Lo que el usuario haya agregado a mano desde la app
  /// (origen "local") nunca se toca acá, para no perderlo.
  Future<void> replaceAll(List<Producto> productos) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('productos', where: "origen = 'catalogo'");
      final batch = txn.batch();
      for (final p in productos) {
        batch.insert('productos', {...p.toMap(), 'origen': 'catalogo'});
      }
      await batch.commit(noResult: true);
    });
  }

  /// Sube este número cada vez que se reemplace assets/productos_seed.json
  /// con un catálogo nuevo — así los celulares que YA tenían la app
  /// instalada (no solo las instalaciones nuevas) reciben el catálogo
  /// actualizado la próxima vez que abran la app.
  static const int _versionCatalogo = 1;

  /// Sincroniza el catálogo base con lo que viene empaquetado en el
  /// instalador: la primera vez llena la base vacía, y en instalaciones que
  /// ya tenían un catálogo viejo lo reemplaza si _versionCatalogo subió —
  /// en ambos casos sin tocar los productos agregados a mano (ver
  /// [replaceAll]).
  Future<void> actualizarCatalogoBase() async {
    final prefs = await SharedPreferences.getInstance();
    final versionInstalada = prefs.getInt('version_catalogo_productos') ?? 0;
    if (versionInstalada >= _versionCatalogo) return;

    final raw = await rootBundle.loadString('assets/productos_seed.json');
    final List<dynamic> data = jsonDecode(raw);
    final productos = data.map((e) => Producto.fromMap(Map<String, dynamic>.from(e))).toList();
    await replaceAll(productos);

    await prefs.setInt('version_catalogo_productos', _versionCatalogo);
  }

  /// Agrega un producto nuevo escrito a mano desde la app (no del catálogo
  /// empaquetado ni de una sincronización) — se marca como origen "local"
  /// para que nunca se borre al actualizar el catálogo base.
  Future<void> agregarProductoManual(Producto producto) async {
    final db = await database;
    await db.insert('productos', {...producto.toMap(), 'origen': 'local'});
  }

  /// Solo para productos de origen "local": los del catálogo se reemplazan
  /// enteros al actualizar/sincronizar, así que un cambio a mano sobre ellos
  /// se perdería sin aviso.
  Future<void> actualizarProductoManual(Producto producto) async {
    final db = await database;
    final datos = producto.toMap()..remove('id');
    await db.update(
      'productos',
      datos,
      where: "id = ? AND origen = 'local'",
      whereArgs: [producto.id],
    );
  }

  Future<void> eliminarProductoManual(int id) async {
    final db = await database;
    await db.delete('productos', where: "id = ? AND origen = 'local'", whereArgs: [id]);
  }

  Future<List<String>> getCategorias() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT categoria_producto FROM productos ORDER BY categoria_producto',
    );
    return result.map((e) => e['categoria_producto'] as String).toList();
  }

  Future<List<Producto>> getProductosPorCategoria(String categoria) async {
    final db = await database;
    final result = await db.query(
      'productos',
      where: 'categoria_producto = ?',
      whereArgs: [categoria],
      orderBy: 'nombre',
    );
    return result.map((e) => Producto.fromMap(e)).toList();
  }

  /// Todo el catálogo agrupado por categoría en una sola consulta — para la
  /// pantalla de Productos (lista de categorías tipo acordeón), evita
  /// pedirle a la base una consulta separada por cada categoría.
  Future<Map<String, List<Producto>>> getTodosAgrupados() async {
    final db = await database;
    final result = await db.query(
      'productos',
      orderBy: 'categoria_producto, nombre',
    );
    final agrupado = <String, List<Producto>>{};
    for (final fila in result) {
      final producto = Producto.fromMap(fila);
      agrupado.putIfAbsent(producto.categoriaProducto, () => []).add(producto);
    }
    return agrupado;
  }

  Future<List<Producto>> buscar(String query) async {
    final db = await database;
    final result = await db.query(
      'productos',
      where: 'nombre LIKE ? OR referencia_interna LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'nombre',
      limit: 150,
    );
    return result.map((e) => Producto.fromMap(e)).toList();
  }

  Future<void> guardarCotizacion(CotizacionGuardada cotizacion) async {
    final db = await database;
    await db.insert('cotizaciones_guardadas', cotizacion.toMap());
  }

  Future<List<CotizacionGuardada>> getCotizacionesGuardadas() async {
    final db = await database;
    final result = await db.query('cotizaciones_guardadas', orderBy: 'fecha DESC');
    return result.map((e) => CotizacionGuardada.fromMap(e)).toList();
  }

  Future<void> eliminarCotizacion(int id) async {
    final db = await database;
    await db.delete('cotizaciones_guardadas', where: 'id = ?', whereArgs: [id]);
  }

  /// Devuelve el id de la fila insertada, para poder actualizarla después
  /// (ej. cuando recién en ese momento se genera el PDF).
  Future<int> guardarChecklist(ChecklistGuardado checklist) async {
    final db = await database;
    return db.insert('checklists_guardados', checklist.toMap());
  }

  Future<void> actualizarChecklist(int id, ChecklistGuardado checklist) async {
    final db = await database;
    await db.update(
      'checklists_guardados',
      checklist.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> eliminarChecklist(int id) async {
    final db = await database;
    await db.delete('checklists_guardados', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChecklistGuardado>> getChecklistsGuardados() async {
    final db = await database;
    final result = await db.query('checklists_guardados', orderBy: 'fecha DESC');
    return result.map((e) => ChecklistGuardado.fromMap(e)).toList();
  }

  Future<int> countChecklistsGuardados() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM checklists_guardados');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------------------------------------------------------------------
  // Almacén: requerimientos
  // ---------------------------------------------------------------------

  Future<int> insertarRequerimiento(Requerimiento requerimiento) async {
    final db = await database;
    return db.insert('requerimientos', requerimiento.toMap());
  }

  Future<void> actualizarRequerimiento(Requerimiento requerimiento) async {
    final db = await database;
    await db.update(
      'requerimientos',
      requerimiento.toMap(),
      where: 'id = ?',
      whereArgs: [requerimiento.id],
    );
  }

  Future<void> eliminarRequerimiento(int id) async {
    final db = await database;
    await db.delete('requerimientos', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Requerimiento>> getRequerimientos() async {
    final db = await database;
    final result = await db.query('requerimientos', orderBy: 'fecha_creacion DESC');
    return result.map((e) => Requerimiento.fromMap(e)).toList();
  }

  // ---------------------------------------------------------------------
  // Almacén: checklists de herramientas
  // ---------------------------------------------------------------------

  Future<int> insertarChecklistHerramientas(ChecklistHerramientas checklist) async {
    final db = await database;
    return db.insert('checklists_herramientas', checklist.toMap());
  }

  Future<void> actualizarChecklistHerramientas(ChecklistHerramientas checklist) async {
    final db = await database;
    await db.update(
      'checklists_herramientas',
      checklist.toMap(),
      where: 'id = ?',
      whereArgs: [checklist.id],
    );
  }

  Future<void> eliminarChecklistHerramientas(int id) async {
    final db = await database;
    await db.delete('checklists_herramientas', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChecklistHerramientas>> getChecklistsHerramientas() async {
    final db = await database;
    final result = await db.query('checklists_herramientas', orderBy: 'fecha_salida DESC');
    return result.map((e) => ChecklistHerramientas.fromMap(e)).toList();
  }

  // ---------------------------------------------------------------------
  // Ítems agregados a la lista base de los checklists
  // ---------------------------------------------------------------------

  Future<List<ItemCatalogoChecklist>> getItemsCatalogoChecklist(TipoChecklist tipo) async {
    final db = await database;
    final result = await db.query(
      'checklist_catalogo',
      where: 'tipo = ?',
      whereArgs: [tipo.name],
      orderBy: 'id',
    );
    return result.map((e) => ItemCatalogoChecklist.fromMap(e)).toList();
  }

  Future<int> agregarItemCatalogoChecklist(ItemCatalogoChecklist item) async {
    final db = await database;
    return db.insert('checklist_catalogo', item.toMap());
  }

  Future<void> eliminarItemCatalogoChecklist(int id) async {
    final db = await database;
    await db.delete('checklist_catalogo', where: 'id = ?', whereArgs: [id]);
  }
}
