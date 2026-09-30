/// Registro de un checklist de obra ya finalizado — lo que se muestra en
/// la pestaña "Historial" (filtrado junto a las cotizaciones) y en su
/// pantalla de detalle. [categoriasJson] guarda las categorías con
/// cada ítem (marcado o no) tal como quedaron al guardar, para poder
/// mostrar el detalle estructurado después (ver checklist_state.dart:
/// categoriasDesdeJson / ChecklistCategoriaState.toJson).
class ChecklistGuardado {
  final int? id;
  final String responsable;
  final DateTime fecha;
  final int totalItems;
  final int itemsMarcados;
  final String resumenTexto;
  final String? archivoPdf;
  final String categoriasJson;

  ChecklistGuardado({
    this.id,
    required this.responsable,
    required this.fecha,
    required this.totalItems,
    required this.itemsMarcados,
    required this.resumenTexto,
    this.archivoPdf,
    this.categoriasJson = '[]',
  });

  factory ChecklistGuardado.fromMap(Map<String, dynamic> map) {
    return ChecklistGuardado(
      id: map['id'] as int?,
      responsable: (map['responsable'] ?? '').toString(),
      fecha: DateTime.parse(map['fecha'] as String),
      totalItems: (map['total_items'] as num).toInt(),
      itemsMarcados: (map['items_marcados'] as num).toInt(),
      resumenTexto: (map['resumen_texto'] ?? '').toString(),
      archivoPdf: map['archivo_pdf'] as String?,
      categoriasJson: (map['categorias_json'] ?? '[]').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'responsable': responsable,
      'fecha': fecha.toIso8601String(),
      'total_items': totalItems,
      'items_marcados': itemsMarcados,
      'resumen_texto': resumenTexto,
      'archivo_pdf': archivoPdf,
      'categorias_json': categoriasJson,
    };
  }
}
