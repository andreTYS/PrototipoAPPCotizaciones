/// Los datos de un requerimiento o de una salida de herramientas, que se
/// piden ANTES de empezar el checklist o elegir la maleta: la obra, quién
/// pide / quién se lleva las herramientas, y (en requerimientos) si es
/// urgente. Las observaciones son opcionales.
class DatosAlmacen {
  final String obra;
  final String persona;
  final String observaciones;
  final bool urgente;

  const DatosAlmacen({required this.obra, required this.persona, this.observaciones = '', this.urgente = false});

  DatosAlmacen copyWith({String? obra, String? persona, String? observaciones, bool? urgente}) => DatosAlmacen(
        obra: obra ?? this.obra,
        persona: persona ?? this.persona,
        observaciones: observaciones ?? this.observaciones,
        urgente: urgente ?? this.urgente,
      );
}
