import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cotizador_icr/models/checklist_categoria.dart';
import 'package:cotizador_icr/models/checklist_herramientas.dart';
import 'package:cotizador_icr/models/cotizacion_guardada.dart';
import 'package:cotizador_icr/models/requerimiento.dart';
import 'package:cotizador_icr/screens/alistar_requerimiento_screen.dart';
import 'package:cotizador_icr/screens/editar_almacen_screen.dart';
import 'package:cotizador_icr/screens/editar_cotizacion_screen.dart';
import 'package:cotizador_icr/services/db_helper.dart';
import 'package:cotizador_icr/services/pdf_service.dart';
import 'package:cotizador_icr/state/almacen_state.dart';
import 'package:cotizador_icr/utils/seguridad.dart';

/// Alistado material por material con avance compartido, y edición con
/// clave de requerimientos, salidas de herramientas y cotizaciones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DbHelper.instance.cerrarParaPruebas();
    dir = Directory.systemTemp.createTempSync('cot_edicion_');
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

  List<ChecklistCategoriaState> tresMateriales() => [
        ChecklistCategoriaState(nombre: '1. CONDUIT', items: [
          ChecklistItemEntry(texto: 'Tubo Conduit 1"', cantidad: 11, precio: 19),
          ChecklistItemEntry(texto: 'Curva 90° 1"', cantidad: 10, precio: 3),
        ]),
        ChecklistCategoriaState(nombre: '2. FOTOVOLTAICO', items: [
          ChecklistItemEntry(texto: 'Conector MC4', cantidad: 20),
        ]),
      ];

  test('alistado compartido: una persona alista parte y otra termina', () async {
    final almacen = AlmacenState();
    var r = (await almacen.crearRequerimiento(
      obra: 'Obra X', solicitante: 'Juan', urgente: false, categorias: tresMateriales(),
    ));
    r = await almacen.aprobarRequerimiento(r, aprobadoPor: 'Carlos');
    expect(r.estado, EstadoRequerimiento.aprobado);
    expect(r.totalAlistados, 0);

    // Pedro alista 2 de 3 y guarda
    final cats = soloMarcados(categoriasDesdeJson(r.categoriasJson));
    cats[0].items[0]
      ..alistado = true
      ..alistadoPor = 'Pedro'
      ..fechaAlistado = DateTime(2026, 10, 15, 9);
    cats[0].items[1]
      ..alistado = true
      ..alistadoPor = 'Pedro'
      ..fechaAlistado = DateTime(2026, 10, 15, 9);
    r = await almacen.guardarAlistado(r, categorias: cats);
    expect(r.estado, EstadoRequerimiento.aprobado); // sigue pendiente de alistar
    expect(r.totalAlistados, 2);
    expect(r.todoAlistado, isFalse);

    // Lo guardado está en la base: otra persona lo ve igual
    final recargado = (await DbHelper.instance.getRequerimientos()).single;
    expect(recargado.totalAlistados, 2);
    expect(recargado.quienesAlistaron, ['Pedro']);

    // Ana continúa con el que falta
    final cats2 = soloMarcados(categoriasDesdeJson(recargado.categoriasJson));
    cats2[1].items[0]
      ..alistado = true
      ..alistadoPor = 'Ana'
      ..fechaAlistado = DateTime(2026, 10, 15, 15);
    r = await almacen.guardarAlistado(recargado, categorias: cats2);
    expect(r.estado, EstadoRequerimiento.listo);
    expect(r.alistadoPor, 'Pedro, Ana');
    expect(r.fechaListo, isNotNull);
  });

  testWidgets('pantalla de alistar: exige el nombre y marca quién alistó lo nuevo', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 2;
    final cats = tresMateriales();
    cats[0].items[0]
      ..alistado = true
      ..alistadoPor = 'Pedro'
      ..fechaAlistado = DateTime(2026, 10, 15, 9);
    final r = Requerimiento(
      id: 1, numero: 'REQ-0001', obra: 'Obra X', solicitante: 'Juan', estado: EstadoRequerimiento.aprobado,
      fechaCreacion: DateTime(2026, 10, 14), categoriasJson: categoriasAJson(cats),
    );
    ResultadoAlistado? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => resultado = await Navigator.push<ResultadoAlistado>(
              context,
              MaterialPageRoute(builder: (_) => AlistarRequerimientoScreen(requerimiento: r)),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await esperar(tester);

    expect(find.text('1 de 3 alistados'), findsOneWidget);
    expect(find.textContaining('Alistado por Pedro'), findsOneWidget);

    await tester.tap(find.text('Curva 90° 1"'));
    await tester.pump();
    expect(find.text('2 de 3 alistados'), findsOneWidget);

    // sin nombre no guarda
    await tester.tap(find.textContaining('GUARDAR AVANCE'));
    await esperar(tester);
    expect(find.text('El nombre es obligatorio'), findsOneWidget);
    expect(resultado, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Alistado por (almacenero) *'), 'Ana');
    await tester.pump();
    await tester.tap(find.textContaining('GUARDAR AVANCE'));
    await esperar(tester);

    final items = resultado!.categorias.expand((c) => c.items).toList();
    expect(items[0].alistadoPor, 'Pedro'); // el de antes no cambia de dueño
    expect(items[1].alistado, isTrue);
    expect(items[1].alistadoPor, 'Ana');
    expect(items[2].alistado, isNot(true));
  });

  testWidgets('clave de edición: rechaza una incorrecta y acepta 1234', (tester) async {
    bool? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () async => resultado = await pedirClaveEdicion(context), child: const Text('editar')),
        ),
      ),
    ));
    await tester.tap(find.text('editar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Clave incorrecta'), findsOneWidget);
    expect(resultado, isNull);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(resultado, isTrue);
  });

  test('editar un requerimiento listo con un material nuevo lo reabre sin perder lo alistado', () async {
    final almacen = AlmacenState();
    var r = await almacen.crearRequerimiento(obra: 'Obra X', solicitante: 'Juan', urgente: false, categorias: tresMateriales());
    r = await almacen.aprobarRequerimiento(r, aprobadoPor: 'Carlos');
    final cats = soloMarcados(categoriasDesdeJson(r.categoriasJson));
    for (final i in cats.expand((c) => c.items)) {
      i
        ..alistado = true
        ..alistadoPor = 'Pedro'
        ..fechaAlistado = DateTime.now();
    }
    r = await almacen.guardarAlistado(r, categorias: cats);
    expect(r.estado, EstadoRequerimiento.listo);

    // Se le agrega un material olvidado y se cambia una cantidad
    final editadas = soloMarcados(categoriasDesdeJson(r.categoriasJson));
    editadas[0].items[0].cantidad = 12;
    editadas[0].items.add(ChecklistItemEntry(
      texto: 'Abrazaderas', cantidad: 20, precio: 2, esExtra: true, agregadoDespues: true,
    ));
    final resultado = ResultadoEdicion(
      obra: 'Obra X', persona: 'Juan', observaciones: '', urgente: false, categorias: editadas,
      resumen: ['+ Abrazaderas × 20', 'Tubo Conduit 1": ×11 → ×12'], paraLaLista: const [],
    );
    expect(resultado.nuevos, 1);
    r = await almacen.editarRequerimiento(r, resultado);

    expect(r.estado, EstadoRequerimiento.aprobado); // reabierto: falta alistar lo nuevo
    expect(r.fechaListo, isNull);
    expect(r.totalItems, 4);
    expect(r.totalAlistados, 3); // lo de antes sigue alistado
    expect(r.observaciones, contains('[Editado'));
    expect(r.observaciones, contains('+ Abrazaderas'));
    expect(r.totalPrecio, 12 * 19 + 10 * 3 + 20 * 2);
    expect((await DbHelper.instance.getRequerimientos()).single.totalItems, 4);
  });

  test('editar una salida conforme con una herramienta nueva la deja pendiente de devolución', () async {
    final almacen = AlmacenState();
    final cats = [
      ChecklistCategoriaState(nombre: 'Primer nivel', items: [
        ChecklistItemEntry(texto: 'Taladro', cantidad: 1, salio: true, volvio: true),
      ]),
    ];
    var h = await almacen.registrarSalida(obra: 'Obra Y', responsable: 'Luis', categorias: cats);
    h = await almacen.confirmarSalida(h, confirmadaPor: 'Pedro', categorias: [
      ChecklistCategoriaState(nombre: 'Primer nivel', items: [ChecklistItemEntry(texto: 'Taladro', cantidad: 1, salio: true)]),
    ]);
    h = await almacen.confirmarDevolucion(h, encargado: 'Pedro', categorias: [
      ChecklistCategoriaState(nombre: 'Primer nivel', items: [ChecklistItemEntry(texto: 'Taladro', cantidad: 1, salio: true, volvio: true)]),
    ]);
    expect(h.estado, EstadoHerramientas.conforme);

    final editadas = soloMarcados(categoriasDesdeJson(h.categoriasJson));
    editadas[0].items.add(ChecklistItemEntry(texto: 'Amoladora', cantidad: 1, esExtra: true, agregadoDespues: true));
    h = await almacen.editarHerramientas(
      h,
      ResultadoEdicion(
        obra: 'Obra Y', persona: 'Luis', observaciones: '', urgente: false, categorias: editadas,
        resumen: ['+ Amoladora × 1'], paraLaLista: const [],
      ),
    );
    expect(h.estado, EstadoHerramientas.pendiente);
    expect(h.fechaDevolucion, isNull);
    final amoladora = h.categorias.expand((c) => c.items).firstWhere((i) => i.texto == 'Amoladora');
    expect(amoladora.salio, isTrue); // se da por salida junto con las demás
    expect(amoladora.volvio, isNull);
    expect(h.totalItems, 2);
  });

  testWidgets('editar requerimiento: agregar un material nuevo y guardarlo también en la lista', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 2;
    await tester.runAsync(() => DbHelper.instance.getMaletas());
    ResultadoEdicion? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => resultado = await Navigator.push<ResultadoEdicion>(
              context,
              MaterialPageRoute(
                builder: (_) => EditarAlmacenScreen(
                  tipo: TipoChecklist.materiales, numero: 'REQ-0001', obra: 'Obra X', persona: 'Juan',
                  observaciones: '', urgente: false, categorias: tresMateriales(),
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await esperar(tester);

    await tester.tap(find.text('Agregar material'));
    await esperar(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre *'), 'cinta aislante');
    await tester.enterText(find.widgetWithText(TextField, 'Precio unitario S/'), '4.5');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await esperar(tester);
    await tester.tap(find.text('CONDUIT').last);
    await esperar(tester);
    await tester.tap(find.text('Guardar también en la lista de materiales'));
    await tester.pump();
    await tester.tap(find.text('AGREGAR'));
    await esperar(tester);
    expect(find.text('Cinta aislante'), findsOneWidget);
    expect(find.text('Nuevo'), findsOneWidget);

    await tester.tap(find.text('GUARDAR'));
    await esperar(tester);
    expect(resultado, isNotNull);
    expect(resultado!.nuevos, 1);
    expect(resultado!.resumen.single, startsWith('+ Cinta aislante'));
    expect(resultado!.paraLaLista.single.nombre, 'Cinta aislante');
    final nuevo = resultado!.categorias.expand((c) => c.items).firstWhere((i) => i.texto == 'Cinta aislante');
    expect(nuevo.agregadoDespues, isTrue);
    expect(nuevo.precio, 4.5);

    // ...y al guardar el cambio, queda también en la lista base
    final lista = await tester.runAsync(() async {
      final almacen = AlmacenState();
      final r = await almacen.crearRequerimiento(obra: 'Obra X', solicitante: 'Juan', urgente: false, categorias: tresMateriales());
      await almacen.editarRequerimiento(r, resultado!);
      return DbHelper.instance.getItemsCatalogoChecklist(TipoChecklist.materiales);
    });
    expect(lista!.any((i) => i.nombre == 'Cinta aislante' && i.precio == 4.5), isTrue);
  });

  testWidgets('editar cotización: agregar un producto nuevo y regenerar el PDF', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 2;
    final pdf = '${dir.path}/cotizacion_S00007.pdf';
    final c = CotizacionGuardada(
      id: 1, numero: 'S00007', cliente: 'Cliente SAC', fecha: DateTime(2026, 10, 10), total: 200, archivoPdf: pdf,
      items: [ItemCotizacionGuardado(nombre: 'Panel 100W', cantidad: 2, precioUnitario: 100)],
    );
    CotizacionGuardada? editada;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => editada = await Navigator.push<CotizacionGuardada>(
              context,
              MaterialPageRoute(builder: (_) => EditarCotizacionScreen(cotizacion: c)),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await esperar(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Cliente'), 'Cliente SAC Perú');
    await tester.tap(find.text('Agregar producto'));
    await esperar(tester);
    await tester.tap(find.text('Producto nuevo'));
    await esperar(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre *'), 'cable especial');
    await tester.enterText(find.widgetWithText(TextField, 'Precio S/ *'), '50');
    await tester.tap(find.text('AGREGAR'));
    await esperar(tester);
    expect(find.text('S/ 250.00'), findsWidgets); // 200 + 50 en el total

    await tester.tap(find.text('GUARDAR'));
    await esperar(tester);
    expect(editada, isNotNull);
    expect(editada!.total, 250);
    expect(editada!.cliente, 'Cliente SAC Perú');
    expect(editada!.items.map((i) => i.nombre), ['Panel 100W', 'Cable especial']);

    final ruta = await tester.runAsync(() => PdfService.regenerarCotizacion(editada!));
    expect(ruta, pdf);
    expect(File(pdf).existsSync(), isTrue);
    expect(File(pdf).lengthSync(), greaterThan(1000));
  });
}
