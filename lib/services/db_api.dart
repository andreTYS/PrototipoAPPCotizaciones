import 'package:flutter/foundation.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_guardado.dart';
import '../models/checklist_herramientas.dart';
import '../models/cotizacion_guardada.dart';
import '../models/item_catalogo_checklist.dart';
import '../models/maleta.dart';
import '../models/producto.dart';
import '../models/requerimiento.dart';
import 'api_cliente.dart';
import 'db_helper.dart';

/// Los datos en el servidor compartido: todos los usuarios leen y escriben en
/// la misma base de datos (PostgreSQL) a través de la API. Si alguien más
/// cambia un documento mientras se está viendo, el servidor avisa (versión)
/// en vez de pisar su cambio.
class DbApi implements DbHelper {
  DbApi._();
  static final DbApi instancia = DbApi._();

  final _api = ApiCliente.instancia;

  @override
  final ValueNotifier<int> catalogoCambios = ValueNotifier(0);

  @override
  bool get esServidor => true;

  @override
  Future<void> cerrarParaPruebas() async {
    _catalogo = null;
  }

  @override
  Future<int> siguienteCorrelativo(String clave) async {
    final datos = await _api.post('correlativos/$clave');
    return (datos['valor'] as num).toInt();
  }

  /// El servidor revisa la clave y da un permiso corto para editar.
  @override
  Future<bool> verificarClaveEdicion(String clave) async {
    try {
      final datos = await _api.post('clave-edicion', {'clave': clave.trim()});
      _api.tokenEdicion = datos['token_edicion'] as String;
      return true;
    } on ApiError catch (e) {
      if (e.codigo == 403) return false;
      rethrow;
    }
  }

