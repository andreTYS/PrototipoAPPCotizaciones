import 'checklist_categoria.dart';

/// Recorrido de un requerimiento de materiales: se crea pendiente, el jefe
/// de obra lo aprueba (con su código) y almacén confirma la entrega.
enum EstadoRequerimiento { pendiente, aprobado, entregado }

extension EstadoRequerimientoTexto on EstadoRequerimiento {
  String get etiqueta => switch (this) {
        EstadoRequerimiento.pendiente => 'Pendiente aprobación',
        EstadoRequerimiento.aprobado => 'Aprobado por jefe de obra',
        EstadoRequerimiento.entregado => 'Entregado',
      };
}

/// Pedido de materiales a almacén armado con el checklist de siempre
/// (categoría por categoría). [categoriasJson] guarda solo lo que se pidió,
/// con su cantidad — es lo que se muestra en el detalle y en el PDF.
class Requerimiento {
  final int? id;
  final String numero;
  final String obra;
  final String solicitante;
  final bool urgente;
  final EstadoRequerimiento estado;
  final DateTime fechaCreacion;
  final DateTime? fechaAprobacion;
  final String? aprobadoPor;
  final DateTime? fechaEntrega;
  final String? recibidoPor;
  final String? observaciones;
  final String categoriasJson;

  Requerimiento({
    this.id,
    required this.numero,
    required this.obra,
    required this.solicitante,
    this.urgente = false,
    this.estado = EstadoRequerimiento.pendiente,
    required this.fechaCreacion,
    this.fechaAprobacion,
    this.aprobadoPor,
    this.fechaEntrega,
    this.recibidoPor,
    this.observaciones,
    required this.categoriasJson,
  });

  late final List<ChecklistCategoriaState> categorias = soloMarcados(categoriasDesdeJson(categoriasJson));
  late final int totalItems = categorias.fold(0, (s, c) => s + c.items.length);
  late final int totalUnidades = categorias.fold(0, (s, c) => s + c.totalUnidades);

  bool get entregado => estado == EstadoRequerimiento.entregado;

  /// Lo que se muestra en el Inicio: todo lo pendiente de aprobar, y lo
  /// urgente mientras no se haya entregado.
  bool get requiereAtencion => !entregado && (urgente || estado == EstadoRequerimiento.pendiente);

  Requerimiento copyWith({
    int? id,
    EstadoRequerimiento? estado,
    DateTime? fechaAprobacion,
    String? aprobadoPor,
    DateTime? fechaEntrega,
    String? recibidoPor,
  }) {
    return Requerimiento(
      id: id ?? this.id,
      numero: numero,
      obra: obra,
      solicitante: solicitante,
      urgente: urgente,
      estado: estado ?? this.estado,
      fechaCreacion: fechaCreacion,
      fechaAprobacion: fechaAprobacion ?? this.fechaAprobacion,
      aprobadoPor: aprobadoPor ?? this.aprobadoPor,
      fechaEntrega: fechaEntrega ?? this.fechaEntrega,
      recibidoPor: recibidoPor ?? this.recibidoPor,
      observaciones: observaciones,
      categoriasJson: categoriasJson,
    );
  }

  factory Requerimiento.fromMap(Map<String, dynamic> map) {
    return Requerimiento(
      id: map['id'] as int?,
      numero: (map['numero'] ?? '').toString(),
      obra: (map['obra'] ?? '').toString(),
      solicitante: (map['solicitante'] ?? '').toString(),
      urgente: map['urgente'] == 1,
      estado: EstadoRequerimiento.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoRequerimiento.pendiente,
      ),
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      fechaAprobacion: DateTime.tryParse((map['fecha_aprobacion'] ?? '').toString()),
      aprobadoPor: map['aprobado_por'] as String?,
      fechaEntrega: DateTime.tryParse((map['fecha_entrega'] ?? '').toString()),
      recibidoPor: map['recibido_por'] as String?,
      observaciones: map['observaciones'] as String?,
      categoriasJson: (map['categorias_json'] ?? '[]').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'numero': numero,
      'obra': obra,
      'solicitante': solicitante,
      'urgente': urgente ? 1 : 0,
      'estado': estado.name,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_aprobacion': fechaAprobacion?.toIso8601String(),
      'aprobado_por': aprobadoPor,
      'fecha_entrega': fechaEntrega?.toIso8601String(),
      'recibido_por': recibidoPor,
      'observaciones': observaciones,
      'categorias_json': categoriasJson,
    };
  }
}
