import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_guardado.dart';
import '../models/checklist_herramientas.dart';
import '../models/cotizacion_guardada.dart';
import '../models/item_catalogo_checklist.dart';
import '../models/maleta.dart';
import '../models/producto.dart';
import '../models/requerimiento.dart';

/// Toda la app le pide productos a este helper, sin saber si vienen del
/// JSON semilla (primer arranque) o de una sincronización con el servidor.
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();
  Database? _db;

  /// Sube cada vez que cambia el catálogo de productos (se agrega, edita o
  /// elimina uno): las pantallas que lo muestran se actualizan solas.
  final ValueNotifier<int> catalogoCambios = ValueNotifier(0);

  /// Solo para pruebas: cierra la base y olvida la conexión, para abrir
  /// otra (en otra carpeta) la próxima vez.
  Future<void> cerrarParaPruebas() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'cotizador_icr.db');
    return openDatabase(
      path,
      version: 9,
      onCreate: (db, version) async {
        await _crearTablaProductos(db);
        await _crearTablaCotizacionesGuardadas(db);
        await _crearTablaChecklistsGuardados(db);
        await _crearTablasAlmacen(db);
        await _crearTablasConfiguracion(db);
        await _sembrarListasChecklist(db);
        await _sembrarMaletas(db);
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
        if (oldVersion < 7) {
          await _agregarColumnasEstadosAlmacen(db);
        }
        if (oldVersion < 8) {
          try {
            await db.execute('ALTER TABLE checklists_herramientas ADD COLUMN maleta TEXT');
          } catch (_) {
            // La columna ya existe (tabla recién creada con el esquema nuevo).
          }
        }
        if (oldVersion < 9) {
          await _migrarAConfiguracion(db);
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
        origen TEXT NOT NULL DEFAULT 'catalogo',
        modificado INTEGER NOT NULL DEFAULT 0,
        eliminado INTEGER NOT NULL DEFAULT 0,
        clave_catalogo TEXT
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
        fecha_listo TEXT,
        alistado_por TEXT,
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
        maleta TEXT,
        estado TEXT NOT NULL,
        fecha_salida TEXT NOT NULL,
        fecha_confirmacion_salida TEXT,
        salida_confirmada_por TEXT,
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
        fecha TEXT NOT NULL,
        precio REAL,
        orden INTEGER,
        base INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Maletas armadas (las de Configuración): cada una con sus herramientas
  /// por nivel y la foto de cada una.
  Future<void> _crearTablasConfiguracion(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS maletas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        orden INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS maleta_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        maleta_id INTEGER NOT NULL,
        nivel TEXT NOT NULL,
        nombre TEXT NOT NULL,
        imagen TEXT,
        orden INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Upgrade a la 9: las listas del checklist (materiales y herramientas)
  /// pasan a vivir enteras en la base, con precio y orden, para poder
  /// cambiar cualquier ítem desde Configuración; y los productos ganan las
  /// marcas "modificado" y "eliminado" para que lo que se cambie a mano no
  /// se pierda al actualizar el catálogo. Lo que ya se había agregado a la
  /// lista se conserva (queda al final de su categoría).
  Future<void> _migrarAConfiguracion(Database db) async {
    for (final alter in [
      'ALTER TABLE productos ADD COLUMN modificado INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE productos ADD COLUMN eliminado INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE productos ADD COLUMN clave_catalogo TEXT',
      'ALTER TABLE checklist_catalogo ADD COLUMN precio REAL',
      'ALTER TABLE checklist_catalogo ADD COLUMN orden INTEGER',
      'ALTER TABLE checklist_catalogo ADD COLUMN base INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(alter);
      } catch (_) {
        // La columna ya existe.
      }
    }
    await db.execute('UPDATE checklist_catalogo SET orden = 100000 + id WHERE orden IS NULL');
    // Los productos del catálogo que ya había (nadie los había podido
    // modificar todavía) guardan su identidad original.
    final existentes = await db.query('productos', where: "origen = 'catalogo' AND clave_catalogo IS NULL");
    final batch = db.batch();
    for (final fila in existentes) {
      batch.update('productos', {'clave_catalogo': _claveCatalogo(fila)}, where: 'id = ?', whereArgs: [fila['id']]);
    }
    await batch.commit(noResult: true);
    await _crearTablasConfiguracion(db);
    await _sembrarListasChecklist(db);
    await _sembrarMaletas(db);
  }

  /// Carga la lista base de la empresa (assets/checklist_seed.json y los
  /// precios de assets/precios_materiales.json) a la base. Lo que alguien
  /// ya había agregado con el mismo nombre se conserva y pasa a ser parte
  /// de la lista base. Solo se hace al crear o migrar la base.
  Future<void> _sembrarListasChecklist(Database db) async {
    final seed = jsonDecode(await rootBundle.loadString('assets/checklist_seed.json')) as List;
    final precios = <String, double>{};
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/precios_materiales.json')) as Map<String, dynamic>;
      for (final e in raw.entries) {
        precios[e.key.toLowerCase()] = (e.value as num).toDouble();
      }
    } catch (_) {
      // Sin lista de precios, los materiales quedan sin precio.
    }
    final ahora = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final c in seed) {
        final categoria = c['categoria'] as String;
        final tipo = tipoDeCategoriaSeed(categoria);
        final ordenCategoria = (c['orden'] as num).toInt();
        final items = List<String>.from(c['items'] as List);
        for (var i = 0; i < items.length; i++) {
          final nombre = items[i];
          final orden = ordenCategoria * 1000 + i;
          final precio = tipo == TipoChecklist.materiales ? precios[nombre.toLowerCase()] : null;
          final existente = await txn.query(
            'checklist_catalogo',
            columns: ['id'],
            where: 'tipo = ? AND LOWER(nombre) = ?',
            whereArgs: [tipo.name, nombre.toLowerCase()],
            limit: 1,
          );
          if (existente.isNotEmpty) {
            await txn.update(
              'checklist_catalogo',
              {'base': 1, 'orden': orden, 'precio': precio},
              where: 'id = ?',
              whereArgs: [existente.first['id']],
            );
          } else {
            await txn.insert('checklist_catalogo', {
              'tipo': tipo.name,
              'categoria': categoria,
              'nombre': nombre,
              'unidad': null,
              'fecha': ahora,
              'precio': precio,
              'orden': orden,
              'base': 1,
            });
          }
        }
      }
    });
  }

  /// Carga las maletas que vienen con la app (assets/maletas/maletas.json,
  /// armadas desde los checklists de la empresa) si todavía no hay ninguna.
  Future<void> _sembrarMaletas(Database db) async {
    if (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM maletas')) != 0) return;
    final maletas = jsonDecode(await rootBundle.loadString('assets/maletas/maletas.json')) as List;
    await db.transaction((txn) async {
      var ordenMaleta = 0;
      for (final m in maletas) {
        final id = await txn.insert('maletas', {'nombre': m['nombre'], 'orden': ordenMaleta++});
        var orden = 0;
        for (final c in m['categorias'] as List) {
          for (final i in c['items'] as List) {
            final foto = i['imagen'] as String?;
            await txn.insert('maleta_items', {
              'maleta_id': id,
              'nivel': c['nombre'],
              'nombre': i['nombre'],
              'imagen': foto == null ? null : 'assets/maletas/${m['carpeta']}/$foto',
              'orden': orden++,
            });
          }
        }
      }
    });
  }

  /// Upgrade desde una versión anterior a la 7: los estados nuevos
  /// ("listo para entrega" en requerimientos, "salida confirmada" en
  /// herramientas) guardan cuándo y quién. Las salidas que ya existían
  /// siguen como estaban (pendientes de devolución o conformes). Si la
  /// columna ya existe (tabla recién creada con el esquema nuevo) se ignora.
  Future<void> _agregarColumnasEstadosAlmacen(Database db) async {
    const columnas = [
      ('requerimientos', 'fecha_listo'),
      ('requerimientos', 'alistado_por'),
      ('checklists_herramientas', 'fecha_confirmacion_salida'),
      ('checklists_herramientas', 'salida_confirmada_por'),
    ];
    for (final (tabla, columna) in columnas) {
      try {
        await db.execute('ALTER TABLE $tabla ADD COLUMN $columna TEXT');
      } catch (_) {
        // La columna ya existe.
      }
    }
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
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM productos WHERE eliminado = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Reemplaza el catálogo (usado tanto por el seed inicial como por la
  /// sincronización con el servidor) — SOLO los productos de origen
  /// "catalogo". Lo que el usuario haya agregado a mano desde la app
  /// (origen "local") nunca se toca acá, ni los productos del catálogo que
  /// se hayan modificado o eliminado desde Configuración: conservan su
  /// cambio (el producto nuevo con el mismo id se descarta).
  Future<void> replaceAll(List<Producto> productos) async {
    final db = await database;
    await db.transaction((txn) async {
      // El catálogo empaquetado no trae ids: cada producto se reconoce por
      // su identidad original (nombre, referencia, categoría y precios tal
      // como vinieron), que se conserva aunque después se le cambie algo.
      final conservados = <String, int>{};
      final modificados = await txn.query(
        'productos',
        columns: ['clave_catalogo'],
        where: "origen = 'catalogo' AND modificado = 1 AND clave_catalogo IS NOT NULL",
      );
      for (final fila in modificados) {
        final clave = fila['clave_catalogo'] as String;
        conservados[clave] = (conservados[clave] ?? 0) + 1;
      }
      await txn.delete('productos', where: "origen = 'catalogo' AND modificado = 0");
      final batch = txn.batch();
      for (final p in productos) {
        final datos = p.toMap();
        final clave = _claveCatalogo(datos);
        final pendientes = conservados[clave] ?? 0;
        if (pendientes > 0) {
          conservados[clave] = pendientes - 1;
          continue;
        }
        batch.insert('productos', {...datos, 'origen': 'catalogo', 'clave_catalogo': clave});
      }
      await batch.commit(noResult: true);
    });
    catalogoCambios.value++;
  }

  static String _claveCatalogo(Map<String, Object?> p) =>
      '${(p['nombre'] ?? '').toString().trim().toLowerCase()}|${p['referencia_interna'] ?? ''}|'
      '${p['categoria_producto'] ?? ''}|${p['costo'] ?? ''}|${p['precio_venta'] ?? ''}';

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
    await actualizarCatalogoBaseForzado();
  }

  /// Vuelve a cargar el catálogo empaquetado sin mirar la versión (la
  /// sincronización y las pruebas); respeta lo modificado y agregado a mano.
  Future<void> actualizarCatalogoBaseForzado() async {
    final prefs = await SharedPreferences.getInstance();

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
    catalogoCambios.value++;
  }

  /// Edita cualquier producto (los de Configuración incluyen los del
  /// catálogo): un producto del catálogo queda marcado como "modificado"
  /// para que no se pierda al actualizar el catálogo base.
  Future<void> actualizarProductoManual(Producto producto) async {
    final db = await database;
    final datos = producto.toMap()..remove('id');
    await db.update(
      'productos',
      {...datos, 'modificado': 1},
      where: 'id = ?',
      whereArgs: [producto.id],
    );
    catalogoCambios.value++;
  }

  /// Los agregados a mano se borran; los del catálogo se marcan como
  /// eliminados (para que no vuelvan al actualizar el catálogo base).
  Future<void> eliminarProductoManual(int id) async {
    final db = await database;
    await db.delete('productos', where: "id = ? AND origen = 'local'", whereArgs: [id]);
    await db.update('productos', {'eliminado': 1, 'modificado': 1}, where: "id = ? AND origen = 'catalogo'", whereArgs: [id]);
    catalogoCambios.value++;
  }

  Future<List<String>> getCategorias() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT categoria_producto FROM productos WHERE eliminado = 0 ORDER BY categoria_producto',
    );
    return result.map((e) => e['categoria_producto'] as String).toList();
  }

  Future<List<Producto>> getProductosPorCategoria(String categoria) async {
    final db = await database;
    final result = await db.query(
      'productos',
      where: 'categoria_producto = ? AND eliminado = 0',
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
      where: 'eliminado = 0',
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
      where: 'eliminado = 0 AND (nombre LIKE ? OR referencia_interna LIKE ?)',
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

  /// Guarda los cambios de una cotización editada (datos, productos, total).
  Future<void> actualizarCotizacion(CotizacionGuardada cotizacion) async {
    final db = await database;
    await db.update('cotizaciones_guardadas', cotizacion.toMap(), where: 'id = ?', whereArgs: [cotizacion.id]);
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
  // Listas de los checklists (materiales y herramientas)
  // ---------------------------------------------------------------------

  /// Toda la lista de ese checklist, en el orden en que se arma.
  Future<List<ItemCatalogoChecklist>> getItemsCatalogoChecklist(TipoChecklist tipo) async {
    final db = await database;
    final result = await db.query(
      'checklist_catalogo',
      where: 'tipo = ?',
      whereArgs: [tipo.name],
      orderBy: 'orden, id',
    );
    return result.map((e) => ItemCatalogoChecklist.fromMap(e)).toList();
  }

  /// Agrega un ítem al final de su categoría (o, si la categoría es nueva,
  /// una categoría nueva al final de la lista).
  Future<int> agregarItemCatalogoChecklist(ItemCatalogoChecklist item) async {
    final db = await database;
    var orden = item.orden;
    if (orden == null) {
      final enCategoria = await db.rawQuery(
        'SELECT MAX(orden) AS m FROM checklist_catalogo WHERE tipo = ? AND categoria = ?',
        [item.tipo.name, item.categoria],
      );
      final maxCategoria = enCategoria.first['m'] as int?;
      if (maxCategoria != null) {
        orden = maxCategoria + 1;
      } else {
        final total = await db.rawQuery('SELECT MAX(orden) AS m FROM checklist_catalogo WHERE tipo = ?', [item.tipo.name]);
        final maxTotal = (total.first['m'] as int?) ?? 0;
        orden = ((maxTotal ~/ 1000) + 1) * 1000;
      }
    }
    return db.insert('checklist_catalogo', {...item.toMap(), 'orden': orden});
  }

  /// Cambia nombre, categoría, unidad o precio de un ítem de la lista.
  /// Al cambiar de categoría pasa al final de la nueva.
  Future<void> actualizarItemCatalogoChecklist(ItemCatalogoChecklist item, {required String categoriaAnterior}) async {
    final db = await database;
    final datos = {
      'categoria': item.categoria,
      'nombre': item.nombre,
      'unidad': item.unidad,
      'precio': item.precio,
    };
    if (item.categoria != categoriaAnterior) {
      final enCategoria = await db.rawQuery(
        'SELECT MAX(orden) AS m FROM checklist_catalogo WHERE tipo = ? AND categoria = ?',
        [item.tipo.name, item.categoria],
      );
      final maxCategoria = enCategoria.first['m'] as int?;
      if (maxCategoria != null) {
        datos['orden'] = maxCategoria + 1;
      } else {
        final total = await db.rawQuery('SELECT MAX(orden) AS m FROM checklist_catalogo WHERE tipo = ?', [item.tipo.name]);
        datos['orden'] = (((total.first['m'] as int?) ?? 0) ~/ 1000 + 1) * 1000;
      }
    }
    await db.update('checklist_catalogo', datos, where: 'id = ?', whereArgs: [item.id]);
  }

  /// Cambia el nombre de una categoría de la lista (en todos sus ítems).
  Future<void> renombrarCategoriaCatalogo(TipoChecklist tipo, String anterior, String nueva) async {
    final db = await database;
    await db.update(
      'checklist_catalogo',
      {'categoria': nueva},
      where: 'tipo = ? AND categoria = ?',
      whereArgs: [tipo.name, anterior],
    );
  }

  Future<void> eliminarItemCatalogoChecklist(int id) async {
    final db = await database;
    await db.delete('checklist_catalogo', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Maletas
  // ---------------------------------------------------------------------

  Future<List<Maleta>> getMaletas() async {
    final db = await database;
    final maletas = await db.query('maletas', orderBy: 'orden, id');
    final resultado = <Maleta>[];
    for (final m in maletas) {
      final items = await db.query('maleta_items', where: 'maleta_id = ?', whereArgs: [m['id']], orderBy: 'orden, id');
      final niveles = <String, List<ItemMaleta>>{};
      for (final i in items) {
        niveles.putIfAbsent(i['nivel'] as String, () => []).add(
              ItemMaleta(id: i['id'] as int, nombre: i['nombre'] as String, imagen: i['imagen'] as String?),
            );
      }
      resultado.add(Maleta(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        categorias: [for (final e in niveles.entries) CategoriaMaleta(nombre: e.key, items: e.value)],
      ));
    }
    return resultado;
  }

  Future<int> crearMaleta(String nombre) async {
    final db = await database;
    final max = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(MAX(orden), -1) FROM maletas')) ?? -1;
    return db.insert('maletas', {'nombre': nombre, 'orden': max + 1});
  }

  Future<void> renombrarMaleta(int id, String nombre) async {
    final db = await database;
    await db.update('maletas', {'nombre': nombre}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> eliminarMaleta(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('maleta_items', where: 'maleta_id = ?', whereArgs: [id]);
      await txn.delete('maletas', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Agrega una herramienta al final de su nivel (o un nivel nuevo al final).
  Future<int> agregarItemMaleta(int maletaId, {required String nivel, required String nombre, String? imagen}) async {
    final db = await database;
    final enNivel = await db.rawQuery(
      'SELECT MAX(orden) AS m FROM maleta_items WHERE maleta_id = ? AND nivel = ?',
      [maletaId, nivel],
    );
    int orden;
    final maxNivel = enNivel.first['m'] as int?;
    if (maxNivel != null) {
      orden = maxNivel + 1;
    } else {
      final total = await db.rawQuery('SELECT MAX(orden) AS m FROM maleta_items WHERE maleta_id = ?', [maletaId]);
      orden = (((total.first['m'] as int?) ?? -1) ~/ 1000 + 1) * 1000;
    }
    return db.insert('maleta_items', {
      'maleta_id': maletaId,
      'nivel': nivel,
      'nombre': nombre,
      'imagen': imagen,
      'orden': orden,
    });
  }

  Future<void> actualizarItemMaleta(int itemId, {required String nivel, required String nombre, String? imagen}) async {
    final db = await database;
    final actual = await db.query('maleta_items', where: 'id = ?', whereArgs: [itemId], limit: 1);
    if (actual.isEmpty) return;
    final datos = <String, Object?>{'nivel': nivel, 'nombre': nombre, 'imagen': imagen};
    if (actual.first['nivel'] != nivel) {
      final maletaId = actual.first['maleta_id'];
      final enNivel = await db.rawQuery(
        'SELECT MAX(orden) AS m FROM maleta_items WHERE maleta_id = ? AND nivel = ?',
        [maletaId, nivel],
      );
      final maxNivel = enNivel.first['m'] as int?;
      if (maxNivel != null) {
        datos['orden'] = maxNivel + 1;
      } else {
        final total = await db.rawQuery('SELECT MAX(orden) AS m FROM maleta_items WHERE maleta_id = ?', [maletaId]);
        datos['orden'] = (((total.first['m'] as int?) ?? -1) ~/ 1000 + 1) * 1000;
      }
    }
    await db.update('maleta_items', datos, where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> eliminarItemMaleta(int itemId) async {
    final db = await database;
    await db.delete('maleta_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> renombrarNivelMaleta(int maletaId, String anterior, String nuevo) async {
    final db = await database;
    await db.update(
      'maleta_items',
      {'nivel': nuevo},
      where: 'maleta_id = ? AND nivel = ?',
      whereArgs: [maletaId, anterior],
    );
  }
}
