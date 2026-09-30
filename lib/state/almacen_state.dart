import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../models/requerimiento.dart';
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

  /// Aprobados que todavía no se entregan y que no salen ya en
  /// [requierenAtencion] (los urgentes van allá).
  List<Requerimiento> get aprobadosPorEntregar =>
      _requerimientos.where((r) => r.estado == EstadoRequerimiento.aprobado && !r.urgente).toList();

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

  /// Correlativo propio de cada tipo de documento (REQ-0001, HER-0001), en
  /// preferencias y no según el id de la base: así un número nunca se
  /// repite aunque se elimine un registro.
  static Future<String> _siguienteNumero(String clave, String prefijo) async {
    final prefs = await SharedPreferences.getInstance();
    final siguiente = (prefs.getInt(clave) ?? 0) + 1;
    await prefs.setInt(clave, siguiente);
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
      numero: await _siguienteNumero('requerimiento_correlativo', 'REQ'),
      obra: obra,
      solicitante: solicitante,
      urgente: urgente,
      fechaCreacion: DateTime.now(),
      observaciones: observaciones,
      categoriasJson: categoriasAJson(soloMarcados(categorias)),
    );
    final id = await DbHelper.instance.insertarRequerimiento(nuevo);
    final guardado = nuevo.copyWith(id: id);
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
    await DbHelper.instance.actualizarRequerimiento(actualizado);
    _requerimientos = [
      for (final r in _requerimientos) r.id == actualizado.id ? actualizado : r,
    ];
    notifyListeners();
    return actualizado;
  }

  Future<void> eliminarRequerimiento(Requerimiento r) async {
    await DbHelper.instance.eliminarRequerimiento(r.id!);
    _requerimientos = _requerimientos.where((x) => x.id != r.id).toList();
    notifyListeners();
  }

  Future<ChecklistHerramientas> registrarSalida({
    required String obra,
    required String responsable,
    String? observaciones,
    required List<ChecklistCategoriaState> categorias,
  }) async {
    final nuevo = ChecklistHerramientas(
      numero: await _siguienteNumero('herramientas_correlativo', 'HER'),
      obra: obra,
      responsable: responsable,
      fechaSalida: DateTime.now(),
      observaciones: observaciones,
      categoriasJson: categoriasAJson(soloMarcados(categorias)),
    );
    final id = await DbHelper.instance.insertarChecklistHerramientas(nuevo);
    final guardado = nuevo.copyWith(id: id);
    _herramientas = [guardado, ..._herramientas];
    notifyListeners();
    return guardado;
  }

  Future<ChecklistHerramientas> confirmarDevolucion(
    ChecklistHerramientas h, {
    required String encargado,
    String? observaciones,
  }) async {
    final actualizado = h.copyWith(
      estado: EstadoHerramientas.conforme,
      fechaDevolucion: DateTime.now(),
      encargado: encargado,
      observacionesDevolucion: observaciones,
    );
    await DbHelper.instance.actualizarChecklistHerramientas(actualizado);
    _herramientas = [
      for (final x in _herramientas) x.id == actualizado.id ? actualizado : x,
    ];
    notifyListeners();
    return actualizado;
  }

  Future<void> eliminarHerramientas(ChecklistHerramientas h) async {
    await DbHelper.instance.eliminarChecklistHerramientas(h.id!);
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
