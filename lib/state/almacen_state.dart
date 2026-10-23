import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../models/item_catalogo_checklist.dart';
import '../models/requerimiento.dart';
import '../screens/editar_almacen_screen.dart';
import '../services/api_cliente.dart';
import '../services/db_helper.dart';

/// Código que pide la app para aprobar un requerimiento como jefe de obra,
/// para que no lo apruebe cualquiera. Fijo por ahora (así se definió para
/// esta etapa); si más adelante cada jefe de obra necesita el suyo, este es
/// el único lugar que hay que cambiar.
const codigoJefeDeObra = '1234';

/// Requerimientos de materiales y salidas de herramientas de la pestaña
/// Almacén. Lo comparten el Inicio (lo urgente/pendiente), las listas y los
/// detalles: cada cambio de estado se guarda en la base y avisa a todas las
/// pantallas a la vez, sin que cada una tenga que volver a consultarla.
class AlmacenState extends ChangeNotifier {
  List<Requerimiento> _requerimientos = [];
  List<ChecklistHerramientas> _herramientas = [];
  int _checklistsAnteriores = 0;
  bool _cargando = true;

  List<Requerimiento> get requerimientos => _requerimientos;
  List<ChecklistHerramientas> get herramientas => _herramientas;
  bool get cargando => _cargando;

  /// Checklists de obra guardados con la versión anterior de la app (antes
  /// de separar requerimientos y herramientas) — se siguen pudiendo ver.
  int get checklistsAnteriores => _checklistsAnteriores;

  List<Requerimiento> get pendientesAprobacion =>
      _requerimientos.where((r) => r.estado == EstadoRequerimiento.pendiente).toList();

  List<Requerimiento> get urgentesSinEntregar => _requerimientos.where((r) => r.urgente && !r.entregado).toList();

  /// Lo urgente primero; dentro de cada grupo, lo más reciente arriba.
  List<Requerimiento> get requierenAtencion {
    final lista = _requerimientos.where((r) => r.requiereAtencion).toList();
    lista.sort((a, b) {
      if (a.urgente != b.urgente) return a.urgente ? -1 : 1;
      return b.fechaCreacion.compareTo(a.fechaCreacion);
    });
    return lista;
  }

  /// Aprobados que el almacenero todavía tiene que alistar, y que no salen
  /// ya en [requierenAtencion] (los urgentes van allá).
  List<Requerimiento> get pendientesDeAlistar =>
      _requerimientos.where((r) => r.estado == EstadoRequerimiento.aprobado && !r.urgente).toList();

  /// Ya alistados, esperando que se entreguen (sin los urgentes, que van en
  /// [requierenAtencion]).
  List<Requerimiento> get listosParaEntrega =>
      _requerimientos.where((r) => r.estado == EstadoRequerimiento.listo && !r.urgente).toList();

  /// Checklists registrados cuyas herramientas todavía no se confirma que salieron.
  List<ChecklistHerramientas> get salidasPorConfirmar =>
      _herramientas.where((h) => h.estado == EstadoHerramientas.registrado).toList();

  List<ChecklistHerramientas> get herramientasPorDevolver =>
      _herramientas.where((h) => h.estado == EstadoHerramientas.pendiente).toList();

  Requerimiento? requerimientoPorId(int id) {
    for (final r in _requerimientos) {
      if (r.id == id) return r;
    }
    return null;
  }

