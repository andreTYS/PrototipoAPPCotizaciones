import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../models/requerimiento.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';
import '../services/erp_config_service.dart';

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

  /// Al aprobar, se aparta stock real en el ERP para cada ítem que tenga SKU
  /// (los de texto libre no tienen contraparte real, siguen siendo solo del
  /// checklist). Best-effort: si el ERP no está configurado o falla, el
  /// requerimiento se aprueba igual — el jefe de obra no debe quedar
  /// bloqueado por un problema de red, mismo criterio que el resto de la
  /// app. El detalle de qué se pudo o no reservar queda en debugPrint.
  Future<Requerimiento> aprobarRequerimiento(Requerimiento r, {String? aprobadoPor}) async {
    final categorias = categoriasDesdeJson(r.categoriasJson);
    await _reservarItemsEnErp(categorias);
    return _actualizarRequerimiento(
      r.copyWith(
        estado: EstadoRequerimiento.aprobado,
        fechaAprobacion: DateTime.now(),
        aprobadoPor: aprobadoPor,
        categoriasJson: categoriasAJson(categorias),
      ),
    );
  }

  /// Al entregar, cada ítem con una reserva activa se despacha de verdad
  /// (descuenta stock físico); si el producto es retornable, el ERP crea
  /// el préstamo correspondiente, que después cierra
  /// [confirmarDevolucion]. Un ítem que falla en el ERP queda con su
  /// reserva_id intacto para poder reintentarse en una próxima entrega.
  Future<Requerimiento> entregarRequerimiento(Requerimiento r, {String? recibidoPor}) async {
    final categorias = categoriasDesdeJson(r.categoriasJson);
    await _despacharItemsEnErp(categorias);
    return _actualizarRequerimiento(
      r.copyWith(
        estado: EstadoRequerimiento.entregado,
        fechaEntrega: DateTime.now(),
        recibidoPor: recibidoPor,
        categoriasJson: categoriasAJson(categorias),
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

  /// Si el requerimiento ya estaba aprobado (con stock apartado en el ERP)
  /// y se elimina antes de entregarse, la reserva quedaría trabada para
  /// siempre del lado del ERP si no se libera acá.
  Future<void> eliminarRequerimiento(Requerimiento r) async {
    if (r.estado == EstadoRequerimiento.aprobado) {
      await _liberarItemsEnErp(categoriasDesdeJson(r.categoriasJson));
    }
    await DbHelper.instance.eliminarRequerimiento(r.id!);
    _requerimientos = _requerimientos.where((x) => x.id != r.id).toList();
    notifyListeners();
  }

  /// La salida de herramientas no tiene aprobación previa (a diferencia de
  /// un requerimiento): al registrarla, cada ítem con SKU se reserva y se
  /// despacha de una — si el producto es retornable, el ERP crea el
  /// préstamo que después cierra [confirmarDevolucion]. Best-effort, igual
  /// que el resto: si el ERP falla, la salida se sigue registrando local.
  Future<ChecklistHerramientas> registrarSalida({
    required String obra,
    required String responsable,
    String? observaciones,
    required List<ChecklistCategoriaState> categorias,
  }) async {
    final marcados = soloMarcados(categorias);
    await _reservarYDespacharItemsEnErp(marcados);
    final nuevo = ChecklistHerramientas(
      numero: await _siguienteNumero('herramientas_correlativo', 'HER'),
      obra: obra,
      responsable: responsable,
      fechaSalida: DateTime.now(),
      observaciones: observaciones,
      categoriasJson: categoriasAJson(marcados),
    );
    final id = await DbHelper.instance.insertarChecklistHerramientas(nuevo);
    final guardado = nuevo.copyWith(id: id);
    _herramientas = [guardado, ..._herramientas];
    notifyListeners();
    return guardado;
  }

  /// Cierra en el ERP el préstamo de cada ítem que se logró despachar como
  /// tal (repone su stock físico real) antes de marcar el checklist como
  /// conforme. Un ítem que falla queda con su prestamo_id intacto, para
  /// poder reintentar la devolución más adelante.
  Future<ChecklistHerramientas> confirmarDevolucion(
    ChecklistHerramientas h, {
    required String encargado,
    String? observaciones,
  }) async {
    final categorias = categoriasDesdeJson(h.categoriasJson);
    await _devolverItemsEnErp(categorias);
    final actualizado = h.copyWith(
      estado: EstadoHerramientas.conforme,
      fechaDevolucion: DateTime.now(),
      encargado: encargado,
      observacionesDevolucion: observaciones,
      categoriasJson: categoriasAJson(categorias),
    );
    await DbHelper.instance.actualizarChecklistHerramientas(actualizado);
    _herramientas = [
      for (final x in _herramientas) x.id == actualizado.id ? actualizado : x,
    ];
    notifyListeners();
    return actualizado;
  }

  /// Si el checklist todavía tenía herramientas prestadas (pendiente
  /// devolución) y se elimina antes de confirmarla, los préstamos quedarían
  /// abiertos para siempre del lado del ERP si no se cierran acá.
  Future<void> eliminarHerramientas(ChecklistHerramientas h) async {
    if (h.estado == EstadoHerramientas.pendiente) {
      await _devolverItemsEnErp(categoriasDesdeJson(h.categoriasJson));
    }
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

  // -------------------- Sincronización con el ERP --------------------
  //
  // Todo lo de acá abajo es best-effort: si el ERP no está configurado (ver
  // Conexión con el ERP) o alguna llamada falla, se registra con debugPrint
  // y se sigue de largo — el requerimiento/checklist ya quedó guardado
  // local, que es lo que de verdad no se puede perder en el campo.

  /// Credenciales + almacén configurados, o null si falta alguno — en cuyo
  /// caso el llamador debe seguir de largo sin tocar el ERP.
  Future<(String, String, String)?> _credencialesErp() async {
    if (!await ErpConfigService.estaConfigurado()) return null;
    final baseUrl = await ErpConfigService.getBaseUrl();
    final token = await ErpConfigService.getToken();
    final almacen = await ErpConfigService.getAlmacenCodigo();
    if (baseUrl == null || token == null || almacen == null || almacen.isEmpty) return null;
    return (baseUrl, token, almacen);
  }

  Iterable<ChecklistItemEntry> _itemsDe(List<ChecklistCategoriaState> categorias) sync* {
    for (final categoria in categorias) {
      yield* categoria.items;
    }
  }

  /// Reserva stock para cada ítem con SKU que todavía no tenga una reserva
  /// activa — al aprobar un requerimiento.
  Future<void> _reservarItemsEnErp(List<ChecklistCategoriaState> categorias) async {
    final credenciales = await _credencialesErp();
    if (credenciales == null) return;
    final (baseUrl, token, almacen) = credenciales;
    for (final item in _itemsDe(categorias)) {
      if (item.sku == null || item.reservaId != null) continue;
      try {
        item.reservaId = await ApiService.reservarStock(
          baseUrl: baseUrl,
          token: token,
          sku: item.sku!,
          cantidad: item.cantidad,
          warehouseCode: almacen,
        );
      } catch (e) {
        debugPrint('No se pudo reservar ${item.sku} (${item.texto}) en el ERP: $e');
      }
    }
  }

  /// Despacha (descuenta stock físico real) cada ítem con una reserva
  /// activa — al confirmar la entrega de un requerimiento ya aprobado.
  Future<void> _despacharItemsEnErp(List<ChecklistCategoriaState> categorias) async {
    final credenciales = await _credencialesErp();
    if (credenciales == null) return;
    final (baseUrl, token, _) = credenciales;
    for (final item in _itemsDe(categorias)) {
      if (item.reservaId == null) continue;
      try {
        item.prestamoId = await ApiService.despacharReserva(
          baseUrl: baseUrl,
          token: token,
          reservaId: item.reservaId!,
          cantidad: item.cantidad,
        );
        item.reservaId = null;
      } catch (e) {
        debugPrint('No se pudo despachar la reserva ${item.reservaId} (${item.texto}) en el ERP: $e');
      }
    }
  }

  /// Reserva y despacha de una sola vez — la salida de una herramienta no
  /// tiene aprobación previa que separe ambos pasos como en un requerimiento.
  Future<void> _reservarYDespacharItemsEnErp(List<ChecklistCategoriaState> categorias) async {
    final credenciales = await _credencialesErp();
    if (credenciales == null) return;
    final (baseUrl, token, almacen) = credenciales;
    for (final item in _itemsDe(categorias)) {
      if (item.sku == null || item.prestamoId != null) continue;
      try {
        final reservaId = await ApiService.reservarStock(
          baseUrl: baseUrl,
          token: token,
          sku: item.sku!,
          cantidad: item.cantidad,
          warehouseCode: almacen,
        );
        item.prestamoId = await ApiService.despacharReserva(
          baseUrl: baseUrl,
          token: token,
          reservaId: reservaId,
          cantidad: item.cantidad,
        );
      } catch (e) {
        debugPrint('No se pudo registrar la salida de ${item.sku} (${item.texto}) en el ERP: $e');
      }
    }
  }

  /// Cierra el préstamo de cada ítem que sigue prestado — al confirmar la
  /// devolución de un checklist de herramientas, o al eliminar uno que
  /// todavía tenía herramientas afuera.
  Future<void> _devolverItemsEnErp(List<ChecklistCategoriaState> categorias) async {
    final credenciales = await _credencialesErp();
    if (credenciales == null) return;
    final (baseUrl, token, _) = credenciales;
    for (final item in _itemsDe(categorias)) {
      if (item.prestamoId == null) continue;
      try {
        await ApiService.devolverPrestamo(baseUrl: baseUrl, token: token, prestamoId: item.prestamoId!);
        item.prestamoId = null;
      } catch (e) {
        debugPrint('No se pudo devolver el préstamo ${item.prestamoId} (${item.texto}) en el ERP: $e');
      }
    }
  }

  /// Libera la reserva de cada ítem que seguía activa — al eliminar un
  /// requerimiento ya aprobado antes de que se entregara.
  Future<void> _liberarItemsEnErp(List<ChecklistCategoriaState> categorias) async {
    final credenciales = await _credencialesErp();
    if (credenciales == null) return;
    final (baseUrl, token, _) = credenciales;
    for (final item in _itemsDe(categorias)) {
      if (item.reservaId == null) continue;
      try {
        await ApiService.liberarReserva(baseUrl: baseUrl, token: token, reservaId: item.reservaId!);
        item.reservaId = null;
      } catch (e) {
        debugPrint('No se pudo liberar la reserva ${item.reservaId} (${item.texto}) en el ERP: $e');
      }
    }
  }
}
