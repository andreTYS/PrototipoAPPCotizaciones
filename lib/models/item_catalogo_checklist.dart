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

  /// Precio por defecto en soles (solo materiales).
  final double? precio;

  /// Posición en la lista: las categorías salen en el orden de su primer
  /// ítem, y dentro de cada una, por este número.
  final int? orden;

  /// Si viene de la lista base de la empresa (Excel) en vez de haberse
  /// agregado desde la app. Todo se puede editar y quitar igual.
  final bool esBase;

  ItemCatalogoChecklist({
    this.id,
    required this.tipo,
    required this.categoria,
    required this.nombre,
    this.unidad,
    required this.fecha,
    this.precio,
    this.orden,
    this.esBase = false,
  });

  bool get tipoEsMateriales => tipo == TipoChecklist.materiales;

  ItemCatalogoChecklist copyWith({String? categoria, String? nombre, String? unidad, double? precio, bool sinPrecio = false}) =>
      ItemCatalogoChecklist(
        id: id,
        tipo: tipo,
        categoria: categoria ?? this.categoria,
        nombre: nombre ?? this.nombre,
        unidad: unidad ?? this.unidad,
        fecha: fecha,
        precio: sinPrecio ? null : (precio ?? this.precio),
        orden: orden,
        esBase: esBase,
      );

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
      precio: (map['precio'] as num?)?.toDouble(),
      orden: map['orden'] as int?,
      esBase: map['base'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo.name,
      'categoria': categoria,
      'nombre': nombre,
      'unidad': unidad,
      'fecha': fecha.toIso8601String(),
      'precio': precio,
      'base': esBase ? 1 : 0,
    };
  }
}
