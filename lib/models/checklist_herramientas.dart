import 'checklist_categoria.dart';

/// Las herramientas salen a obra (quedan pendientes de devolución) hasta que
/// un encargado confirma que volvieron todas: ahí quedan "conforme".
enum EstadoHerramientas { pendiente, conforme }

extension EstadoHerramientasTexto on EstadoHerramientas {
  String get etiqueta => switch (this) {
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
  final EstadoHerramientas estado;
  final DateTime fechaSalida;
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
    this.estado = EstadoHerramientas.pendiente,
    required this.fechaSalida,
    this.fechaDevolucion,
    this.encargado,
    this.observaciones,
    this.observacionesDevolucion,
    required this.categoriasJson,
  });

  late final List<ChecklistCategoriaState> categorias = soloMarcados(categoriasDesdeJson(categoriasJson));
  late final int totalItems = categorias.fold(0, (s, c) => s + c.items.length);
  late final int totalUnidades = categorias.fold(0, (s, c) => s + c.totalUnidades);

  bool get conforme => estado == EstadoHerramientas.conforme;

  ChecklistHerramientas copyWith({
    int? id,
    EstadoHerramientas? estado,
    DateTime? fechaDevolucion,
    String? encargado,
    String? observacionesDevolucion,
  }) {
    return ChecklistHerramientas(
      id: id ?? this.id,
      numero: numero,
      obra: obra,
      responsable: responsable,
      estado: estado ?? this.estado,
      fechaSalida: fechaSalida,
      fechaDevolucion: fechaDevolucion ?? this.fechaDevolucion,
      encargado: encargado ?? this.encargado,
      observaciones: observaciones,
      observacionesDevolucion: observacionesDevolucion ?? this.observacionesDevolucion,
      categoriasJson: categoriasJson,
    );
  }

  factory ChecklistHerramientas.fromMap(Map<String, dynamic> map) {
    return ChecklistHerramientas(
      id: map['id'] as int?,
      numero: (map['numero'] ?? '').toString(),
      obra: (map['obra'] ?? '').toString(),
      responsable: (map['responsable'] ?? '').toString(),
      estado: EstadoHerramientas.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoHerramientas.pendiente,
      ),
      fechaSalida: DateTime.parse(map['fecha_salida'] as String),
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
      'estado': estado.name,
      'fecha_salida': fechaSalida.toIso8601String(),
      'fecha_devolucion': fechaDevolucion?.toIso8601String(),
      'encargado': encargado,
      'observaciones': observaciones,
      'observaciones_devolucion': observacionesDevolucion,
      'categorias_json': categoriasJson,
    };
  }
}
