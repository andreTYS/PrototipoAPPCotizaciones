import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/producto.dart';
import '../services/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/producto_thumbnail.dart';

const _unidadesMedida = ['Unidades', 'm', 'Otra'];

/// Borra un producto agregado desde la app, junto con la foto que se le
/// haya tomado (que vive en el almacenamiento propio de la app).
Future<void> eliminarProductoLocal(Producto producto) async {
  if (producto.id == null) return;
  await DbHelper.instance.eliminarProductoManual(producto.id!);
  await _borrarFoto(producto.archivoImagen);
}

Future<void> _borrarFoto(String? ruta) async {
  if (!esRutaDeArchivo(ruta)) return;
  try {
    final archivo = File(ruta!);
    if (await archivo.exists()) await archivo.delete();
  } catch (_) {
    // Si ya no estaba, no pasa nada.
  }
}

/// Formulario para agregar un producto nuevo a la base local — para lo que
/// no está en el catálogo empaquetado — con todos sus datos: foto, nombre,
/// categoría, precio de venta, costo, unidad y referencia. Queda marcado
/// como origen "local" (ver DbHelper.agregarProductoManual), así nunca se
/// borra si más adelante se actualiza el catálogo base o se sincroniza con
/// un servidor. Con [producto] sirve también para editar uno ya agregado.
class AgregarProductoScreen extends StatefulWidget {
  final List<String> categorias;
  final Producto? producto;

  const AgregarProductoScreen({super.key, required this.categorias, this.producto});

  @override
  State<AgregarProductoScreen> createState() => _AgregarProductoScreenState();
}

