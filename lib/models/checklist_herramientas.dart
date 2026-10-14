import 'checklist_categoria.dart';

/// Recorrido de una salida de herramientas: se registra con el checklist,
/// almacén confirma que salieron (desde ahí quedan pendientes de devolución)
/// y, cuando vuelven todas, un encargado confirma la devolución: "conforme".
enum EstadoHerramientas { registrado, pendiente, conforme }

extension EstadoHerramientasTexto on EstadoHerramientas {
  String get etiqueta => switch (this) {
        EstadoHerramientas.registrado => 'Registrado',
        EstadoHerramientas.pendiente => 'Pendiente devolución',
        EstadoHerramientas.conforme => 'Conforme',
      };
}

/// Registro de una salida de herramientas armado con el checklist de
/// siempre. [categoriasJson] guarda solo lo que salió, con su cantidad.
class ChecklistHerramientas {
  final int? id;
  final String numero;
  final String obra;
  final String responsable;

  /// Si salió una maleta armada (ej. "Maleta 1") en vez del checklist.
  final String? maleta;
  final EstadoHerramientas estado;

  /// Cuándo se registró el checklist (antes de que salgan las herramientas).
  final DateTime fechaSalida;

  /// Cuándo almacén confirmó que las herramientas salieron, y quién.
  final DateTime? fechaConfirmacionSalida;
  final String? salidaConfirmadaPor;
  final DateTime? fechaDevolucion;
  final String? encargado;
  final String? observaciones;
  final String? observacionesDevolucion;
  final String categoriasJson;

  ChecklistHerramientas({
    this.id,
    required this.numero,
    required this.obra,
    required this.responsable,
    this.maleta,
    this.estado = EstadoHerramientas.registrado,
    required this.fechaSalida,
    this.fechaConfirmacionSalida,
    this.salidaConfirmadaPor,
    this.fechaDevolucion,
    this.encargado,
    this.observaciones,
    this.observacionesDevolucion,
    required this.categoriasJson,
  });

  late final List<ChecklistCategoriaState> categorias = _conMarcasPorDefecto(soloMarcados(categoriasDesdeJson(categoriasJson)));

  /// Las salidas guardadas antes de que se marcara herramienta por
  /// herramienta no traen las marcas: si ya salieron se dan por salidas, y
  /// si ya fueron conformes, por devueltas.
  List<ChecklistCategoriaState> _conMarcasPorDefecto(List<ChecklistCategoriaState> categorias) {
    for (final c in categorias) {
      for (final i in c.items) {
        if (i.salio == null && estado != EstadoHerramientas.registrado) i.salio = true;
        if (i.volvio == null && estado == EstadoHerramientas.conforme && i.salio != false) i.volvio = true;
      }
    }
    return categorias;
  }

  Iterable<ChecklistItemEntry> get _items => categorias.expand((c) => c.items);

  /// Herramientas que no salieron en la confirmación de salida.
  late final List<ChecklistItemEntry> noSalieron = [for (final i in _items) if (i.salio == false) i];

  /// Herramientas que salieron y no volvieron al confirmar la devolución.
  late final List<ChecklistItemEntry> noVolvieron = [for (final i in _items) if (i.salio != false && i.volvio == false) i];

  /// Cuántas salieron a obra (todas, mientras no se confirme la salida).
  int get totalSalieron => _items.where((i) => i.salio != false).length;
  late final int totalItems = categorias.fold(0, (s, c) => s + c.items.length);
  late final int totalUnidades = categorias.fold(0, (s, c) => s + c.totalUnidades);

  bool get conforme => estado == EstadoHerramientas.conforme;

  /// Ya salieron a obra (pendientes de devolución o devueltas).
  bool get salidaConfirmada => estado != EstadoHerramientas.registrado;

  ChecklistHerramientas copyWith({
    int? id,
    EstadoHerramientas? estado,
    DateTime? fechaConfirmacionSalida,
    String? salidaConfirmadaPor,
    DateTime? fechaDevolucion,
    String? encargado,
    String? observacionesDevolucion,
    // Solo lo usa AlmacenState, para guardar de vuelta el reserva_id/
    // prestamo_id de cada ítem después de sincronizar con el ERP.
    String? categoriasJson,
    String? observaciones,
  }) {
    return ChecklistHerramientas(
      id: id ?? this.id,
      numero: numero,
      obra: obra,
      responsable: responsable,
      maleta: maleta,
      estado: estado ?? this.estado,
      fechaSalida: fechaSalida,
      fechaConfirmacionSalida: fechaConfirmacionSalida ?? this.fechaConfirmacionSalida,
      salidaConfirmadaPor: salidaConfirmadaPor ?? this.salidaConfirmadaPor,
      fechaDevolucion: fechaDevolucion ?? this.fechaDevolucion,
      encargado: encargado ?? this.encargado,
      observaciones: observaciones ?? this.observaciones,
      observacionesDevolucion: observacionesDevolucion ?? this.observacionesDevolucion,
      categoriasJson: categoriasJson ?? this.categoriasJson,
    );
  }

  factory ChecklistHerramientas.fromMap(Map<String, dynamic> map) {
    return ChecklistHerramientas(
      id: map['id'] as int?,
      numero: (map['numero'] ?? '').toString(),
      obra: (map['obra'] ?? '').toString(),
      responsable: (map['responsable'] ?? '').toString(),
      maleta: map['maleta'] as String?,
      estado: EstadoHerramientas.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoHerramientas.pendiente,
      ),
      fechaSalida: DateTime.parse(map['fecha_salida'] as String),
      fechaConfirmacionSalida: DateTime.tryParse((map['fecha_confirmacion_salida'] ?? '').toString()),
      salidaConfirmadaPor: map['salida_confirmada_por'] as String?,
      fechaDevolucion: DateTime.tryParse((map['fecha_devolucion'] ?? '').toString()),
      encargado: map['encargado'] as String?,
      observaciones: map['observaciones'] as String?,
      observacionesDevolucion: map['observaciones_devolucion'] as String?,
      categoriasJson: (map['categorias_json'] ?? '[]').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'numero': numero,
      'obra': obra,
      'responsable': responsable,
      'maleta': maleta,
      'estado': estado.name,
      'fecha_salida': fechaSalida.toIso8601String(),
      'fecha_confirmacion_salida': fechaConfirmacionSalida?.toIso8601String(),
      'salida_confirmada_por': salidaConfirmadaPor,
      'fecha_devolucion': fechaDevolucion?.toIso8601String(),
      'encargado': encargado,
      'observaciones': observaciones,
      'observaciones_devolucion': observacionesDevolucion,
      'categorias_json': categoriasJson,
    };
  }
}
