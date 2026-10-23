import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/checklist_categoria.dart';
import '../models/cotizacion_guardada.dart';
import '../models/producto.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/buscador_productos.dart';
import '../widgets/config_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/producto_thumbnail.dart';

/// Editar una cotización ya hecha (se llega aquí después de ingresar la
/// clave): cambiar los datos del cliente y bancarios, las cantidades y
/// precios, quitar un producto, agregar uno que se olvidó (del catálogo) o
/// uno nuevo escrito a mano. Devuelve la cotización con sus cambios; el
/// total se recalcula y quien la llama vuelve a armar el PDF.
class EditarCotizacionScreen extends StatefulWidget {
  final CotizacionGuardada cotizacion;

  const EditarCotizacionScreen({super.key, required this.cotizacion});

  @override
  State<EditarCotizacionScreen> createState() => _EditarCotizacionScreenState();
}

class _EditarCotizacionScreenState extends State<EditarCotizacionScreen> {
  late final _cliente = TextEditingController(text: widget.cotizacion.cliente);
  late final _ruc = TextEditingController(text: widget.cotizacion.rucDni ?? '');
  late final _telefono =
      TextEditingController(text: widget.cotizacion.telefono ?? '');
  late final _vendedor =
      TextEditingController(text: widget.cotizacion.vendedor ?? '');
  late final _banco =
      TextEditingController(text: widget.cotizacion.banco ?? '');
  late final _moneda =
      TextEditingController(text: widget.cotizacion.moneda ?? '');
  late final _cuenta =
      TextEditingController(text: widget.cotizacion.nroCuenta ?? '');
  late final _cci = TextEditingController(text: widget.cotizacion.cci ?? '');

  /// Copia de trabajo (los cambios se aplican al guardar).
  late final List<_Linea> _lineas = [
    for (final i in widget.cotizacion.items)
      _Linea(
        nombre: i.nombre,
        cantidad: i.cantidad,
        precio: i.precioUnitario,
        unidad: i.unidadMedida,
        imagen: i.archivoImagen,
      ),
  ];

  @override
  void dispose() {
    for (final c in [
      _cliente,
      _ruc,
      _telefono,
      _vendedor,
      _banco,
      _moneda,
      _cuenta,
      _cci
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total => _lineas.fold(0, (s, l) => s + l.cantidad * l.precio);

  InputDecoration _decoracion(String label, IconData icono) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono, size: 20),
        filled: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );

  Future<void> _cambiarPrecio(_Linea l) async {
    final precio = await pedirNumero(context,
        titulo: 'Precio unitario',
        etiqueta: 'Precio',
        valorInicial: l.precio,
        prefijo: 'S/ ');
    if (precio != null) setState(() => l.precio = precio);
  }

  Future<void> _agregarDelCatalogo() async {
    final p = await showModalBottomSheet<Producto>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BuscadorProductos(),
    );
    if (p == null) return;
    setState(() {
      final existente = _lineas.where((l) => l.nombre == p.nombre).firstOrNull;
      if (existente != null) {
        existente.cantidad += 1;
      } else {
        _lineas.add(_Linea(
          nombre: p.nombre,
          cantidad: 1,
          precio: p.precioVenta ?? 0,
          unidad: p.unidadMedida,
          imagen: p.archivoImagen,
          nuevo: true,
        ));
      }
    });
  }