  ChecklistHerramientas? herramientasPorId(int id) {
    for (final h in _herramientas) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// Solo para pruebas: carga salidas de herramientas sin pasar por la base.
  @visibleForTesting
  void herramientasParaPrueba(List<ChecklistHerramientas> lista) {
    _herramientas = lista;
    _cargando = false;
  }

  Future<void> cargar() async {
    try {
      final requerimientos = await DbHelper.instance.getRequerimientos();
      final herramientas = await DbHelper.instance.getChecklistsHerramientas();
      final anteriores = await DbHelper.instance.countChecklistsGuardados();
      _requerimientos = requerimientos;
      _herramientas = herramientas;
      _checklistsAnteriores = anteriores;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  // Con servidor, otras personas cambian cosas todo el tiempo: la lista se
  // vuelve a pedir cada cierto rato (y al volver a la app) y las pantallas se
  // actualizan solas, para que todos vean lo mismo.
  Timer? _reloj;
  bool _actualizando = false;
  static const _cadaCuanto = Duration(seconds: 20);

  /// Cuántos requerimientos esperan aprobación y no se habían visto antes
  /// (para avisar al encargado en el celular).
  final ValueNotifier<List<Requerimiento>> nuevosPorAprobar = ValueNotifier(const []);

  void iniciarActualizacionAutomatica() {
    if (!DbHelper.instance.esServidor || _reloj != null) return;
    _reloj = Timer.periodic(_cadaCuanto, (_) => actualizarEnSegundoPlano());
  }

  void detenerActualizacionAutomatica() {
    _reloj?.cancel();
    _reloj = null;
  }

  static String _firma(Iterable<(int?, int)> filas) => filas.map((f) => '${f.$1}:${f.$2}').join(',');

  /// Vuelve a pedir la lista sin mostrar "cargando"; solo avisa a las
  /// pantallas si algo cambió.
  Future<void> actualizarEnSegundoPlano() async {
    if (_actualizando) return;
    _actualizando = true;
    try {
      final requerimientos = await DbHelper.instance.getRequerimientos();
      final herramientas = await DbHelper.instance.getChecklistsHerramientas();
      final cambio = _firma(requerimientos.map((r) => (r.id, r.version))) != _firma(_requerimientos.map((r) => (r.id, r.version))) ||
          _firma(herramientas.map((h) => (h.id, h.version))) != _firma(_herramientas.map((h) => (h.id, h.version)));
      if (!cambio) return;
      final conocidos = {for (final r in _requerimientos) r.id};
      final nuevos = [
        for (final r in requerimientos)
          if (r.estado == EstadoRequerimiento.pendiente && !conocidos.contains(r.id)) r,
      ];
      _requerimientos = requerimientos;
      _herramientas = herramientas;
      notifyListeners();
      if (nuevos.isNotEmpty) nuevosPorAprobar.value = nuevos;
    } catch (_) {
      // Sin conexión por un momento: se reintenta en el próximo ciclo.
    } finally {
      _actualizando = false;
    }
  }

  /// Si el servidor rechaza un cambio porque otra persona ya lo modificó, se
  /// actualiza lo que se ve para partir de lo último (el aviso con el motivo
  /// lo muestra la app, ver main.dart).
  Future<T> _conAvisos<T>(Future<T> Function() accion) async {
    try {
      return await accion();
    } on ApiError catch (e) {
      if (e.conflicto) await actualizarEnSegundoPlano();
      rethrow;
    }
  }

  @override
  void dispose() {
    detenerActualizacionAutomatica();
    nuevosPorAprobar.dispose();
    super.dispose();
  }

  /// Correlativo propio de cada tipo de documento (REQ-0001, HER-0001), en
  /// preferencias y no según el id de la base: así un número nunca se
  /// repite aunque se elimine un registro.
  static Future<String> _siguienteNumero(String clave, String prefijo) async {
    final siguiente = await DbHelper.instance.siguienteCorrelativo(clave);
    return '$prefijo-${siguiente.toString().padLeft(4, '0')}';
  }

  Future<Requerimiento> crearRequerimiento({
    required String obra,
    required String solicitante,
    required bool urgente,
    String? observaciones,
    required List<ChecklistCategoriaState> categorias,
  }) async {
    final nuevo = Requerimiento(
      numero: await _siguienteNumero('requerimiento', 'REQ'),
      obra: obra,
      solicitante: solicitante,
      urgente: urgente,
      fechaCreacion: DateTime.now(),
      observaciones: observaciones,
      categoriasJson: categoriasAJson(soloMarcados(categorias)),
    );
    final guardado = await _conAvisos(() => DbHelper.instance.insertarRequerimiento(nuevo));
    _requerimientos = [guardado, ..._requerimientos];
    notifyListeners();
    return guardado;
  }

  Future<Requerimiento> aprobarRequerimiento(Requerimiento r, {String? aprobadoPor}) {
    return _actualizarRequerimiento(
      r.copyWith(
        estado: EstadoRequerimiento.aprobado,
        fechaAprobacion: DateTime.now(),
        aprobadoPor: aprobadoPor,
      ),
    );
  }

  /// Guarda el avance del alistado (los materiales marcados en [categorias],
  /// cada uno con quién y cuándo). Si ya están todos alistados, el
  /// requerimiento pasa solo a "listo para entrega"; si no, sigue pendiente
  /// de alistar para que otra persona continúe.
  Future<Requerimiento> guardarAlistado(Requerimiento r, {required List<ChecklistCategoriaState> categorias}) {
    final items = categorias.expand((c) => c.items).toList();
    final todo = items.isNotEmpty && items.every((i) => i.alistado == true);
    final quienes = <String>[];
    for (final i in items) {
      final n = (i.alistadoPor ?? '').trim();
      if (i.alistado == true && n.isNotEmpty && !quienes.contains(n)) quienes.add(n);
    }
    final conAvance = r.copyWith(categoriasJson: categoriasAJson(categorias));
    return _actualizarRequerimiento(
      todo
          ? conAvance.copyWith(
              estado: EstadoRequerimiento.listo,
              fechaListo: DateTime.now(),
              alistadoPor: quienes.join(', '),
            )
          : conAvance,
    );
  }

  /// Anota en las observaciones qué se cambió y cuándo, para que quede el
  /// rastro de las ediciones.
  static String? _conBitacora(String observaciones, List<String> resumen) {
    final base = observaciones.trim();
    if (resumen.isEmpty) return base.isEmpty ? null : base;
    final ahora = DateTime.now();
    final fecha =
        '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')} ${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}';
    final linea = '[Editado $fecha] ${resumen.join('; ')}';
    return base.isEmpty ? linea : '$base\n$linea';
  }

  /// Lo agregado con "Guardar también en la lista" pasa a la lista base.
  static Future<void> _guardarEnListas(List<ItemCatalogoChecklist> items) async {
    for (final item in items) {
      final existentes = await DbHelper.instance.getItemsCatalogoChecklist(item.tipo);
      final yaEsta = existentes.any((e) => e.nombre.toLowerCase() == item.nombre.toLowerCase());
      if (!yaEsta) await DbHelper.instance.agregarItemCatalogoChecklist(item);
    }
  }

  /// Edita un requerimiento ya registrado (datos, ítems, cantidades,
  /// precios). Si se le agregó algo cuando ya estaba listo o entregado,
  /// vuelve a "aprobado, pendiente de alistar" para alistar lo nuevo.
  Future<Requerimiento> editarRequerimiento(Requerimiento r, ResultadoEdicion e) async {
    await _guardarEnListas(e.paraLaLista);
    final json = categoriasAJson(e.categorias);
    final observaciones = _conBitacora(e.observaciones, e.resumen);
    final reabre = e.nuevos > 0 &&
        (r.estado == EstadoRequerimiento.listo || r.estado == EstadoRequerimiento.entregado);
    var nuevo = reabre
        ? r.reabierto(
            categoriasJson: json, obra: e.obra, solicitante: e.persona, urgente: e.urgente, observaciones: observaciones)
        : r.copyWith(
            categoriasJson: json, obra: e.obra, solicitante: e.persona, urgente: e.urgente, observaciones: observaciones);
    // Si quedó aprobado y ya todo está alistado (por ejemplo, se quitó lo
    // único que faltaba), pasa a listo.
    if (nuevo.estado == EstadoRequerimiento.aprobado && nuevo.todoAlistado) {
      nuevo = nuevo.copyWith(
        estado: EstadoRequerimiento.listo,
        fechaListo: DateTime.now(),
        alistadoPor: nuevo.quienesAlistaron.join(', '),
      );
    }
    return _actualizarRequerimiento(nuevo);
  }

  /// Edita una salida de herramientas ya registrada. Las herramientas
  /// agregadas cuando la salida ya se confirmó se dan por salidas; si estaba
  /// conforme, vuelve a "pendiente de devolución".
  Future<ChecklistHerramientas> editarHerramientas(ChecklistHerramientas h, ResultadoEdicion e) async {
    await _guardarEnListas(e.paraLaLista);
    final yaSalio = h.estado != EstadoHerramientas.registrado;
    if (yaSalio) {
      for (final c in e.categorias) {
        for (final i in c.items) {
          if (i.agregadoDespues && i.salio == null) i.salio = true;
        }
      }
    }
    final json = categoriasAJson(e.categorias);
    final observaciones = _conBitacora(e.observaciones, e.resumen);
    final reabre = e.nuevos > 0 && h.estado == EstadoHerramientas.conforme;
    final nuevo = reabre
        ? h.reabierto(categoriasJson: json, obra: e.obra, responsable: e.persona, observaciones: observaciones)
        : h.copyWith(categoriasJson: json, obra: e.obra, responsable: e.persona, observaciones: observaciones);
    return _actualizarHerramientas(nuevo);
  }

  /// El almacenero terminó de preparar los materiales.
  Future<Requerimiento> marcarListoParaEntrega(Requerimiento r, {String? alistadoPor}) {
    return _actualizarRequerimiento(
      r.copyWith(
        estado: EstadoRequerimiento.listo,
        fechaListo: DateTime.now(),
        alistadoPor: alistadoPor,
      ),
    );
  }

  Future<Requerimiento> entregarRequerimiento(Requerimiento r, {String? recibidoPor}) {
    return _actualizarRequerimiento(
      r.copyWith(
        estado: EstadoRequerimiento.entregado,
        fechaEntrega: DateTime.now(),
        recibidoPor: recibidoPor,
      ),
    );
  }

  Future<Requerimiento> _actualizarRequerimiento(Requerimiento actualizado) async {
    final guardado = await _conAvisos(() => DbHelper.instance.actualizarRequerimiento(actualizado));
    _requerimientos = [
      for (final r in _requerimientos) r.id == guardado.id ? guardado : r,
    ];
    notifyListeners();
    return guardado;
  }

  Future<void> eliminarRequerimiento(Requerimiento r) async {
    await _conAvisos(() => DbHelper.instance.eliminarRequerimiento(r.id!));
    _requerimientos = _requerimientos.where((x) => x.id != r.id).toList();
    notifyListeners();
  }

  Future<ChecklistHerramientas> registrarSalida({
    required String obra,
    required String responsable,
    String? observaciones,
    required List<ChecklistCategoriaState> categorias,
    String? maleta,
  }) async {
    final nuevo = ChecklistHerramientas(
      numero: await _siguienteNumero('herramientas', 'HER'),
      obra: obra,
      responsable: responsable,
      maleta: maleta,
      fechaSalida: DateTime.now(),
      observaciones: observaciones,
      categoriasJson: categoriasAJson(soloMarcados(categorias)),
    );
    final guardado = await _conAvisos(() => DbHelper.instance.insertarChecklistHerramientas(nuevo));
    _herramientas = [guardado, ..._herramientas];
    notifyListeners();
    return guardado;
  }

  /// Almacén confirma qué herramientas salieron (las que se marcaron una
  /// por una en [categorias]): quedan pendientes de devolución.
  Future<ChecklistHerramientas> confirmarSalida(
    ChecklistHerramientas h, {
    required String confirmadaPor,
    required List<ChecklistCategoriaState> categorias,
    String? observaciones,
  }) {
    final extra = (observaciones ?? '').trim();
    final previas = (h.observaciones ?? '').trim();
    return _actualizarHerramientas(
      h.copyWith(
        estado: EstadoHerramientas.pendiente,
        fechaConfirmacionSalida: DateTime.now(),
        salidaConfirmadaPor: confirmadaPor,
        categoriasJson: categoriasAJson(categorias),
        observaciones: extra.isEmpty ? previas : (previas.isEmpty ? extra : '$previas\nSalida: $extra'),
      ),
    );
  }

  Future<ChecklistHerramientas> confirmarDevolucion(
    ChecklistHerramientas h, {
    required String encargado,
    String? observaciones,
    List<ChecklistCategoriaState>? categorias,
  }) async {
    return _actualizarHerramientas(
      h.copyWith(
        estado: EstadoHerramientas.conforme,
        fechaDevolucion: DateTime.now(),
        encargado: encargado,
        observacionesDevolucion: observaciones,
        categoriasJson: categorias == null ? null : categoriasAJson(categorias),
      ),
    );
  }

  Future<ChecklistHerramientas> _actualizarHerramientas(ChecklistHerramientas actualizado) async {
    final guardado = await _conAvisos(() => DbHelper.instance.actualizarChecklistHerramientas(actualizado));
    _herramientas = [
      for (final x in _herramientas) x.id == guardado.id ? guardado : x,
    ];
    notifyListeners();
    return guardado;
  }

  Future<void> eliminarHerramientas(ChecklistHerramientas h) async {
    await _conAvisos(() => DbHelper.instance.eliminarChecklistHerramientas(h.id!));
    _herramientas = _herramientas.where((x) => x.id != h.id).toList();
    notifyListeners();
  }

  /// Tras borrar un checklist de la versión anterior, para que Almacén deje
  /// de ofrecer el acceso cuando ya no queda ninguno.
  Future<void> recontarChecklistsAnteriores() async {
    _checklistsAnteriores = await DbHelper.instance.countChecklistsGuardados();
    notifyListeners();
  }
}
