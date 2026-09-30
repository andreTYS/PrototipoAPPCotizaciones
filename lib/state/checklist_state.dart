import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/checklist_categoria.dart';
import '../models/item_catalogo_checklist.dart';
import '../services/db_helper.dart';
import '../utils/checklist_estilo.dart';

/// Estado de un checklist en armado (un requerimiento de materiales o una
/// salida de herramientas, según [tipo]): carga las categorías base una sola
/// vez — las del Excel más lo que se haya agregado a la lista desde la app —
/// y controla el avance secuencial (categoría por categoría, obligatorio
/// hacia adelante, libre hacia atrás) para que no se pase nada por alto.
///
/// Vive mientras la app está abierta (ver [BorradoresChecklist]): si se sale
/// a mitad de camino, al volver se puede continuar donde se quedó.
class ChecklistState extends ChangeNotifier {
  final TipoChecklist tipo;

  ChecklistState(this.tipo);

  List<ChecklistCategoriaState> _categorias = [];
  int _indice = 0;
  bool _cargando = true;
  String? _error;

  List<ChecklistCategoriaState> get categorias => _categorias;
  int get indice => _indice;
  bool get cargando => _cargando;
  String? get error => _error;

  ChecklistCategoriaState get categoriaActual => _categorias[_indice];
  bool get esPrimeraCategoria => _indice == 0;
  bool get esUltimaCategoria => _indice == _categorias.length - 1;

  /// Si ya avanzó de categoría, marcó algo, o agregó algún extra — para
  /// decidir si hace falta preguntar antes de empezar uno nuevo.
  bool get tieneProgreso => _indice > 0 || totalMarcados > 0 || _categorias.any((c) => c.items.any((i) => i.esExtra));

  int get totalItems => _categorias.fold(0, (s, c) => s + c.items.length);
  int get totalMarcados => _categorias.fold(0, (s, c) => s + c.totalMarcados);

  /// Avance por CATEGORÍAS ya completadas, no por ítems marcados: esto es
  /// una revisión de qué llevar (no siempre se lleva todo), así que pasar
  /// de categoría sube el % aunque no se haya marcado nada en ella. Arranca
  /// en 0% en la primera categoría y solo llega a 100% al terminar la
  /// última (en el resumen), no mientras aún se está en ella.
  int get porcentajeAvance => _categorias.isEmpty ? 0 : ((_indice / _categorias.length) * 100).round();

  Future<void> cargar() async {
    if (_categorias.isNotEmpty) return;
    await _cargarDesdeAssets();
  }

  Future<void> _cargarDesdeAssets() async {
    try {
      final raw = await rootBundle.loadString('assets/checklist_seed.json');
      final List<dynamic> data = jsonDecode(raw);
      final seed = data
          .map((e) => ChecklistCategoriaSeed.fromMap(Map<String, dynamic>.from(e)))
          .where((c) => tipoDeCategoriaSeed(c.categoria) == tipo)
          .toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

      final categorias = seed
          .map(
            (c) => ChecklistCategoriaState(
              nombre: c.categoria,
              items: c.items.map((texto) => ChecklistItemEntry(texto: capitalizarPrimeraLetra(texto))).toList(),
            ),
          )
          .toList();

      final agregados = await DbHelper.instance.getItemsCatalogoChecklist(tipo);
      for (final item in agregados) {
        _incorporar(categorias, item);
      }

      _categorias = categorias;
      _indice = 0;
      _error = null;
    } catch (e) {
      // Sin este catch, un catálogo de checklist corrupto deja la pantalla
      // girando en el spinner para siempre, sin ninguna pista de qué falló.
      _error = 'No se pudo cargar el checklist.\n\n$e';
    }
    _cargando = false;
    notifyListeners();
  }

  /// Suma un ítem agregado a la lista base en su categoría (o en una nueva,
  /// al final, si esa categoría no existe en el Excel) — sin repetirlo si ya
  /// había uno con el mismo nombre.
  static void _incorporar(List<ChecklistCategoriaState> categorias, ItemCatalogoChecklist item) {
    final nombre = capitalizarPrimeraLetra(item.nombre.trim());
    if (nombre.isEmpty) return;
    var categoria = _buscarCategoria(categorias, item.categoria);
    if (categoria == null) {
      categoria = ChecklistCategoriaState(nombre: item.categoria.trim().toUpperCase(), items: []);
      categorias.add(categoria);
    }
    final yaEsta = categoria.items.any((i) => i.texto.toLowerCase() == nombre.toLowerCase());
    if (!yaEsta) categoria.items.add(ChecklistItemEntry(texto: nombre, unidad: item.unidad));
  }

