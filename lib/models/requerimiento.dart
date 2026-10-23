import 'checklist_categoria.dart';

/// Recorrido de un requerimiento de materiales: se crea pendiente, el jefe
/// de obra lo aprueba (con su código) — desde ahí queda "pendiente de
/// alistar" como recordatorio para el almacenero —, el almacenero confirma
/// que está listo para entrega cuando terminó de prepararlo, y por último
/// confirma la entrega.
enum EstadoRequerimiento { pendiente, aprobado, listo, entregado }

extension EstadoRequerimientoTexto on EstadoRequerimiento {
  String get etiqueta => switch (this) {
        EstadoRequerimiento.pendiente => 'Pendiente aprobación',
        EstadoRequerimiento.aprobado => 'Aprobado por jefe de obra',
        EstadoRequerimiento.listo => 'Listo para entrega',
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
  final DateTime? fechaListo;
  final String? alistadoPor;
  final DateTime? fechaEntrega;
  final String? recibidoPor;
  final String? observaciones;
  final String categoriasJson;

  /// Con servidor: la versión del registro cuando se leyó. Si otra persona lo
  /// cambia en el medio, el servidor avisa en vez de pisar su cambio.
  final int version;

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
    this.fechaListo,
    this.alistadoPor,
    this.fechaEntrega,
    this.recibidoPor,
    this.observaciones,
    required this.categoriasJson,
    this.version = 0,
  });

  late final List<ChecklistCategoriaState> categorias = soloMarcados(categoriasDesdeJson(categoriasJson));
  late final int totalItems = categorias.fold(0, (s, c) => s + c.items.length);
  late final int totalUnidades = categorias.fold(0, (s, c) => s + c.totalUnidades);

  /// Total estimado en soles (cantidad × precio de cada material). Los
  /// requerimientos anteriores a los precios no lo tienen ([conPrecios]).
  late final double totalPrecio = totalPrecioCategorias(categorias);
  late final bool conPrecios = categoriasConPrecios(categorias);

  bool get entregado => estado == EstadoRequerimiento.entregado;

  /// Aprobado y todavía sin alistar: el recordatorio para el almacenero.
  bool get pendienteDeAlistar => estado == EstadoRequerimiento.aprobado;

  /// Cuántos materiales ya se alistaron (se van marcando de a poco).
  int get totalAlistados =>
      categorias.fold(0, (s, c) => s + c.items.where((i) => i.alistado == true).length);

  bool get todoAlistado => totalItems > 0 && totalAlistados == totalItems;

  /// Quiénes alistaron algo, en el orden en que empezaron.
  List<String> get quienesAlistaron {
    final nombres = <String>[];
    for (final c in categorias) {
      for (final i in c.items) {
        final n = (i.alistadoPor ?? '').trim();
        if (i.alistado == true && n.isNotEmpty && !nombres.contains(n)) nombres.add(n);
      }
    }
    return nombres;
  }

  /// Lo que se muestra en el Inicio: todo lo pendiente de aprobar, y lo
  /// urgente mientras no se haya entregado.
  bool get requiereAtencion => !entregado && (urgente || estado == EstadoRequerimiento.pendiente);

  Requerimiento copyWith({
    int? id,
    EstadoRequerimiento? estado,
    DateTime? fechaAprobacion,
    String? aprobadoPor,
    DateTime? fechaListo,
    String? alistadoPor,
    DateTime? fechaEntrega,
    String? recibidoPor,
    String? categoriasJson,
    String? obra,
    String? solicitante,
    bool? urgente,
    String? observaciones,
  }) {
    return Requerimiento(
      id: id ?? this.id,
      numero: numero,
      obra: obra ?? this.obra,
      solicitante: solicitante ?? this.solicitante,
      urgente: urgente ?? this.urgente,
      estado: estado ?? this.estado,
      fechaCreacion: fechaCreacion,
      fechaAprobacion: fechaAprobacion ?? this.fechaAprobacion,
      aprobadoPor: aprobadoPor ?? this.aprobadoPor,
      fechaListo: fechaListo ?? this.fechaListo,
      alistadoPor: alistadoPor ?? this.alistadoPor,
      fechaEntrega: fechaEntrega ?? this.fechaEntrega,
      recibidoPor: recibidoPor ?? this.recibidoPor,
      observaciones: observaciones ?? this.observaciones,
      categoriasJson: categoriasJson ?? this.categoriasJson,
      version: version,
    );
  }

  /// Vuelve a "aprobado, pendiente de alistar" (al agregarle algo después
  /// de que ya estaba listo o entregado): se conserva quién y cuándo lo
  /// aprobó, y se limpian los pasos que hay que volver a hacer.
  Requerimiento reabierto({String? categoriasJson, String? obra, String? solicitante, bool? urgente, String? observaciones}) {
    return Requerimiento(
      id: id,
      numero: numero,
      obra: obra ?? this.obra,
      solicitante: solicitante ?? this.solicitante,
      urgente: urgente ?? this.urgente,
      estado: EstadoRequerimiento.aprobado,
      fechaCreacion: fechaCreacion,
      fechaAprobacion: fechaAprobacion,
      aprobadoPor: aprobadoPor,
      observaciones: observaciones ?? this.observaciones,
      categoriasJson: categoriasJson ?? this.categoriasJson,
      version: version,
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
      fechaListo: DateTime.tryParse((map['fecha_listo'] ?? '').toString()),
      alistadoPor: map['alistado_por'] as String?,
      fechaEntrega: DateTime.tryParse((map['fecha_entrega'] ?? '').toString()),
      recibidoPor: map['recibido_por'] as String?,
      observaciones: map['observaciones'] as String?,
      categoriasJson: (map['categorias_json'] ?? '[]').toString(),
      version: (map['version'] as num?)?.toInt() ?? 0,
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
      'fecha_listo': fechaListo?.toIso8601String(),
      'alistado_por': alistadoPor,
      'fecha_entrega': fechaEntrega?.toIso8601String(),
      'recibido_por': recibidoPor,
      'observaciones': observaciones,
      'categorias_json': categoriasJson,
    };
  }
}
