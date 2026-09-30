import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/producto.dart';
import '../services/db_helper.dart';
import '../state/cotizacion_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/brand_icon.dart';
import '../widgets/producto_thumbnail.dart';
import 'agregar_producto_screen.dart';
import 'chat_screen.dart';
import 'generar_cotizacion_screen.dart';
import 'historial_cotizaciones_screen.dart';

/// Píldora que muestra el catálogo completo, todas las categorías juntas.
const _todos = '__todos__';

/// Pestaña "Cotización": categorías como píldoras horizontales — la primera,
/// "Todos", muestra el catálogo completo; al tocar otra se muestran solo sus
/// productos, cada uno con un casillero (como en el checklist) que al
/// marcarlo revela un stepper de cantidad. La búsqueda filtra tanto por
/// nombre de categoría como por nombre/referencia de producto. Arriba están
/// la cotización por voz, el historial de cotizaciones y agregar producto.
/// Al elegir productos, "Generar cotización" empuja el formulario final.
class ProductosScreen extends StatefulWidget {
  const ProductosScreen({super.key});

  @override
  State<ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<ProductosScreen> {
  Map<String, List<Producto>> _porCategoria = {};
  bool _cargando = true;
  String _busqueda = '';
  final _busquedaController = TextEditingController();
  String _categoriaActiva = _todos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final agrupado = await DbHelper.instance.getTodosAgrupados();
    if (!mounted) return;
    setState(() {
      _porCategoria = agrupado;
      _cargando = false;
    });
  }

  Map<String, List<Producto>> get _filtrado {
    final query = _busqueda.trim().toLowerCase();
    if (query.isEmpty) return _porCategoria;

    final resultado = <String, List<Producto>>{};
    for (final entry in _porCategoria.entries) {
      final categoriaCoincide = entry.key.toLowerCase().contains(query);
      final productos = categoriaCoincide
          ? entry.value
          : entry.value
              .where(
                (p) =>
                    p.nombre.toLowerCase().contains(query) || (p.referenciaInterna ?? '').toLowerCase().contains(query),
              )
              .toList();
      if (productos.isNotEmpty) {
        resultado[entry.key] = productos;
      }
    }
    return resultado;
  }