  static ChecklistCategoriaState? _buscarCategoria(List<ChecklistCategoriaState> categorias, String nombre) {
    final buscado = quitarNumeroCategoria(nombre.trim()).toUpperCase();
    for (final c in categorias) {
      if (quitarNumeroCategoria(c.nombre).toUpperCase() == buscado) return c;
    }
    return null;
  }

  /// Nombres de las categorías de este checklist, tal como se guardan (con
  /// su número del Excel) — para elegir dónde va un ítem nuevo de la lista.
  Future<List<String>> nombresCategorias() async {
    await cargar();
    return _categorias.map((c) => c.nombre).toList();
  }

  /// Un ítem recién agregado a la lista base también aparece en el
  /// checklist que se esté armando ahora (sin marcar), sin tener que
  /// empezarlo de nuevo.
  void incorporarItemCatalogo(ItemCatalogoChecklist item) {
    if (_categorias.isEmpty) return;
    _incorporar(_categorias, item);
    notifyListeners();
  }

  /// Si se quita un ítem de la lista base, sale también del checklist en
  /// armado — salvo que ya estuviera marcado (eso ya es parte del pedido).
  void quitarItemCatalogo(ItemCatalogoChecklist item) {
    final categoria = _buscarCategoria(_categorias, item.categoria);
    if (categoria == null) return;
    categoria.items.removeWhere(
      (i) => !i.marcado && !i.esExtra && i.texto.toLowerCase() == item.nombre.trim().toLowerCase(),
    );
    notifyListeners();
  }

  void toggleItem(int itemIndex) {
    final item = categoriaActual.items[itemIndex];
    item.cantidad = item.marcado ? 0 : 1;
    notifyListeners();
  }

  /// Ajusta cuántas unidades de un ítem se van a llevar — lo usa el stepper
  /// que aparece junto al casillero una vez marcado. Bajar a 0 equivale a
  /// desmarcarlo (sigue en la lista, solo que no se lleva).
  void setCantidad(int categoriaIndex, int itemIndex, int cantidad) {
    _categorias[categoriaIndex].items[itemIndex].cantidad = cantidad < 0 ? 0 : cantidad;
    notifyListeners();
  }

  /// Agrega un ítem nuevo (ya marcado) a una categoría cualquiera, solo para
  /// este checklist.
  void agregarItemEn(int categoriaIndex, String texto, {bool esProducto = false}) {
    final limpio = texto.trim();
    if (limpio.isEmpty) return;
    _categorias[categoriaIndex].items.add(
          ChecklistItemEntry(
              texto: capitalizarPrimeraLetra(limpio), cantidad: 1, esExtra: true, esProducto: esProducto),
        );
    notifyListeners();
  }

  void avanzar() {
    if (esUltimaCategoria) return;
    _indice++;
    notifyListeners();
  }

  void retroceder() {
    if (esPrimeraCategoria) return;
    _indice--;
    notifyListeners();
  }

  /// Solo permite saltar a categorías ya visitadas (hacia atrás) — avanzar
  /// siempre pasa por [avanzar], una por una, para no saltarse ninguna.
  void irACategoria(int i) {
    if (i < 0 || i > _indice) return;
    _indice = i;
    notifyListeners();
  }

  /// Vuelve a armar todas las categorías desde cero (sin marcar, sin
  /// extras) para empezar uno nuevo.
  Future<void> reiniciar() async {
    _categorias = [];
    _cargando = true;
    notifyListeners();
    await _cargarDesdeAssets();
  }
}

/// Los dos checklists que se pueden estar armando a la vez (uno de
/// materiales para un requerimiento y uno de herramientas), cada uno con su
/// propio avance. Se entregan a cada pantalla del recorrido con
/// ChangeNotifierProvider.value (ver abrirChecklist en checklist_screen).
class BorradoresChecklist {
  final materiales = ChecklistState(TipoChecklist.materiales);
  final herramientas = ChecklistState(TipoChecklist.herramientas);

  ChecklistState de(TipoChecklist tipo) => tipo == TipoChecklist.materiales ? materiales : herramientas;
}
