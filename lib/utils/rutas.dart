/// Nombres de las rutas de las listas de Almacén: al terminar de crear un
/// requerimiento o una salida, se vuelve hasta la lista (si se llegó desde
/// ahí) sacando del camino las pantallas del checklist ya usadas.
class Rutas {
  Rutas._();
  static const listaRequerimientos = 'lista_requerimientos';
  static const listaHerramientas = 'lista_herramientas';
}
