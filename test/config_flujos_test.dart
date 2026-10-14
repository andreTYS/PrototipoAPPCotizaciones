import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cotizador_icr/models/checklist_categoria.dart';
import 'package:cotizador_icr/models/checklist_herramientas.dart';
import 'package:cotizador_icr/screens/config_lista_screen.dart';
import 'package:cotizador_icr/screens/config_maletas_screen.dart';
import 'package:cotizador_icr/screens/revision_herramientas_screen.dart';
import 'package:cotizador_icr/services/db_helper.dart';
import 'package:cotizador_icr/state/almacen_state.dart';
import 'package:cotizador_icr/state/checklist_state.dart';

/// Flujos de Configuración y de revisión herramienta por herramienta,
/// manejados como los usaría una persona (tocar, escribir, guardar) contra
/// una base SQLite real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DbHelper.instance.cerrarParaPruebas();
    dir = Directory.systemTemp.createTempSync('cot_flujo_');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
  });

  tearDown(() async {
    await DbHelper.instance.cerrarParaPruebas();
    dir.deleteSync(recursive: true);
  });

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Widget app(Widget home, {AlmacenState? almacen}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AlmacenState>(create: (_) => almacen ?? AlmacenState()),
          Provider(create: (_) => BorradoresChecklist()),
        ],
        child: MaterialApp(home: home),
      );

  testWidgets('materiales: cambiar el precio de un ítem y agregar uno nuevo con precio', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 2;
    await tester.runAsync(() => DbHelper.instance.getMaletas());
    await tester.pumpWidget(app(const ConfigListaScreen(tipo: TipoChecklist.materiales)));
    await esperar(tester);

    // Cambiar el precio del tubo (S/ 19.00 → 21.50)
    await tester.tap(find.text('Tubo Conduit 1"'));
    await esperar(tester);
    final precio = find.widgetWithText(TextField, 'Precio S/');
    expect(precio, findsOneWidget);
    await tester.enterText(precio, '21.50');
    await tester.tap(find.text('GUARDAR'));
    await esperar(tester);

    var items = (await tester.runAsync(() => DbHelper.instance.getItemsCatalogoChecklist(TipoChecklist.materiales)))!;
    expect(items.firstWhere((i) => i.nombre == 'Tubo Conduit 1"').precio, 21.5);
    expect(find.text('S/ 21.50'), findsOneWidget);

    // Agregar un material nuevo en una categoría existente
    await tester.tap(find.text('AGREGAR MATERIAL'));
    await esperar(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre *'), 'interruptor simple');
    await tester.enterText(find.widgetWithText(TextField, 'Precio S/'), '6,5');
    // sin categoría no deja guardar
    await tester.tap(find.text('GUARDAR'));
    await esperar(tester);
    expect(find.text('Elige o escribe una categoría'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await esperar(tester);
    await tester.tap(find.text('ELÉCTRICO').last);
    await esperar(tester);
    await tester.tap(find.text('GUARDAR'));
    await esperar(tester);

    items = (await tester.runAsync(() => DbHelper.instance.getItemsCatalogoChecklist(TipoChecklist.materiales)))!;
    final nuevo = items.firstWhere((i) => i.nombre == 'Interruptor simple');
    expect(nuevo.precio, 6.5);
    expect(nuevo.categoria, '3. ELÉCTRICO');
    expect(nuevo.esBase, isFalse);
  });

  testWidgets('maletas: crear una maleta y agregarle una herramienta', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 2;
    // La primera vez que se abre la base se cargan las listas y las maletas.
    await tester.runAsync(() => DbHelper.instance.getMaletas());
    await tester.pumpWidget(app(const ConfigMaletasScreen()));
    await esperar(tester);
    expect(find.text('Maleta 2 - Blanca'), findsOneWidget);

    await tester.tap(find.text('NUEVA MALETA'));
    await esperar(tester);
    await tester.enterText(find.byType(TextField), 'Maleta 3');
    await tester.tap(find.text('Guardar'));
    await esperar(tester);
    // se abre el editor de la maleta nueva, vacía
    expect(find.text('Esta maleta está vacía'), findsOneWidget);

    await tester.tap(find.text('AGREGAR HERRAMIENTA'));
    await esperar(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre *'), 'taladro percutor');
    await tester.enterText(find.widgetWithText(TextField, 'Nombre del nivel nuevo'), 'Primer nivel');
    await tester.tap(find.text('GUARDAR'));
    await esperar(tester);

    final maleta = (await tester.runAsync(() => DbHelper.instance.getMaletas()))!.firstWhere((m) => m.nombre == 'Maleta 3');
    expect(maleta.totalItems, 1);
    expect(maleta.categorias.single.nombre, 'Primer nivel');
    expect(maleta.categorias.single.items.single.nombre, 'Taladro percutor');
    expect(find.text('Taladro percutor'), findsOneWidget);
  });

  testWidgets('confirmar salida: exige el nombre y deja anotadas las que no salieron', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 2;
    final cats = [
      ChecklistCategoriaState(nombre: 'Primer nivel', items: [
        ChecklistItemEntry(texto: 'Taladro', cantidad: 1),
        ChecklistItemEntry(texto: 'Amoladora', cantidad: 1),
        ChecklistItemEntry(texto: 'Martillo', cantidad: 1),
      ]),
    ];
    final h = ChecklistHerramientas(
      id: 1, numero: 'HER-0001', obra: 'Obra X', responsable: 'Luis',
      fechaSalida: DateTime(2026, 10, 15), categoriasJson: categoriasAJson(cats),
    );
    ResultadoRevision? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => resultado = await Navigator.push<ResultadoRevision>(
              context,
              MaterialPageRoute(builder: (_) => RevisionHerramientasScreen(checklist: h, modo: ModoRevision.salida)),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await esperar(tester);

    // Sin nombre y sin marcar nada no avanza
    await tester.tap(find.textContaining('CONFIRMAR SALIDA'));
    await esperar(tester);
    expect(find.text('El nombre es obligatorio'), findsOneWidget);
    expect(resultado, isNull);

    // Marca dos de tres, pone el nombre y confirma
    await tester.tap(find.text('Taladro'));
    await tester.tap(find.text('Amoladora'));
    await tester.enterText(find.widgetWithText(TextField, 'Entregado por (almacén) *'), 'Pedro');
    await tester.pump();
    await tester.tap(find.textContaining('CONFIRMAR SALIDA'));
    await esperar(tester);

    expect(resultado, isNotNull);
    expect(resultado!.nombre, 'Pedro');
    final items = resultado!.categorias.single.items;
    expect(items.map((i) => '${i.texto}:${i.salio}').toList(), ['Taladro:true', 'Amoladora:true', 'Martillo:false']);
  });
}
