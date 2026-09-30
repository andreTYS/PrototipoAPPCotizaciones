import 'checklist_categoria.dart';

/// Ítem que alguien agregó a la lista base de un checklist (además de los
/// del Excel) para que aparezca en todos los que se armen de ahí en
/// adelante — a diferencia de "Añadir objeto a este paso", que solo lo
/// suma al checklist que se está armando en ese momento.
class ItemCatalogoChecklist {
  final int? id;
  final TipoChecklist tipo;

  /// Nombre exacto de la categoría donde va (ej. "2. FOTOVOLTAICO"); si no
  /// coincide con ninguna de las del Excel, se arma una categoría nueva.
  final String categoria;
  final String nombre;
  final String? unidad;
  final DateTime fecha;

  ItemCatalogoChecklist({
    this.id,
    required this.tipo,
    required this.categoria,
    required this.nombre,
    this.unidad,
    required this.fecha,
  });

  factory ItemCatalogoChecklist.fromMap(Map<String, dynamic> map) {
    return ItemCatalogoChecklist(
      id: map['id'] as int?,
      tipo: TipoChecklist.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => TipoChecklist.materiales,
      ),
      categoria: (map['categoria'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      unidad: map['unidad'] as String?,
      fecha: DateTime.tryParse((map['fecha'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo.name,
      'categoria': categoria,
      'nombre': nombre,
      'unidad': unidad,
      'fecha': fecha.toIso8601String(),
    };
  }
}