  Future<void> _agregarNuevo() async {
    final nueva = await showModalBottomSheet<_Linea>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HojaProductoNuevo(),
    );
    if (nueva != null) setState(() => _lineas.add(nueva));
  }

  void _opcionesAgregar() {
    showModalBottomSheet<void>(
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
          // Material propio: el fondo blanco de la hoja taparía el efecto al tocar.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.search, color: BrandColors.cian),
                  title: const Text('Producto del catálogo'),
                  subtitle: const Text('Uno que se olvidó'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _agregarDelCatalogo();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_box_outlined,
                      color: BrandColors.cian),
                  title: const Text('Producto nuevo'),
                  subtitle: const Text('Escribirlo a mano, con su precio'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _agregarNuevo();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _guardar() {
    if (_lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Debe quedar al menos un producto. Para quitarlo todo, elimina la cotización.')),
      );
      return;
    }
    String? texto(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final c = widget.cotizacion;
    Navigator.pop(
      context,
      CotizacionGuardada(
        id: c.id,
        numero: c.numero,
        cliente: _cliente.text.trim(),
        rucDni: texto(_ruc),
        telefono: texto(_telefono),
        vendedor: texto(_vendedor),
        banco: texto(_banco),
        moneda: texto(_moneda),
        nroCuenta: texto(_cuenta),
        cci: texto(_cci),
        fecha: c.fecha,
        total: _total,
        archivoPdf: c.archivoPdf,
        version: c.version,
        items: [
          for (final l in _lineas)
            ItemCotizacionGuardado(
              nombre: l.nombre,
              cantidad: l.cantidad,
              precioUnitario: l.precio,
              archivoImagen: l.imagen,
              unidadMedida: l.unidad,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'EDITAR · ${widget.cotizacion.numero}',
              titulo: 'Editar cotización',
              color: BrandColors.cian,
              conVolver: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  TextField(
                      controller: _cliente,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          _decoracion('Cliente', Icons.business_outlined)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                              controller: _ruc,
                              keyboardType: TextInputType.number,
                              decoration: _decoracion(
                                  'RUC / DNI', Icons.badge_outlined))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: _telefono,
                              keyboardType: TextInputType.phone,
                              decoration: _decoracion(
                                  'Teléfono', Icons.phone_outlined))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _vendedor,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          _decoracion('Vendedor', Icons.person_outline)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                              controller: _banco,
                              decoration: _decoracion(
                                  'Banco', Icons.account_balance_outlined))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: _moneda,
                              decoration: _decoracion(
                                  'Moneda', Icons.payments_outlined))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _cuenta,
                      decoration: _decoracion('N.° de cuenta', Icons.numbers)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _cci,
                      decoration: _decoracion('CCI', Icons.numbers)),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('PRODUCTOS · ${_lineas.length}',
                        style: AppTextStyles.etiqueta
                            .copyWith(color: BrandColors.azulMarino)),
                  ),
                  for (final l in List.of(_lineas))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          ProductoThumbnail(archivoImagen: l.imagen, size: 44),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.nombre,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                if (l.nuevo)
                                  const Text('Nuevo',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: BrandColors.cian,
                                          fontWeight: FontWeight.w800)),
                                InkWell(
                                  onTap: () => _cambiarPrecio(l),
                                  child: Text(
                                    '${soles(l.precio)} c/u · ${soles(l.cantidad * l.precio)}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: BrandColors.azulMarino),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 22),
                            onPressed: l.cantidad > 1
                                ? () => setState(() => l.cantidad--)
                                : null,
                          ),
                          Text('${l.cantidad}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon:
                                const Icon(Icons.add_circle_outline, size: 22),
                            onPressed: () => setState(() => l.cantidad++),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.delete_outline,
                                size: 20, color: colorScheme.outline),
                            onPressed: () => setState(() => _lineas.remove(l)),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                        color: BrandColors.azulMarino,
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('TOTAL',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12)),
                        ),
                        Text(soles(_total),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _opcionesAgregar,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Agregar producto'),
                    style: estiloBotonSecundario,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.cian,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('GUARDAR',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Linea {
  String nombre;
  int cantidad;
  double precio;
  String? unidad;
  String? imagen;
  bool nuevo;

  _Linea(
      {required this.nombre,
      required this.cantidad,
      required this.precio,
      this.unidad,
      this.imagen,
      this.nuevo = false});
}

/// Un producto que no está en el catálogo, escrito a mano con su precio.
class _HojaProductoNuevo extends StatefulWidget {
  const _HojaProductoNuevo();

  @override
  State<_HojaProductoNuevo> createState() => _HojaProductoNuevoState();
}

class _HojaProductoNuevoState extends State<_HojaProductoNuevo> {
  final _nombre = TextEditingController();
  final _cantidad = TextEditingController(text: '1');
  final _precio = TextEditingController();
  final _unidad = TextEditingController(text: 'Unidades');
  bool _intento = false;

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _precio.dispose();
    _unidad.dispose();
    super.dispose();
  }

  void _guardar() {
    final nombre = _nombre.text.trim();
    final cantidad = int.tryParse(_cantidad.text.trim()) ?? 0;
    final precio = double.tryParse(_precio.text.trim().replaceAll(',', '.'));
    if (nombre.isEmpty || cantidad < 1 || precio == null) {
      setState(() => _intento = true);
      return;
    }
    final unidad = _unidad.text.trim();
    Navigator.pop(
      context,
      _Linea(
        nombre: capitalizarPrimeraLetra(nombre),
        cantidad: cantidad,
        precio: precio,
        unidad: unidad.isEmpty ? null : unidad,
        nuevo: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HojaAlmacen(
      titulo: 'Producto nuevo',
      texto:
          'Un producto que no está en el catálogo. Para tenerlo siempre disponible, agrégalo en Configuración › Productos.',
      children: [
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.sentences,
          decoration:
              decoracionCampoHoja('Nombre *', icono: Icons.label_outline)
                  .copyWith(
                      errorText: _intento && _nombre.text.trim().isEmpty
                          ? 'Escribe el nombre'
                          : null),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cantidad,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration:
                    decoracionCampoHoja('Cantidad *', icono: Icons.numbers),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _precio,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                decoration: decoracionCampoHoja('Precio S/ *',
                        icono: Icons.sell_outlined)
                    .copyWith(
                        errorText: _intento &&
                                double.tryParse(_precio.text
                                        .trim()
                                        .replaceAll(',', '.')) ==
                                    null
                            ? 'Falta'
                            : null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _unidad,
            decoration: decoracionCampoHoja('Unidad',
                icono: Icons.straighten_outlined)),
        const SizedBox(height: 16),
        BotonPrincipal(
            texto: 'AGREGAR',
            icono: Icons.add,
            color: BrandColors.cian,
            onPressed: _guardar),
      ],
    );
  }
}