class _AgregarProductoScreenState extends State<AgregarProductoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _categoriaOtraController = TextEditingController();
  final _precioController = TextEditingController();
  final _costoController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _unidadOtraController = TextEditingController();
  String? _categoriaSeleccionada;
  String _unidadSeleccionada = 'Unidades';
  bool _guardando = false;

  /// Ruta de la foto elegida (ya copiada al almacenamiento de la app).
  String? _foto;

  bool get _editando => widget.producto != null;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    if (p == null) return;
    _nombreController.text = p.nombre;
    _categoriaSeleccionada = widget.categorias.contains(p.categoriaProducto) ? p.categoriaProducto : 'Otra';
    if (_categoriaSeleccionada == 'Otra') _categoriaOtraController.text = p.categoriaProducto;
    _precioController.text = p.precioVenta?.toStringAsFixed(2) ?? '';
    _costoController.text = p.costo?.toStringAsFixed(2) ?? '';
    _referenciaController.text = p.referenciaInterna ?? '';
    final unidad = (p.unidadMedida ?? '').trim();
    if (unidad.isEmpty || _unidadesMedida.contains(unidad)) {
      _unidadSeleccionada = unidad.isEmpty ? 'Unidades' : unidad;
    } else {
      _unidadSeleccionada = 'Otra';
      _unidadOtraController.text = unidad;
    }
    _foto = p.archivoImagen;
  }

  /// La foto se copia a la carpeta propia de la app: la del caché de la
  /// cámara o de la galería puede desaparecer en cualquier momento.
  Future<void> _elegirFoto(ImageSource origen) async {
    try {
      final elegida = await ImagePicker().pickImage(source: origen, maxWidth: 1200, imageQuality: 80);
      if (elegida == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final carpeta = Directory('${dir.path}/productos_locales');
      if (!await carpeta.exists()) await carpeta.create(recursive: true);
      final extension = elegida.path.contains('.') ? elegida.path.split('.').last : 'jpg';
      final destino = '${carpeta.path}/producto_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await File(elegida.path).copy(destino);
      if (!mounted) return;
      setState(() => _foto = destino);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo obtener la foto: $e')),
      );
    }
  }

  Future<void> _mostrarOpcionesFoto() async {
    final origen = await showModalBottomSheet<ImageSource>(
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
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: BrandColors.cian),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: BrandColors.cian),
                title: const Text('Elegir de la galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (origen != null) await _elegirFoto(origen);
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este producto?'),
        content: const Text('Ya no aparecerá en el catálogo. Las cotizaciones ya hechas no cambian.'),
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
    if (confirmar != true) return;
    await eliminarProductoLocal(widget.producto!);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _categoriaOtraController.dispose();
    _precioController.dispose();
    _costoController.dispose();
    _referenciaController.dispose();
    _unidadOtraController.dispose();
    super.dispose();
  }

  String? get _categoriaEfectiva {
    if (_categoriaSeleccionada == null) return null;
    if (_categoriaSeleccionada == 'Otra') {
      final texto = _categoriaOtraController.text.trim();
      return texto.isEmpty ? null : texto.toUpperCase();
    }
    return _categoriaSeleccionada;
  }

  String? get _unidadEfectiva {
    final texto = _unidadSeleccionada == 'Otra' ? _unidadOtraController.text.trim() : _unidadSeleccionada;
    return texto.isEmpty ? null : texto;
  }

  double? _numero(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));

  Future<void> _guardar() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final categoria = _categoriaEfectiva;
    if (categoria == null || categoria.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige o escribe una categoría.')),
      );
      return;
    }
    if (!formOk) return;

    setState(() => _guardando = true);
    final producto = Producto(
      id: widget.producto?.id,
      origen: 'local',
      archivoImagen: _foto,
      nombre: _nombreController.text.trim(),
      categoriaProducto: categoria,
      precioVenta: _numero(_precioController.text),
      costo: _costoController.text.trim().isEmpty ? null : _numero(_costoController.text),
      unidadMedida: _unidadEfectiva,
      referenciaInterna: _referenciaController.text.trim().isEmpty ? null : _referenciaController.text.trim(),
    );

    try {
      if (_editando) {
        await DbHelper.instance.actualizarProductoManual(producto);
        // Si se cambió la foto, la anterior ya no la usa nadie.
        if (widget.producto!.archivoImagen != _foto) await _borrarFoto(widget.producto!.archivoImagen);
      } else {
        await DbHelper.instance.agregarProductoManual(producto);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el producto: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _tituloSeccion(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Text(texto, style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino)),
    );
  }

  Widget _etiqueta(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(texto, style: AppTextStyles.etiqueta),
    );
  }

  InputDecoration _decoracionCampo({String? hint}) {
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: borde,
      enabledBorder: borde,
      errorBorder: borde.copyWith(borderSide: const BorderSide(color: Colors.red)),
    );
  }

  Widget _campo(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta(label),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: _decoracionCampo(),
          validator: validator,
        ),
      ],
    );
  }

  Widget _campoCategoria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('CATEGORÍA'),
        DropdownButtonFormField<String>(
          initialValue: _categoriaSeleccionada,
          isExpanded: true,
          hint: const Text('Elegir', style: TextStyle(fontSize: 13)),
          decoration: _decoracionCampo(),
          items: [
            ...widget.categorias.map(
              (c) => DropdownMenuItem(
                  value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            ),
            const DropdownMenuItem(
                value: 'Otra', child: Text('Otra (nueva categoría)', style: TextStyle(fontSize: 13))),
          ],
          onChanged: (v) => setState(() => _categoriaSeleccionada = v),
        ),
        if (_categoriaSeleccionada == 'Otra') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _categoriaOtraController,
            textCapitalization: TextCapitalization.characters,
            decoration: _decoracionCampo(hint: 'Nombre de la categoría'),
          ),
        ],
      ],
    );
  }

  Widget _campoUnidad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('UNIDAD DE MEDIDA'),
        DropdownButtonFormField<String>(
          initialValue: _unidadSeleccionada,
          isExpanded: true,
          decoration: _decoracionCampo(),
          items: _unidadesMedida
              .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _unidadSeleccionada = v);
          },
        ),
        if (_unidadSeleccionada == 'Otra') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _unidadOtraController,
            decoration: _decoracionCampo(hint: 'Ej. kg, caja, rollo'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: BrandColors.azulMarino,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 20, 20),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CATÁLOGO LOCAL', style: AppTextStyles.etiqueta.copyWith(color: Colors.white70)),
                            Text(
                              _editando ? 'Editar producto' : 'Agregar producto',
                              style: AppTextStyles.titulo.copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      if (_editando)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white),
                          tooltip: 'Eliminar producto',
                          onPressed: _eliminar,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    _tituloSeccion('DATOS DEL PRODUCTO'),
                    _etiqueta('FOTO (sale en el PDF de la cotización)'),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _mostrarOpcionesFoto,
                          child: ProductoThumbnail(archivoImagen: _foto, size: 84),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _mostrarOpcionesFoto,
                                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                                label: Text(_foto == null ? 'Agregar foto' : 'Cambiar foto'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: BrandColors.azulMarino,
                                  side: const BorderSide(color: BrandColors.cian),
                                ),
                              ),
                              if (_foto != null)
                                TextButton(
                                  onPressed: () => setState(() => _foto = null),
                                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                  child: const Text('Quitar foto'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _campo(
                      'NOMBRE',
                      _nombreController,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre del producto.' : null,
                    ),
                    const SizedBox(height: 12),
                    _campoCategoria(),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _campo(
                            'PRECIO DE VENTA (S/)',
                            _precioController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) {
                              final n = _numero(v ?? '');
                              if (n == null || n <= 0) return 'Ingresa un precio válido.';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _campo(
                            'COSTO (S/, opcional)',
                            _costoController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _campoUnidad()),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _campo('REFERENCIA INTERNA (opcional)', _referenciaController),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.azulMarino,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: const StadiumBorder(),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _editando ? 'GUARDAR CAMBIOS' : 'GUARDAR PRODUCTO',
                            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