  List<Map<String, dynamic>> _lista(dynamic datos) =>
      (datos as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // ---------------------------------------------------------------------
  // Productos: el catálogo se pide una vez y se reutiliza (búsqueda, voz)
  // ---------------------------------------------------------------------

  List<Producto>? _catalogo;
  DateTime? _catalogoPedido;
  static const _vigencia = Duration(minutes: 2);

  Future<List<Producto>> _productos() async {
    final vigente = _catalogo != null && _catalogoPedido != null && DateTime.now().difference(_catalogoPedido!) < _vigencia;
    if (!vigente) {
      _catalogo = _lista(await _api.get('productos')).map(Producto.fromMap).toList();
      _catalogoPedido = DateTime.now();
    }
    return _catalogo!;
  }

  void _catalogoCambio() {
    _catalogo = null;
    catalogoCambios.value++;
  }

  @override
  Future<int> countTotal() async => (await _productos()).length;

  @override
  Future<void> replaceAll(List<Producto> productos) =>
      throw UnsupportedError('El catálogo se administra en el servidor.');

  @override
  Future<void> actualizarCatalogoBase() async {}

  @override
  Future<void> actualizarCatalogoBaseForzado() async {}

  Map<String, dynamic> _cuerpoProducto(Producto p) => {
        'nombre': p.nombre,
        'categoria_producto': p.categoriaProducto,
        'precio_venta': p.precioVenta,
        'costo': p.costo,
        'referencia_interna': p.referenciaInterna,
        'unidad_medida': p.unidadMedida,
        'archivo_imagen': p.archivoImagen,
        'imagen_url': p.imagenUrl,
      };

  @override
  Future<void> agregarProductoManual(Producto producto) async {
    await _api.post('productos', _cuerpoProducto(producto));
    _catalogoCambio();
  }

  @override
  Future<void> actualizarProductoManual(Producto producto) async {
    await _api.put('productos/${producto.id}', _cuerpoProducto(producto));
    _catalogoCambio();
  }

  @override
  Future<void> eliminarProductoManual(int id) async {
    await _api.delete('productos/$id');
    _catalogoCambio();
  }

  @override
  Future<List<String>> getCategorias() async {
    final categorias = {for (final p in await _productos()) p.categoriaProducto}.toList()..sort();
    return categorias;
  }

  @override
  Future<List<Producto>> getProductosPorCategoria(String categoria) async =>
      [for (final p in await _productos()) if (p.categoriaProducto == categoria) p];

  @override
  Future<Map<String, List<Producto>>> getTodosAgrupados() async {
    final agrupado = <String, List<Producto>>{};
    for (final p in await _productos()) {
      agrupado.putIfAbsent(p.categoriaProducto, () => []).add(p);
    }
    return agrupado;
  }

  @override
  Future<List<Producto>> buscar(String query) async {
    final q = query.toLowerCase();
    final encontrados = [
      for (final p in await _productos())
        if (p.nombre.toLowerCase().contains(q) || (p.referenciaInterna ?? '').toLowerCase().contains(q)) p,
    ]..sort((a, b) => a.nombre.compareTo(b.nombre));
    return encontrados.take(150).toList();
  }

  // ---------------------------------------------------------------------
  // Cotizaciones
  // ---------------------------------------------------------------------

  @override
  Future<void> guardarCotizacion(CotizacionGuardada cotizacion) async {
    await _api.post('cotizaciones', cotizacion.toMap());
  }

  @override
  Future<List<CotizacionGuardada>> getCotizacionesGuardadas() async =>
      _lista(await _api.get('cotizaciones')).map(CotizacionGuardada.fromMap).toList();

  @override
  Future<CotizacionGuardada> actualizarCotizacion(CotizacionGuardada cotizacion) async {
    final fila = await _api.put('cotizaciones/${cotizacion.id}', {...cotizacion.toMap(), 'version': cotizacion.version});
    return CotizacionGuardada.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  @override
  Future<void> eliminarCotizacion(int id) async {
    await _api.delete('cotizaciones/$id');
  }

  // ---------------------------------------------------------------------
  // Checklists de versiones anteriores: solo existían en el celular
  // ---------------------------------------------------------------------

  @override
  Future<int> guardarChecklist(ChecklistGuardado checklist) async => 0;

  @override
  Future<void> actualizarChecklist(int id, ChecklistGuardado checklist) async {}

  @override
  Future<void> eliminarChecklist(int id) async {}

  @override
  Future<List<ChecklistGuardado>> getChecklistsGuardados() async => [];

  @override
  Future<int> countChecklistsGuardados() async => 0;

  // ---------------------------------------------------------------------
  // Almacén
  // ---------------------------------------------------------------------

  @override
  Future<Requerimiento> insertarRequerimiento(Requerimiento requerimiento) async {
    final fila = await _api.post('requerimientos', requerimiento.toMap());
    return Requerimiento.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  @override
  Future<Requerimiento> actualizarRequerimiento(Requerimiento requerimiento) async {
    final fila = await _api.put('requerimientos/${requerimiento.id}', {...requerimiento.toMap(), 'version': requerimiento.version});
    return Requerimiento.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  @override
  Future<void> eliminarRequerimiento(int id) async {
    await _api.delete('requerimientos/$id');
  }

  @override
  Future<List<Requerimiento>> getRequerimientos() async =>
      _lista(await _api.get('requerimientos')).map(Requerimiento.fromMap).toList();

  @override
  Future<ChecklistHerramientas> insertarChecklistHerramientas(ChecklistHerramientas checklist) async {
    final fila = await _api.post('herramientas', checklist.toMap());
    return ChecklistHerramientas.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  @override
  Future<ChecklistHerramientas> actualizarChecklistHerramientas(ChecklistHerramientas checklist) async {
    final fila = await _api.put('herramientas/${checklist.id}', {...checklist.toMap(), 'version': checklist.version});
    return ChecklistHerramientas.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  @override
  Future<void> eliminarChecklistHerramientas(int id) async {
    await _api.delete('herramientas/$id');
  }

  @override
  Future<List<ChecklistHerramientas>> getChecklistsHerramientas() async =>
      _lista(await _api.get('herramientas')).map(ChecklistHerramientas.fromMap).toList();

  // ---------------------------------------------------------------------
  // Listas del checklist
  // ---------------------------------------------------------------------

  @override
  Future<List<ItemCatalogoChecklist>> getItemsCatalogoChecklist(TipoChecklist tipo) async =>
      _lista(await _api.get('checklist-catalogo', query: {'tipo': tipo.name})).map(ItemCatalogoChecklist.fromMap).toList();

  @override
  Future<int> agregarItemCatalogoChecklist(ItemCatalogoChecklist item) async {
    final fila = await _api.post('checklist-catalogo', {...item.toMap(), 'orden': item.orden});
    return (fila['id'] as num).toInt();
  }

  @override
  Future<void> actualizarItemCatalogoChecklist(ItemCatalogoChecklist item, {required String categoriaAnterior}) async {
    await _api.put('checklist-catalogo/${item.id}', item.toMap());
  }

  @override
  Future<void> renombrarCategoriaCatalogo(TipoChecklist tipo, String anterior, String nueva) async {
    await _api.post('checklist-catalogo/renombrar-categoria', {'tipo': tipo.name, 'anterior': anterior, 'nueva': nueva});
  }

  @override
  Future<void> eliminarItemCatalogoChecklist(int id) async {
    await _api.delete('checklist-catalogo/$id');
  }

  // ---------------------------------------------------------------------
  // Maletas
  // ---------------------------------------------------------------------

  @override
  Future<List<Maleta>> getMaletas() async {
    return [
      for (final m in _lista(await _api.get('maletas')))
        Maleta(
          id: (m['id'] as num).toInt(),
          nombre: m['nombre'] as String,
          categorias: [
            for (final c in (m['categorias'] as List).cast<Map>())
              CategoriaMaleta(
                nombre: c['nombre'] as String,
                items: [
                  for (final i in (c['items'] as List).cast<Map>())
                    ItemMaleta(id: (i['id'] as num).toInt(), nombre: i['nombre'] as String, imagen: i['imagen'] as String?),
                ],
              ),
          ],
        ),
    ];
  }

  @override
  Future<int> crearMaleta(String nombre) async => ((await _api.post('maletas', {'nombre': nombre}))['id'] as num).toInt();

  @override
  Future<void> renombrarMaleta(int id, String nombre) async {
    await _api.put('maletas/$id', {'nombre': nombre});
  }

  @override
  Future<void> eliminarMaleta(int id) async {
    await _api.delete('maletas/$id');
  }

  @override
  Future<int> agregarItemMaleta(int maletaId, {required String nivel, required String nombre, String? imagen}) async {
    final fila = await _api.post('maletas/$maletaId/items', {'nivel': nivel, 'nombre': nombre, 'imagen': imagen});
    return (fila['id'] as num).toInt();
  }

  @override
  Future<void> actualizarItemMaleta(int itemId, {required String nivel, required String nombre, String? imagen}) async {
    await _api.put('maleta-items/$itemId', {'nivel': nivel, 'nombre': nombre, 'imagen': imagen});
  }

  @override
  Future<void> eliminarItemMaleta(int itemId) async {
    await _api.delete('maleta-items/$itemId');
  }

  @override
  Future<void> renombrarNivelMaleta(int maletaId, String anterior, String nuevo) async {
    await _api.post('maletas/$maletaId/niveles/renombrar', {'anterior': anterior, 'nuevo': nuevo});
  }
}