  Future<void> _agregarProducto() async {
    final categorias = _porCategoria.keys.toList()..sort();
    final agregado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AgregarProductoScreen(categorias: categorias)),
    );
    if (agregado == true) _cargar();
  }

  /// Solo los productos agregados desde la app se pueden editar o quitar:
  /// los del catálogo se reemplazan al sincronizar.
  Future<void> _opcionesProducto(Producto producto) async {
    if (!producto.esLocal) return;
    final accion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text(
                  producto.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: BrandColors.azulMarino),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: BrandColors.cian),
                title: const Text('Editar producto'),
                onTap: () => Navigator.pop(ctx, 'editar'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Eliminar producto', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(ctx, 'eliminar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'editar') {
      final categorias = _porCategoria.keys.toList()..sort();
      final cambiado = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => AgregarProductoScreen(categorias: categorias, producto: producto)),
      );
      if (cambiado == true) _cargar();
    } else {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Eliminar este producto?'),
          content: Text('"${producto.nombre}" ya no aparecerá en el catálogo. Las cotizaciones ya hechas no cambian.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;
      final cotizacion = context.read<CotizacionState>();
      if (cotizacion.estaEnCotizacion(producto)) cotizacion.quitar(producto);
      await eliminarProductoLocal(producto);
      _cargar();
    }
  }

  Widget _botonEncabezado(Widget icono, String tooltip, VoidCallback onPressed) {
    return IconButton(icon: icono, tooltip: tooltip, onPressed: onPressed);
  }

  Widget _encabezado(BuildContext context) {
    final activo = _busqueda.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: BrandColors.cian,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('COTIZACIONES', style: AppTextStyles.etiqueta.copyWith(color: Colors.white70)),
                  ),
                  _botonEncabezado(
                    const BrandIcon('voz.svg', color: Colors.white, size: 22),
                    'Cotizar por voz',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
                  ),
                  _botonEncabezado(
                    const BrandIcon('historial.svg', color: Colors.white, size: 22),
                    'Historial de cotizaciones',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistorialCotizacionesScreen()),
                    ),
                  ),
                  _botonEncabezado(const Icon(Icons.add, color: Colors.white), 'Agregar producto', _agregarProducto),
                ],
              ),
              Text(
                'Selecciona productos',
                style: AppTextStyles.titulo.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _busquedaController,
                onChanged: (v) => setState(() => _busqueda = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Buscar producto',
                  hintStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white70),
                  suffixIcon: activo
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Colors.white70),
                          onPressed: () => setState(() {
                            _busqueda = '';
                            _busquedaController.clear();
                          }),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.15),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cotizacion = context.watch<CotizacionState>();
    final activoBusqueda = _busqueda.trim().isNotEmpty;
    final categoriasFiltradas = _filtrado;
    final categorias = categoriasFiltradas.keys.toList();
    final totalProductos = categoriasFiltradas.values.fold<int>(0, (s, l) => s + l.length);
    final categoriaActiva =
        _categoriaActiva == _todos || categoriasFiltradas.containsKey(_categoriaActiva) ? _categoriaActiva : _todos;
    final productosActivos = categoriaActiva == _todos
        ? categoriasFiltradas.values.expand((l) => l).toList()
        : categoriasFiltradas[categoriaActiva]!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            _encabezado(context),
            if (!_cargando && categorias.isNotEmpty)
              _FilaCategorias(
                categorias: categorias,
                totalProductos: totalProductos,
                activa: categoriaActiva,
                onSeleccionar: (c) => setState(() => _categoriaActiva = c),
              ),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : categorias.isEmpty
                      ? Center(
                          child: Text(
                            activoBusqueda
                                ? 'No se encontró nada para "$_busqueda".'
                                : 'No hay productos cargados todavía.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _ListaProductosCategoria(
                          key: ValueKey(categoriaActiva),
                          titulo: categoriaActiva == _todos ? 'Todos los productos · $totalProductos' : categoriaActiva,
                          mostrarCategoria: categoriaActiva == _todos,
                          productos: productosActivos,
                          cotizacion: cotizacion,
                          onOpciones: _opcionesProducto,
                        ),
            ),
          ],
        ),
        bottomNavigationBar: cotizacion.items.isNotEmpty
            ? _BarraResumen(
                cotizacion: cotizacion,
                onGenerar: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GenerarCotizacionScreen()),
                ),
              )
            : null,
      ),
    );
  }
}

/// Píldoras horizontales de categoría — "Todos" primero (el catálogo
/// completo) y después cada categoría, para ir directo a una entre las 40
/// reales del catálogo.
class _FilaCategorias extends StatelessWidget {
  final List<String> categorias;
  final int totalProductos;
  final String activa;
  final ValueChanged<String> onSeleccionar;

  const _FilaCategorias({
    required this.categorias,
    required this.totalProductos,
    required this.activa,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: categorias.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final categoria = index == 0 ? _todos : categorias[index - 1];
          final esActiva = categoria == activa;
          return AnimatedPressable(
            onTap: () => onSeleccionar(categoria),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: esActiva ? BrandColors.azulMarino : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: esActiva ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Text(
                categoria == _todos ? 'Todos · $totalProductos' : categoria,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: esActiva ? Colors.white : BrandColors.azulMarino,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ListaProductosCategoria extends StatelessWidget {
  final String titulo;
  final bool mostrarCategoria;
  final List<Producto> productos;
  final CotizacionState cotizacion;
  final ValueChanged<Producto> onOpciones;

  const _ListaProductosCategoria({
    super.key,
    required this.titulo,
    required this.mostrarCategoria,
    required this.productos,
    required this.cotizacion,
    required this.onOpciones,
  });

  @override
  Widget build(BuildContext context) {
    final seleccionados = productos.where(cotizacion.estaEnCotizacion).length;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: productos.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: BrandColors.azulMarino),
                  ),
                ),
                if (seleccionados > 0)
                  Text(
                    '$seleccionados sel.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BrandColors.cian),
                  ),
              ],
            ),
          );
        }
        final producto = productos[index - 1];
        return _FilaProducto(
          producto: producto,
          cotizacion: cotizacion,
          mostrarCategoria: mostrarCategoria,
          onOpciones: producto.esLocal ? () => onOpciones(producto) : null,
        );
      },
    );
  }
}

