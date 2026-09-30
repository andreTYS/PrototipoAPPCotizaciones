import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/buscador_voz.dart';
import '../services/db_helper.dart';
import '../state/cotizacion_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/animated_pressable.dart';
import 'agregar_por_voz_modal.dart';
import 'generar_cotizacion_screen.dart';

/// Antes de generar cualquier cotización por voz se muestra qué se
/// entendió — la transcripción y los productos que se identificaron del
/// catálogo real, con su cantidad — para poder corregir o quitar algo
/// antes de seguir. Nunca se crea una cotización directo desde lo dictado
/// sin pasar por acá. La transcripción es editable (por si el reconocedor
/// de voz entendió mal una palabra) y se puede volver a grabar para sumar
/// más productos sin perder lo que ya se identificó.
class RevisionVozScreen extends StatefulWidget {
  final String transcripcion;
  final List<ItemDetectado> items;

  const RevisionVozScreen({super.key, required this.transcripcion, required this.items});

  @override
  State<RevisionVozScreen> createState() => _RevisionVozScreenState();
}

class _RevisionVozScreenState extends State<RevisionVozScreen> {
  late List<ItemDetectado> _items = List.of(widget.items);
  late final _controladorTranscripcion = TextEditingController(text: widget.transcripcion);
  bool _buscando = false;

  @override
  void dispose() {
    _controladorTranscripcion.dispose();
    super.dispose();
  }

  void _quitar(int index) => setState(() => _items.removeAt(index));

  void _setCantidad(int index, int cantidad) {
    setState(() {
      if (cantidad <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].cantidad = cantidad;
      }
    });
  }

  void _fusionarItems(List<ItemDetectado> nuevos) {
    for (final nuevo in nuevos) {
      final indice = _items.indexWhere((i) => i.producto.id == nuevo.producto.id);
      if (indice >= 0) {
        _items[indice].cantidad += nuevo.cantidad;
      } else {
        _items.add(nuevo);
      }
    }
  }

  /// Vuelve a buscar en el catálogo con el texto de la transcripción tal
  /// como haya quedado editado — para cuando el reconocedor de voz
  /// entendió mal una palabra y conviene corregirla a mano.
  Future<void> _buscarDeNuevo() async {
    final texto = _controladorTranscripcion.text.trim();
    if (texto.isEmpty || _buscando) return;
    setState(() => _buscando = true);
    final agrupado = await DbHelper.instance.getTodosAgrupados();
    final catalogo = agrupado.values.expand((lista) => lista).toList();
    final nuevosItems = BuscadorVoz.buscar(texto: texto, catalogo: catalogo);
    if (!mounted) return;
    setState(() {
      _items = nuevosItems;
      _buscando = false;
    });
  }

  /// Abre el micrófono de nuevo para dictar más productos y los suma a la
  /// lista que ya se había identificado (sin perderla) — todo dentro de
  /// esta misma pantalla, mediante una hoja modal (nunca navega afuera).
  Future<void> _agregarMasPorVoz() async {
    final resultado = await showModalBottomSheet<(String, List<ItemDetectado>)>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const AgregarPorVozModal(),
    );
    if (resultado == null || !mounted) return;
    final (transcripcionNueva, nuevosItems) = resultado;
    setState(() {
      if (transcripcionNueva.isNotEmpty) {
        final actual = _controladorTranscripcion.text.trim();
        _controladorTranscripcion.text = actual.isEmpty ? transcripcionNueva : '$actual / $transcripcionNueva';
      }
      _fusionarItems(nuevosItems);
    });
  }

  void _continuar() {
    final cotizacion = context.read<CotizacionState>();
    for (final item in _items) {
      cotizacion.setCantidad(item.producto, item.cantidad);
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GenerarCotizacionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (s, i) => s + (i.producto.precioVenta ?? 0) * i.cantidad);

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
                            Text('COTIZAR POR VOZ', style: AppTextStyles.etiqueta.copyWith(color: Colors.white70)),
                            Text('Revisa lo que entendimos', style: AppTextStyles.titulo.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  Text('TRANSCRIPCIÓN (toca para corregir)', style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: BrandColors.celeste,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _controladorTranscripcion,
                      maxLines: null,
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13.5, color: BrandColors.azulMarino),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                        hintText: '(no se detectó nada — puedes escribirlo a mano)',
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton.icon(
                      onPressed: _buscando ? null : _buscarDeNuevo,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Volver a buscar con este texto'),
                      style: TextButton.styleFrom(foregroundColor: BrandColors.azulMarino, visualDensity: VisualDensity.compact),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'PRODUCTOS IDENTIFICADOS · ${_items.length}',
                    style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino),
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No reconocimos ningún producto del catálogo en lo dictado. Corrige el texto de arriba, agrega más por voz, o agrégalos a mano desde Cotizar.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.apoyo,
                      ),
                    )
                  else
                    ...List.generate(
                      _items.length,
                      (i) => _FilaItemVoz(
                        item: _items[i],
                        onCantidad: (c) => _setCantidad(i, c),
                        onQuitar: () => _quitar(i),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _agregarMasPorVoz,
                      icon: const Icon(Icons.mic, size: 18),
                      label: const Text('Agregar más por voz'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BrandColors.cian,
                        side: const BorderSide(color: BrandColors.cian),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  children: [
                    if (_items.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtotal estimado', style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            'S/ ${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BrandColors.azulMarino),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _items.isEmpty ? null : _continuar,
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.azulMarino,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('CONTINUAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaItemVoz extends StatelessWidget {
  final ItemDetectado item;
  final ValueChanged<int> onCantidad;
  final VoidCallback onQuitar;

  const _FilaItemVoz({required this.item, required this.onCantidad, required this.onQuitar});

  @override
  Widget build(BuildContext context) {
    final precio = item.producto.precioVenta ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.producto.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.cuerpo),
                const SizedBox(height: 2),
                Text('S/ ${precio.toStringAsFixed(2)}', style: AppTextStyles.apoyo),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _botonStepper(Icons.remove, () => onCantidad(item.cantidad - 1)),
          SizedBox(
            width: 26,
            child: Text('${item.cantidad}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          _botonStepper(Icons.add, () => onCantidad(item.cantidad + 1)),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Theme.of(context).colorScheme.outline,
            visualDensity: VisualDensity.compact,
            onPressed: onQuitar,
          ),
        ],
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
        decoration: BoxDecoration(color: BrandColors.azulMarino.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
        child: Icon(icono, size: 15, color: BrandColors.azulMarino),
      ),
    );
  }
}
