import 'dart:convert';

/// Para qué se arma un checklist: pedir materiales a almacén (un
/// requerimiento) o registrar las herramientas que salen a obra y que
/// después tienen que volver.
enum TipoChecklist { materiales, herramientas }

/// Una categoría base del checklist de obra, tal como viene del catálogo
/// semilla (assets/checklist_seed.json), extraído del Excel real de la
/// empresa (herramientas y materiales para instalación Victron — 5
/// categorías, 99 ítems en total).
class ChecklistCategoriaSeed {
  final int orden;
  final String categoria;
  final List<String> items;

  ChecklistCategoriaSeed({
    required this.orden,
    required this.categoria,
    required this.items,
  });

  factory ChecklistCategoriaSeed.fromMap(Map<String, dynamic> map) {
    return ChecklistCategoriaSeed(
      orden: map['orden'] as int,
      categoria: map['categoria'] as String,
      items: List<String>.from(map['items'] as List),
    );
  }
}

/// El Excel trae todas las categorías juntas: la de herramientas arma el
/// checklist de herramientas, y el resto (conduit, fotovoltaico, eléctrico,
/// techo) son los materiales que se piden en un requerimiento.
TipoChecklist tipoDeCategoriaSeed(String categoria) =>
    categoria.toUpperCase().contains('HERRAMIENTA') ? TipoChecklist.herramientas : TipoChecklist.materiales;

/// Estándar de formato para el nombre de un ítem: mayúscula inicial, resto
/// tal cual — así se vean parejos sin importar cómo vengan del catálogo
/// base o de lo que haya tipeado quien agrega uno a mano.
String capitalizarPrimeraLetra(String texto) {
  if (texto.isEmpty) return texto;
  return texto[0].toUpperCase() + texto.substring(1);
}

/// Un ítem dentro de una categoría del checklist: puede venir del catálogo
/// base (Excel o agregado a la lista por alguien) o haberse agregado a mano
/// solo para este checklist desde "Añadir objeto a este paso" (en cuyo
/// caso [esExtra] es true, y [esProducto] indica si vino del buscador del
/// catálogo de productos en vez de ser una nota libre).
///
/// Esta es una lista de "qué llevar", no de "qué ya se revisó": marcar un
/// ítem lo deja en [cantidad] 1 y desde ahí se puede subir o bajar con un
/// stepper. [marcado] queda como getter derivado (cantidad > 0) para no
/// duplicar el estado.
class ChecklistItemEntry {
  final String texto;
  int cantidad;
  final bool esExtra;
  final bool esProducto;

  /// Unidad en que se cuenta (ej. "m" para cable); los ítems del Excel no
  /// la traen, así que es opcional y se muestra solo si existe.
  final String? unidad;

  ChecklistItemEntry({
    required this.texto,
    this.cantidad = 0,
    this.esExtra = false,
    this.esProducto = false,
    this.unidad,
  });

  bool get marcado => cantidad > 0;

  /// "× 3" o "× 3 m" — como se muestra la cantidad en pantalla y en el PDF.
  String get cantidadTexto {
    final u = (unidad ?? '').trim();
    return u.isEmpty ? '× $cantidad' : '× $cantidad $u';
  }

  factory ChecklistItemEntry.fromJson(Map<String, dynamic> json) {
    final cantidadJson = json['cantidad'];
    return ChecklistItemEntry(
      texto: (json['texto'] ?? '').toString(),
      // Checklists guardados antes de que existiera "cantidad" solo tenían
      // 'marcado' (true/false) — se traduce a cantidad 1/0 para no perder
      // el detalle histórico.
      cantidad: cantidadJson is num ? cantidadJson.toInt() : (json['marcado'] == true ? 1 : 0),
      esExtra: json['es_extra'] == true,
      esProducto: json['es_producto'] == true,
      unidad: json['unidad'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'texto': texto,
        'cantidad': cantidad,
        'es_extra': esExtra,
        'es_producto': esProducto,
        if (unidad != null) 'unidad': unidad,
      };
}

class ChecklistCategoriaState {
  final String nombre;
  final List<ChecklistItemEntry> items;

  ChecklistCategoriaState({required this.nombre, required this.items});

  factory ChecklistCategoriaState.fromJson(Map<String, dynamic> json) {
    return ChecklistCategoriaState(
      nombre: (json['nombre'] ?? '').toString(),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => ChecklistItemEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'items': items.map((i) => i.toJson()).toList(),
      };

  int get totalMarcados => items.where((i) => i.marcado).length;
  int get totalUnidades => items.fold(0, (s, i) => s + i.cantidad);
}

/// Reconstruye las categorías guardadas de un checklist (para su pantalla
/// de detalle o su PDF) — si el registro es viejo y no tiene este detalle,
/// o el JSON está corrupto, devuelve una lista vacía en vez de fallar.
List<ChecklistCategoriaState> categoriasDesdeJson(String json) {
  if (json.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(json) as List<dynamic>;
    return decoded.map((e) => ChecklistCategoriaState.fromJson(Map<String, dynamic>.from(e))).toList();
  } catch (_) {
    return [];
  }
}

/// Solo lo que se marcó (cantidad > 0), sin categorías vacías — lo que de
/// verdad se pide o sale de almacén, que es lo que queda registrado.
List<ChecklistCategoriaState> soloMarcados(List<ChecklistCategoriaState> categorias) {
  return [
    for (final c in categorias)
      if (c.items.any((i) => i.marcado))
        ChecklistCategoriaState(nombre: c.nombre, items: c.items.where((i) => i.marcado).toList()),
  ];
}

String categoriasAJson(List<ChecklistCategoriaState> categorias) =>
    jsonEncode(categorias.map((c) => c.toJson()).toList());