class _FilaProducto extends StatelessWidget {
  final Producto producto;
  final CotizacionState cotizacion;
  final bool mostrarCategoria;

  /// Solo para productos agregados desde la app (editar/eliminar).
  final VoidCallback? onOpciones;

  const _FilaProducto({
    required this.producto,
    required this.cotizacion,
    required this.mostrarCategoria,
    this.onOpciones,
  });

  @override
  Widget build(BuildContext context) {
    final seleccionado = cotizacion.estaEnCotizacion(producto);
    final cantidad = cotizacion.cantidadDe(producto);
    final precio = producto.precioVenta ?? 0;
    final unidad = (producto.unidadMedida ?? '').trim();
    final detalle = [
      'S/ ${precio.toStringAsFixed(2)}',
      if (unidad.isNotEmpty) unidad,
      if (mostrarCategoria) producto.categoriaProducto,
    ].join(' · ');

    return GestureDetector(
      onLongPress: onOpciones,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _CasilleroProducto(marcado: seleccionado, onTap: () => cotizacion.toggle(producto)),
            const SizedBox(width: 10),
            ProductoThumbnail(archivoImagen: producto.archivoImagen, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cuerpo,
                  ),
                  const SizedBox(height: 2),
                  Text(detalle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.apoyo),
                ],
              ),
            ),
            if (onOpciones != null)
              IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: 'Editar o eliminar',
                visualDensity: VisualDensity.compact,
                onPressed: onOpciones,
              ),
            if (seleccionado) ...[
              const SizedBox(width: 6),
              _botonStepper(Icons.remove, () => cotizacion.setCantidad(producto, cantidad - 1)),
              SizedBox(
                width: 26,
                child: Text(
                  '$cantidad',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              _botonStepper(Icons.add, () => cotizacion.setCantidad(producto, cantidad + 1)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _botonStepper(IconData icono, VoidCallback onTap) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: BrandColors.azulMarino.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icono, size: 15, color: BrandColors.azulMarino),
      ),
    );
  }
}

/// Casillero de selección — mismo lenguaje visual que el del checklist
/// (cuadrado redondeado, se rellena de cian con un check al marcarlo).
class _CasilleroProducto extends StatelessWidget {
  final bool marcado;
  final VoidCallback onTap;

  const _CasilleroProducto({required this.marcado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: marcado ? BrandColors.cian : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: marcado ? BrandColors.cian : Theme.of(context).colorScheme.outline,
            width: 1.6,
          ),
        ),
        child: marcado ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
      ),
    );
  }
}

/// Barra inferior: resumen de cuántos productos distintos hay elegidos y
/// el subtotal, más el botón para pasar al formulario final.
class _BarraResumen extends StatelessWidget {
  final CotizacionState cotizacion;
  final VoidCallback onGenerar;

  const _BarraResumen({required this.cotizacion, required this.onGenerar});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${cotizacion.items.length} productos · subtotal',
                  style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'S/ ${cotizacion.totalGeneral.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: BrandColors.azulMarino),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onGenerar,
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.azulMarino,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: const StadiumBorder(),
                ),
                child:
                    const Text('GENERAR COTIZACIÓN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
