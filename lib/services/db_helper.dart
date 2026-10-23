import 'package:flutter/foundation.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_guardado.dart';
import '../models/checklist_herramientas.dart';
import '../models/cotizacion_guardada.dart';
import '../models/item_catalogo_checklist.dart';
import '../models/maleta.dart';
import '../models/producto.dart';
import '../models/requerimiento.dart';
import 'db_api.dart';
import 'db_local.dart';
import 'modo.dart';

/// Todo lo que la app lee o guarda pasa por aquí. Hay dos formas de
/// responder: [DbLocal] (la base del celular, sin servidor) y [DbApi] (el
/// servidor compartido, donde todos los usuarios ven los mismos datos).
/// Las pantallas no saben cuál de las dos están usando.
abstract class DbHelper {
  static DbHelper instance = modoServidor ? DbApi.instancia : DbLocal.instancia;

  /// ¿Los datos viven en el servidor y los comparten varios usuarios?
  bool get esServidor;

  /// Sube cada vez que cambia el catálogo de productos (se agrega, edita o
  /// elimina uno): las pantallas que lo muestran se actualizan solas.
  ValueNotifier<int> get catalogoCambios;

  /// Solo para pruebas: cierra la conexión y la olvida.
  Future<void> cerrarParaPruebas();

  /// Siguiente número de un documento ('cotizacion', 'requerimiento',
  /// 'herramientas'); con servidor lo reparte la base para no repetirse.
  Future<int> siguienteCorrelativo(String clave);

  /// ¿Es correcta la clave para editar documentos ya registrados?
  Future<bool> verificarClaveEdicion(String clave);

  // Productos -----------------------------------------------------------
  Future<int> countTotal();
  Future<void> replaceAll(List<Producto> productos);
  Future<void> actualizarCatalogoBase();
  Future<void> actualizarCatalogoBaseForzado();
  Future<void> agregarProductoManual(Producto producto);
  Future<void> actualizarProductoManual(Producto producto);
  Future<void> eliminarProductoManual(int id);
  Future<List<String>> getCategorias();
  Future<List<Producto>> getProductosPorCategoria(String categoria);
  Future<Map<String, List<Producto>>> getTodosAgrupados();
  Future<List<Producto>> buscar(String query);

  // Cotizaciones --------------------------------------------------------
  Future<void> guardarCotizacion(CotizacionGuardada cotizacion);
  Future<List<CotizacionGuardada>> getCotizacionesGuardadas();
  Future<CotizacionGuardada> actualizarCotizacion(CotizacionGuardada cotizacion);
  Future<void> eliminarCotizacion(int id);

  // Checklists de versiones anteriores de la app (solo en el celular) ----
  Future<int> guardarChecklist(ChecklistGuardado checklist);
  Future<void> actualizarChecklist(int id, ChecklistGuardado checklist);
  Future<void> eliminarChecklist(int id);
  Future<List<ChecklistGuardado>> getChecklistsGuardados();
  Future<int> countChecklistsGuardados();

  // Almacén -------------------------------------------------------------
  Future<Requerimiento> insertarRequerimiento(Requerimiento requerimiento);
  Future<Requerimiento> actualizarRequerimiento(Requerimiento requerimiento);
  Future<void> eliminarRequerimiento(int id);
  Future<List<Requerimiento>> getRequerimientos();
  Future<ChecklistHerramientas> insertarChecklistHerramientas(ChecklistHerramientas checklist);
  Future<ChecklistHerramientas> actualizarChecklistHerramientas(ChecklistHerramientas checklist);
  Future<void> eliminarChecklistHerramientas(int id);
  Future<List<ChecklistHerramientas>> getChecklistsHerramientas();

  // Listas del checklist ------------------------------------------------
  Future<List<ItemCatalogoChecklist>> getItemsCatalogoChecklist(TipoChecklist tipo);
  Future<int> agregarItemCatalogoChecklist(ItemCatalogoChecklist item);
  Future<void> actualizarItemCatalogoChecklist(ItemCatalogoChecklist item, {required String categoriaAnterior});
  Future<void> renombrarCategoriaCatalogo(TipoChecklist tipo, String anterior, String nueva);
  Future<void> eliminarItemCatalogoChecklist(int id);

  // Maletas -------------------------------------------------------------
  Future<List<Maleta>> getMaletas();
  Future<int> crearMaleta(String nombre);
  Future<void> renombrarMaleta(int id, String nombre);
  Future<void> eliminarMaleta(int id);
  Future<int> agregarItemMaleta(int maletaId, {required String nivel, required String nombre, String? imagen});
  Future<void> actualizarItemMaleta(int itemId, {required String nivel, required String nombre, String? imagen});
  Future<void> eliminarItemMaleta(int itemId);
  Future<void> renombrarNivelMaleta(int maletaId, String anterior, String nuevo);
}
