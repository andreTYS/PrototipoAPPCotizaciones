import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cotizador_icr/models/checklist_categoria.dart';
import 'package:cotizador_icr/models/item_catalogo_checklist.dart';
import 'package:cotizador_icr/models/producto.dart';
import 'package:cotizador_icr/services/db_helper.dart';

/// Pruebas de la base local con SQLite de verdad (sqflite_common_ffi):
/// instalación nueva, migración desde la versión 8 y edición de productos
/// del catálogo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('cotizador_db_');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    DbHelper.instance.cerrarParaPruebas();
  });

  tearDown(() async {
    await DbHelper.instance.cerrarParaPruebas();
    await dir.delete(recursive: true);
  });

  test('instalación nueva: listas, precios y maletas sembradas', () async {
    final db = DbHelper.instance;
    final materiales = await db.getItemsCatalogoChecklist(TipoChecklist.materiales);
    final herramientas = await db.getItemsCatalogoChecklist(TipoChecklist.herramientas);
    expect(materiales.length, 56);
    expect(herramientas.length, 43);
    expect(materiales.every((i) => i.esBase), isTrue);
    expect(materiales.firstWhere((i) => i.nombre == 'Tubo Conduit 1"').precio, 19.0);
    expect(materiales.firstWhere((i) => i.nombre == 'Conector MC4').precio, isNull);
    // categorías en su orden de siempre
    final categorias = <String>[];
    for (final i in materiales) {
      if (!categorias.contains(i.categoria)) categorias.add(i.categoria);
    }
    expect(categorias, ['1. CONDUIT', '2. FOTOVOLTAICO', '3. ELÉCTRICO', '4. TECHO']);

    final maletas = await db.getMaletas();
    expect(maletas.map((m) => m.nombre).toList(), ['Maleta fotovoltaica 1', 'Maleta 2 - Blanca', 'Maletas TLD-AML']);
    expect(maletas.map((m) => m.totalItems).toList(), [35, 35, 2]);
    expect(maletas.first.categorias.map((c) => c.nombre).toList(), ['Primer nivel', 'Segundo nivel', 'Tercer nivel']);
    expect(maletas.first.categorias.first.items.first.imagen, 'assets/maletas/maleta1/foto01.jpg');
    expect(maletas.first.categorias[1].items.first.imagen, isNull);
  });

  test('migración desde la versión 8 conserva lo agregado y marca la lista base', () async {
    final ruta = p.join(dir.path, 'cotizador_icr.db');
    final viejo = await databaseFactoryFfi.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, v) async {
          await db.execute('''CREATE TABLE productos (id INTEGER PRIMARY KEY, costo REAL, nombre TEXT NOT NULL,
            precio_venta REAL, referencia_interna TEXT, unidad_medida TEXT, categoria_producto TEXT,
            archivo_imagen TEXT, imagen_url TEXT, origen TEXT NOT NULL DEFAULT 'catalogo')''');
          await db.execute('''CREATE TABLE checklist_catalogo (id INTEGER PRIMARY KEY AUTOINCREMENT, tipo TEXT NOT NULL,
            categoria TEXT NOT NULL, nombre TEXT NOT NULL, unidad TEXT, fecha TEXT NOT NULL)''');
          await db.insert('productos', {'id': 1, 'nombre': 'Panel', 'precio_venta': 100.0, 'categoria_producto': 'PANELES'});
          await db.insert('checklist_catalogo', {
            'tipo': 'materiales', 'categoria': '2. FOTOVOLTAICO', 'nombre': 'Cable PV Solar 10 mm', 'fecha': '2026-10-01T10:00:00',
          });
          await db.insert('checklist_catalogo', {
            'tipo': 'materiales', 'categoria': 'ILUMINACIÓN', 'nombre': 'Foco led', 'unidad': 'und', 'fecha': '2026-10-02T10:00:00',
          });
        },
      ),
    );
    await viejo.close();

    final db = DbHelper.instance;
    final materiales = await db.getItemsCatalogoChecklist(TipoChecklist.materiales);
    // 56 de la lista base (Cable PV Solar 10 mm ya estaba) + 1 nuevo (Foco led)
    expect(materiales.length, 57);
    final cable = materiales.firstWhere((i) => i.nombre == 'Cable PV Solar 10 mm');
    expect(cable.esBase, isTrue);
    final foco = materiales.firstWhere((i) => i.nombre == 'Foco led');
    expect(foco.esBase, isFalse);
    expect(foco.unidad, 'und');
    expect(materiales.last.nombre, 'Foco led'); // lo agregado queda al final
    expect((await db.getMaletas()).length, 3);
    expect(await db.countTotal(), 1);
  });

  test('editar y eliminar productos del catálogo sobrevive a actualizar el catálogo', () async {
    final db = DbHelper.instance;
    await db.actualizarCatalogoBase();
    expect(await db.countTotal(), 800);

    final panel = (await db.buscar('PANEL')).first;
    await db.actualizarProductoManual(Producto(
      id: panel.id,
      nombre: 'PANEL EDITADO',
      precioVenta: 999,
      categoriaProducto: panel.categoriaProducto,
      origen: 'catalogo',
    ));
    final otro = (await db.buscar('INVERSOR')).first;
    await db.eliminarProductoManual(otro.id!);
    expect(await db.countTotal(), 799);

    // Vuelve a cargarse el catálogo base: lo editado y lo eliminado se respetan.
    final seed = await rootBundle.loadString('assets/productos_seed.json');
    expect(seed.isNotEmpty, isTrue);
    SharedPreferences.setMockInitialValues({});
    await db.actualizarCatalogoBaseForzado();
    expect(await db.countTotal(), 799);
    final editado = await db.buscar('PANEL EDITADO');
    expect(editado.length, 1);
    expect(editado.first.precioVenta, 999);
    expect((await db.buscar(otro.nombre)).where((p) => p.id == otro.id), isEmpty);
  });

  test('agregar ítems y categorías nuevas a la lista', () async {
    final db = DbHelper.instance;
    final id = await db.agregarItemCatalogoChecklist(ItemCatalogoChecklist(
      tipo: TipoChecklist.materiales, categoria: '3. ELÉCTRICO', nombre: 'Interruptor', fecha: DateTime.now(), precio: 7.5,
    ));
    await db.agregarItemCatalogoChecklist(ItemCatalogoChecklist(
      tipo: TipoChecklist.materiales, categoria: 'ILUMINACIÓN', nombre: 'Foco led', fecha: DateTime.now(),
    ));
    final lista = await db.getItemsCatalogoChecklist(TipoChecklist.materiales);
    final posInterruptor = lista.indexWhere((i) => i.nombre == 'Interruptor');
    // queda al final de ELÉCTRICO, antes de TECHO
    expect(lista[posInterruptor - 1].categoria, '3. ELÉCTRICO');
    expect(lista[posInterruptor + 1].categoria, '4. TECHO');
    expect(lista.last.nombre, 'Foco led');

    final item = lista.firstWhere((i) => i.id == id);
    await db.actualizarItemCatalogoChecklist(item.copyWith(nombre: 'Interruptor doble', precio: 9), categoriaAnterior: item.categoria);
    final actualizado = (await db.getItemsCatalogoChecklist(TipoChecklist.materiales)).firstWhere((i) => i.id == id);
    expect(actualizado.nombre, 'Interruptor doble');
    expect(actualizado.precio, 9);
  });

  test('maletas: crear, agregar herramientas, mover de nivel y eliminar', () async {
    final db = DbHelper.instance;
    final id = await db.crearMaleta('Maleta 3');
    final a = await db.agregarItemMaleta(id, nivel: 'Primer nivel', nombre: 'Taladro', imagen: '/tmp/taladro.jpg');
    await db.agregarItemMaleta(id, nivel: 'Primer nivel', nombre: 'Amoladora');
    await db.agregarItemMaleta(id, nivel: 'Segundo nivel', nombre: 'Brocas');
    var maleta = (await db.getMaletas()).firstWhere((m) => m.id == id);
    expect(maleta.categorias.map((c) => '${c.nombre}:${c.items.length}').toList(), ['Primer nivel:2', 'Segundo nivel:1']);

    await db.actualizarItemMaleta(a, nivel: 'Segundo nivel', nombre: 'Taladro inalámbrico', imagen: '/tmp/taladro.jpg');
    maleta = (await db.getMaletas()).firstWhere((m) => m.id == id);
    expect(maleta.categorias.map((c) => '${c.nombre}:${c.items.length}').toList(), ['Primer nivel:1', 'Segundo nivel:2']);
    expect(maleta.categorias[1].items.last.nombre, 'Taladro inalámbrico');

    await db.eliminarMaleta(id);
    expect((await db.getMaletas()).where((m) => m.id == id), isEmpty);
  });
}
