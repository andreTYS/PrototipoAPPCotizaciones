import 'checklist_categoria.dart';

/// Una herramienta dentro de una maleta armada. [imagen] es la ruta de su
/// foto: un asset de la app (assets/maletas/...) o un archivo guardado en
/// el celular cuando se le tomó la foto desde Configuración.
class ItemMaleta {
  final int? id;
  final String nombre;
  final String? imagen;

  const ItemMaleta({this.id, required this.nombre, this.imagen});
}

/// Un nivel / compartimento de la maleta, con lo que lleva.
class CategoriaMaleta {
  final String nombre;
  final List<ItemMaleta> items;

  const CategoriaMaleta({required this.nombre, required this.items});
}

/// Maleta de herramientas ya armada (ej. "Maleta 1"): sale completa a obra,
/// sin tener que recorrer el checklist ítem por ítem. Las maletas viven en
/// la base del celular (se arman, cambian y eliminan desde Configuración);
/// la primera vez se cargan desde assets/maletas/maletas.json.
class Maleta {
  final int? id;
  final String nombre;
  final List<CategoriaMaleta> categorias;

  const Maleta({this.id, required this.nombre, required this.categorias});

  int get totalItems => categorias.fold(0, (s, c) => s + c.items.length);

  /// Lo que se guarda en el checklist de herramientas: cada herramienta de
  /// la maleta con cantidad 1 y su foto, agrupada por nivel.
  List<ChecklistCategoriaState> comoCategoriasChecklist() => [
        for (final c in categorias)
          ChecklistCategoriaState(
            nombre: c.nombre,
            items: [
              for (final i in c.items) ChecklistItemEntry(texto: i.nombre, cantidad: 1, imagen: i.imagen),
            ],
          ),
      ];
}
