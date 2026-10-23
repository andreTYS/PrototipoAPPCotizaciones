// Prueba de punta a punta: la app (DbApi + AlmacenState) contra la API real y
// una base PostgreSQL. Se salta sola si no hay una API de prueba corriendo.
//
//   API_PRUEBA=http://127.0.0.1:3999/api ADMIN_PRUEBA=clave flutter test test/integracion_api_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cotizador_icr/models/checklist_categoria.dart';
import 'package:cotizador_icr/models/checklist_herramientas.dart';
import 'package:cotizador_icr/models/cotizacion_guardada.dart';
import 'package:cotizador_icr/models/item_catalogo_checklist.dart';
import 'package:cotizador_icr/models/producto.dart';
import 'package:cotizador_icr/models/requerimiento.dart';
import 'package:cotizador_icr/screens/editar_almacen_screen.dart';
import 'package:cotizador_icr/services/api_cliente.dart';
import 'package:cotizador_icr/services/db_api.dart';
import 'package:cotizador_icr/services/db_helper.dart';
import 'package:cotizador_icr/state/almacen_state.dart';
import 'package:cotizador_icr/state/auth_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // en las pruebas de widgets la red viene bloqueada
  final url = Platform.environment['API_PRUEBA'];
  final claveAdmin = Platform.environment['ADMIN_PRUEBA'] ?? '';

  final api = ApiCliente.instancia;

  Future<void> entrarComo(String usuario, [String clave = 'clave-segura']) async {
    await AuthState().entrar(usuario, clave);
  }

  List<ChecklistCategoriaState> materiales() => [
        ChecklistCategoriaState(nombre: '1. CONDUIT', items: [
          ChecklistItemEntry(texto: 'Tubo Conduit 1"', cantidad: 11, precio: 19),
          ChecklistItemEntry(texto: 'Curva 90° 1"', cantidad: 10, precio: 3),
        ]),
        ChecklistCategoriaState(nombre: '2. FOTOVOLTAICO', items: [ChecklistItemEntry(texto: 'Conector MC4', cantidad: 20)]),
      ];

  setUpAll(() async {
    if (url == null) return;
    SharedPreferences.setMockInitialValues({});
    api.urlParaPruebas = url;
    DbHelper.instance = DbApi.instancia;
    await entrarComo('admin', claveAdmin);
    final existentes = {for (final u in await api.get('usuarios') as List) (u as Map)['usuario']: u['id']};
    for (final (u, rol) in [('juan', 'empleado'), ('carlos', 'encargado'), ('pedro', 'almacen'), ('ana', 'almacen'), ('vera', 'vendedor')]) {
      if (existentes.containsKey(u)) {
        // de una corrida anterior: se deja con la clave y el rol de la prueba
        await api.put('usuarios/${existentes[u]}', {'clave': 'clave-segura', 'rol': rol, 'activo': true});
      } else {
        await api.post('usuarios', {'usuario': u, 'nombre': u.toUpperCase(), 'clave': 'clave-segura', 'rol': rol});
      }
    }
  });

  group('app contra el servidor compartido', skip: url == null ? 'sin API de prueba (API_PRUEBA)' : false, () {
    test('el catálogo, las listas y las maletas llegan del servidor', () async {
      await entrarComo('juan');
      final db = DbHelper.instance;
      expect(db.esServidor, isTrue);
      expect(await db.countTotal(), greaterThanOrEqualTo(799));
      final agrupado = await db.getTodosAgrupados();
      expect(agrupado.keys, contains('CONTROLADORES'));
      expect((await db.buscar('mppt')).isNotEmpty, isTrue);
      final materiales = await db.getItemsCatalogoChecklist(TipoChecklist.materiales);
      expect(materiales.first.precio, 19);
      expect((await db.getMaletas()).length, greaterThanOrEqualTo(3));
    });

    test('un requerimiento pasa por varias personas y todas ven lo mismo', () async {
      // Juan (empleado) crea el requerimiento
      await entrarComo('juan');
      final deJuan = AlmacenState();
      await deJuan.cargar();
      final creado = await deJuan.crearRequerimiento(obra: 'Obra Integración', solicitante: 'Juan', urgente: false, categorias: materiales());
      expect(creado.numero, matches(r'^REQ-\d{4}$'));
      expect(creado.version, 1);

      // Un empleado no puede aprobar: el servidor lo rechaza
      await expectLater(deJuan.aprobarRequerimiento(creado, aprobadoPor: 'Juan'), throwsA(isA<ApiError>().having((e) => e.codigo, 'codigo', 403)));

      // Carlos (encargado) lo ve en su celular y lo aprueba
      await entrarComo('carlos');
      final deCarlos = AlmacenState();
      await deCarlos.cargar();
      final visto = deCarlos.requerimientos.firstWhere((r) => r.id == creado.id);
      expect(visto.obra, 'Obra Integración');
      final aprobado = await deCarlos.aprobarRequerimiento(visto, aprobadoPor: 'Carlos');
      expect(aprobado.estado, EstadoRequerimiento.aprobado);
      expect(aprobado.version, 2);

      // Pedro y Ana (almacén) abren el mismo requerimiento
      await entrarComo('pedro');
      final dePedro = AlmacenState();
      await dePedro.cargar();
      await entrarComo('ana');
      final deAna = AlmacenState();
      await deAna.cargar();

      // Pedro alista 2 de 3 y guarda
      await entrarComo('pedro');
      var r = dePedro.requerimientoPorId(creado.id!)!;
      var cats = categoriasDesdeJson(r.categoriasJson);
      for (final i in cats.expand((c) => c.items).take(2)) {
        i
          ..alistado = true
          ..alistadoPor = 'Pedro'
          ..fechaAlistado = DateTime.now();
      }
      final parcial = await dePedro.guardarAlistado(r, categorias: cats);
      expect(parcial.estado, EstadoRequerimiento.aprobado);
      expect(parcial.totalAlistados, 2);

      // Ana tenía la lista vieja: el servidor avisa en vez de pisar a Pedro
      await entrarComo('ana');
      final vieja = deAna.requerimientoPorId(creado.id!)!;
      final catsAna = categoriasDesdeJson(vieja.categoriasJson);
      catsAna.expand((c) => c.items).last
        ..alistado = true
        ..alistadoPor = 'Ana'
        ..fechaAlistado = DateTime.now();
      await expectLater(deAna.guardarAlistado(vieja, categorias: catsAna), throwsA(isA<ApiError>().having((e) => e.conflicto, 'conflicto', isTrue)));

      // Con lo último (ya refrescado) Ana continúa donde quedó Pedro y termina
      final actual = deAna.requerimientoPorId(creado.id!)!;
      expect(actual.totalAlistados, 2);
      final catsFinal = categoriasDesdeJson(actual.categoriasJson);
      for (final i in catsFinal.expand((c) => c.items).where((i) => i.alistado != true)) {
        i
          ..alistado = true
          ..alistadoPor = 'Ana'
          ..fechaAlistado = DateTime.now();
      }
      final listo = await deAna.guardarAlistado(actual, categorias: catsFinal);
      expect(listo.estado, EstadoRequerimiento.listo);
      expect(listo.quienesAlistaron, containsAll(['Pedro', 'Ana']));

      // Juan lo ve listo y confirma que lo recibió
      await entrarComo('juan');
      await deJuan.actualizarEnSegundoPlano();
      final paraEntregar = deJuan.requerimientoPorId(creado.id!)!;
      expect(paraEntregar.estado, EstadoRequerimiento.listo);
      final entregado = await deJuan.entregarRequerimiento(paraEntregar, recibidoPor: 'Juan');
      expect(entregado.estado, EstadoRequerimiento.entregado);

      // Editar con la clave: agregar un material olvidado lo reabre
      expect(await DbHelper.instance.verificarClaveEdicion('0000'), isFalse);
      expect(await DbHelper.instance.verificarClaveEdicion('1234'), isTrue);
      final editadas = categoriasDesdeJson(entregado.categoriasJson);
      editadas[0].items.add(ChecklistItemEntry(texto: 'Abrazaderas', cantidad: 20, precio: 2, esExtra: true, agregadoDespues: true));
      final reabierto = await deJuan.editarRequerimiento(
        entregado,
        ResultadoEdicion(
          obra: entregado.obra, persona: entregado.solicitante, observaciones: '', urgente: false, categorias: editadas,
          resumen: ['+ Abrazaderas × 20'], paraLaLista: const [],
        ),
      );
      expect(reabierto.estado, EstadoRequerimiento.aprobado);
      expect(reabierto.totalItems, 4);
      expect(reabierto.totalAlistados, 3);
      expect(reabierto.observaciones, contains('Abrazaderas'));
    });

    test('salida de herramientas: registrar, confirmar, devolver y editar', () async {
      await entrarComo('juan');
      final almacen = AlmacenState();
      await almacen.cargar();
      final salida = await almacen.registrarSalida(
        obra: 'Obra Y', responsable: 'Luis',
        categorias: [ChecklistCategoriaState(nombre: 'Primer nivel', items: [ChecklistItemEntry(texto: 'Taladro', cantidad: 1)])],
      );
      expect(salida.numero, matches(r'^HER-\d{4}$'));
      await expectLater(
        almacen.confirmarSalida(salida, confirmadaPor: 'Juan', categorias: categoriasDesdeJson(salida.categoriasJson)),
        throwsA(isA<ApiError>().having((e) => e.codigo, 'codigo', 403)),
      );

      await entrarComo('pedro');
      final dePedro = AlmacenState();
      await dePedro.cargar();
      final enObra = await dePedro.confirmarSalida(
        dePedro.herramientasPorId(salida.id!)!, confirmadaPor: 'Pedro',
        categorias: [ChecklistCategoriaState(nombre: 'Primer nivel', items: [ChecklistItemEntry(texto: 'Taladro', cantidad: 1, salio: true)])],
      );
      expect(enObra.estado, EstadoHerramientas.pendiente);

      await entrarComo('carlos');
      final deCarlos = AlmacenState();
      await deCarlos.cargar();
      final conforme = await deCarlos.confirmarDevolucion(
        deCarlos.herramientasPorId(salida.id!)!, encargado: 'Carlos',
        categorias: [ChecklistCategoriaState(nombre: 'Primer nivel', items: [ChecklistItemEntry(texto: 'Taladro', cantidad: 1, salio: true, volvio: true)])],
      );
      expect(conforme.estado, EstadoHerramientas.conforme);
    });

    test('cotizaciones: se guardan, las ve otro usuario y se editan con la clave', () async {
      await entrarComo('vera');
      final db = DbHelper.instance;
      final numero = await db.siguienteCorrelativo('cotizacion');
      await db.guardarCotizacion(CotizacionGuardada(
        numero: 'S${numero.toString().padLeft(5, '0')}', cliente: 'Cliente Integración', fecha: DateTime(2026, 10, 22, 9, 30), total: 200, archivoPdf: '',
        items: [ItemCotizacionGuardado(nombre: 'Panel 100W', cantidad: 2, precioUnitario: 100)],
      ));
      await entrarComo('juan');
      final lista = await db.getCotizacionesGuardadas();
      final c = lista.firstWhere((x) => x.cliente == 'Cliente Integración');
      expect(c.items.single.nombre, 'Panel 100W');
      expect(c.version, 1);

      await entrarComo('vera');
      final editada = CotizacionGuardada(
        id: c.id, numero: c.numero, cliente: 'Cliente Integración SAC', fecha: c.fecha, total: 250, archivoPdf: '', version: c.version,
        items: [...c.items, ItemCotizacionGuardado(nombre: 'Cable especial', cantidad: 1, precioUnitario: 50)],
      );
      await expectLater(db.actualizarCotizacion(editada), throwsA(isA<ApiError>().having((e) => e.codigo, 'codigo', 403))); // sin clave
      expect(await db.verificarClaveEdicion('1234'), isTrue);
      final guardada = await db.actualizarCotizacion(editada);
      expect(guardada.total, 250);
      expect(guardada.version, 2);
      expect(guardada.items.length, 2);
    });

    test('productos nuevos y listas editables se comparten', () async {
      await entrarComo('vera');
      final db = DbHelper.instance;
      final marca = 'cable integración ${DateTime.now().microsecondsSinceEpoch}';
      await db.agregarProductoManual(Producto(nombre: marca, categoriaProducto: 'CABLES', precioVenta: 12));
      expect((await db.buscar(marca)).single.origen, 'local');
      final item = ItemCatalogoChecklist(tipo: TipoChecklist.materiales, categoria: '1. CONDUIT', nombre: 'Cinta integración ${DateTime.now().microsecondsSinceEpoch}', fecha: DateTime.now(), precio: 4.5);
      await entrarComo('juan');
      final id = await db.agregarItemCatalogoChecklist(item);
      final lista = await db.getItemsCatalogoChecklist(TipoChecklist.materiales);
      expect(lista.any((i) => i.id == id && i.precio == 4.5), isTrue);
      await entrarComo('pedro');
      await db.eliminarItemCatalogoChecklist(id);
    });
  });
}
