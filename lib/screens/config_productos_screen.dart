import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/producto.dart';
import '../services/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../widgets/config_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/producto_thumbnail.dart';
import 'agregar_producto_screen.dart';

/// Configuración › Productos de cotización: todos los productos del
/// catálogo (los del Excel y los agregados) se pueden cambiar — precio de
/// venta, costo, nombre, categoría, unidad, referencia y foto — o
/// eliminar, y se pueden agregar productos nuevos. Lo que se cambia se
/// usa en las cotizaciones nuevas (las ya hechas no cambian).
class ConfigProductosScreen extends StatefulWidget {
  const ConfigProductosScreen({super.key});

  @override
  State<ConfigProductosScreen> createState() => _ConfigProductosScreenState();
}

class _ConfigProductosScreenState extends State<ConfigProductosScreen> {
  List<Producto> _productos = [];
  bool _cargando = true;
  String _busqueda = '';
  final _busquedaController = TextEditingController();

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
    final agrupado = await DbHelper.instance.getTodosAgrupados();
    if (!mounted) return;
    setState(() {
      _productos = [for (final lista in agrupado.values) ...lista];
      _cargando = false;
    });
  }

  List<String> get _categorias => (_productos.map((p) => p.categoriaProducto).toSet().toList()..sort());

  List<Producto> get _filtrados {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return _productos;
    return _productos
        .where((p) =>
            p.nombre.toLowerCase().contains(q) ||
            (p.referenciaInterna ?? '').toLowerCase().contains(q) ||
            p.categoriaProducto.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _abrirFormulario([Producto? producto]) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AgregarProductoScreen(categorias: _categorias, producto: producto)),
    );
    if (cambio == true) _cargar();
  }

  /// Cambio rápido del precio de venta, sin abrir todo el formulario.
  Future<void> _cambiarPrecio(Producto p) async {
    final controller = TextEditingController(text: p.precioVenta?.toStringAsFixed(2) ?? '');
    final texto = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Precio de venta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(prefixText: 'S/ ', labelText: 'Precio de venta'),
              onSubmitted: (v) => Navigator.pop(dialogContext, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    final precio = double.tryParse((texto ?? '').trim().replaceAll(',', '.'));
    if (precio == null) return;
    await DbHelper.instance.actualizarProductoManual(Producto(
      id: p.id,
      nombre: p.nombre,
      precioVenta: precio,
      costo: p.costo,
      referenciaInterna: p.referenciaInterna,
      unidadMedida: p.unidadMedida,
      categoriaProducto: p.categoriaProducto,
      archivoImagen: p.archivoImagen,
      imagenUrl: p.imagenUrl,
      origen: p.origen,
    ));
    _cargar();
  }

  Future<void> _eliminar(Producto p) async {
    final confirmar = await confirmarBorrado(
      context,
      titulo: '¿Eliminar este producto?',
      texto: '"${p.nombre}" ya no aparecerá en el catálogo. Las cotizaciones ya hechas no cambian.',
    );
    if (!confirmar) return;
    await DbHelper.instance.eliminarProductoManual(p.id!);
    await borrarFotoGuardada(p.archivoImagen);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'CONFIGURACIÓN',
              titulo: 'Productos de cotización',
              conVolver: true,
              abajo: TextField(
                  controller: _busquedaController,
                  onChanged: (v) => setState(() => _busqueda = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, referencia o categoría',
                    hintStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.14),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : lista.isEmpty
                      ? const EstadoVacio(
                          icono: Icons.search_off,
                          titulo: 'No hay productos',
                          subtitulo: 'Prueba con otra búsqueda o agrega un producto nuevo.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: lista.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  '${cantidadConPalabra(lista.length, 'PRODUCTO', 'PRODUCTOS')} · TOCA UNO PARA CAMBIAR TODOS SUS DATOS',
                                  style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino),
                                ),
                              );
                            }
                            final p = lista[index - 1];
                            return _FilaProducto(
                              producto: p,
                              onTap: () => _abrirFormulario(p),
                              onPrecio: () => _cambiarPrecio(p),
                              onEliminar: () => _eliminar(p),
                            );
                          },
                        ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: 'AGREGAR PRODUCTO',
          icono: Icons.add,
          onPressed: () => _abrirFormulario(),
        ),
      ),
    );
  }
}

class _FilaProducto extends StatelessWidget {
  final Producto producto;
  final VoidCallback onTap;
  final VoidCallback onPrecio;
  final VoidCallback onEliminar;

  const _FilaProducto({required this.producto, required this.onTap, required this.onPrecio, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final p = producto;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              ProductoThumbnail(archivoImagen: p.archivoImagen, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.categoriaProducto}${(p.referenciaInterna ?? '').isEmpty ? '' : ' · ${p.referenciaInterna}'}'
                      '${p.esLocal ? ' · agregado' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.apoyo,
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onPrecio,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: BrandColors.cian.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.precioVenta == null ? 'Sin precio' : soles(p.precioVenta!),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: BrandColors.azulMarino),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 12, color: BrandColors.cian),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.outline),
                tooltip: 'Eliminar',
                onPressed: onEliminar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
