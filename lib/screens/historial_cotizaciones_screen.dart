import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/cotizacion_guardada.dart';
import '../services/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/producto_thumbnail.dart';
import 'vista_previa_pdf_screen.dart';

/// Historial de cotizaciones ya generadas (se abre desde el ícono de reloj
/// de la pestaña Cotización), más recientes primero, con búsqueda por
/// cliente y filtro por rango de fechas. Cada tarjeta se puede abrir para
/// ver el detalle completo, compartir su PDF o eliminarla.
class HistorialCotizacionesScreen extends StatefulWidget {
  const HistorialCotizacionesScreen({super.key});

  @override
  State<HistorialCotizacionesScreen> createState() => _HistorialCotizacionesScreenState();
}

class _HistorialCotizacionesScreenState extends State<HistorialCotizacionesScreen> {
  List<CotizacionGuardada> _cotizaciones = [];
  bool _cargando = true;

  final _busquedaController = TextEditingController();
  String _busqueda = '';
  DateTimeRange? _rangoFecha;

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
    final cotizaciones = await DbHelper.instance.getCotizacionesGuardadas();
    if (!mounted) return;
    setState(() {
      _cotizaciones = cotizaciones;
      _cargando = false;
    });
  }

  bool _coincideFecha(DateTime fecha) {
    final rango = _rangoFecha;
    if (rango == null) return true;
    final inicio = DateTime(rango.start.year, rango.start.month, rango.start.day);
    final fin = DateTime(rango.end.year, rango.end.month, rango.end.day + 1);
    return !fecha.isBefore(inicio) && fecha.isBefore(fin);
  }

  List<CotizacionGuardada> get _filtradas {
    final busqueda = _busqueda.trim().toLowerCase();
    return _cotizaciones.where((c) {
      final coincideNombre =
          busqueda.isEmpty || c.cliente.toLowerCase().contains(busqueda) || c.numero.toLowerCase().contains(busqueda);
      return coincideNombre && _coincideFecha(c.fecha);
    }).toList();
  }

  Future<void> _elegirRangoFecha() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 5),
      lastDate: DateTime(ahora.year + 1),
      initialDateRange: _rangoFecha,
      helpText: 'Filtrar por fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
    );
    if (rango != null) setState(() => _rangoFecha = rango);
  }

  String _etiquetaRango(DateTimeRange rango) {
    if (DateUtils.isSameDay(rango.start, rango.end)) return fechaCorta(rango.start);
    return '${fechaCorta(rango.start)} - ${fechaCorta(rango.end)}';
  }

  void _limpiarFiltros() {
    setState(() {
      _busqueda = '';
      _busquedaController.clear();
      _rangoFecha = null;
    });
  }

  Future<void> _abrir(CotizacionGuardada c) async {
    final eliminada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CotizacionDetalleScreen(cotizacion: c)),
    );
    if (eliminada == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'HISTORIAL',
              titulo: 'Cotizaciones',
              conVolver: true,
              abajo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BuscadorEncabezado(
                    controller: _busquedaController,
                    hint: 'Buscar por cliente o número',
                    onChanged: (v) => setState(() => _busqueda = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      PildoraFiltro(
                        texto: 'Todas · ${_cotizaciones.length}',
                        activo: _rangoFecha == null,
                        onTap: () => setState(() => _rangoFecha = null),
                      ),
                      const SizedBox(width: 8),
                      PildoraFiltro(
                        texto: _rangoFecha == null ? 'Fecha' : _etiquetaRango(_rangoFecha!),
                        activo: _rangoFecha != null,
                        icono: Icons.calendar_month_outlined,
                        onTap: _elegirRangoFecha,
                        onClear: _rangoFecha == null ? null : () => setState(() => _rangoFecha = null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargar,
                child: _cargando ? const Center(child: CircularProgressIndicator()) : _lista(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    if (_cotizaciones.isEmpty) {
      return EstadoVacio(
        icono: Icons.receipt_long_outlined,
        titulo: 'Aún no generaste ninguna cotización',
        subtitulo: 'Elige los productos en Cotización y genera tu primera cotización.',
        textoBoton: 'Ir a Cotización',
        onBoton: () => Navigator.of(context).pop(),
      );
    }
    final lista = _filtradas;
    if (lista.isEmpty) {
      return EstadoVacio(
        icono: Icons.search_off,
        titulo: 'Ninguna cotización coincide',
        subtitulo: 'Prueba con otro nombre o cambia el rango de fechas.',
        textoBoton: 'Quitar filtros',
        onBoton: _limpiarFiltros,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: lista.length + 1,
      itemBuilder: (context, index) {
        if (index == lista.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text('toca una tarjeta para ver el detalle', style: AppTextStyles.apoyo)),
          );
        }
        final c = lista[index];
        return FadeSlideIn(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TarjetaCotizacion(
              cotizacion: c,
              onPreview: () => _abrir(c),
              onShare: () => compartirCotizacion(context, c),
              onDelete: () async {
                if (await eliminarCotizacion(context, c)) _cargar();
              },
            ),
          ),
        );
      },
    );
  }
}

Future<bool> _verificarArchivo(BuildContext context, String ruta) async {
  final existe = await File(ruta).exists();
  if (!existe && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ese PDF ya no está disponible en el celular.')),
    );
  }
  return existe;
}

Future<void> compartirCotizacion(BuildContext context, CotizacionGuardada c) async {
  if (!await _verificarArchivo(context, c.archivoPdf)) return;
  final bytes = await File(c.archivoPdf).readAsBytes();
  await Printing.sharePdf(bytes: bytes, filename: 'cotizacion_${c.numero}.pdf');
}

/// Pide confirmación y, si se acepta, borra el registro y su PDF. Devuelve
/// si se eliminó.
Future<bool> eliminarCotizacion(BuildContext context, CotizacionGuardada c) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿Eliminar esta cotización?'),
      content: Text(
        '"${c.cliente.isEmpty ? 'Cliente sin nombre' : c.cliente}" (${c.numero}) se eliminará del historial. '
        'Esta acción no se puede deshacer.',
      ),
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
  if (confirmar != true) return false;
  await DbHelper.instance.eliminarCotizacion(c.id!);
  try {
    final archivo = File(c.archivoPdf);
    if (await archivo.exists()) await archivo.delete();
  } catch (_) {
    // No pasa nada si el archivo ya no está o no se puede borrar.
  }
  return true;
}

class _TarjetaCotizacion extends StatelessWidget {
  final CotizacionGuardada cotizacion;
  final VoidCallback onPreview;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _TarjetaCotizacion({
    required this.cotizacion,
    required this.onPreview,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final moneda = NumberFormat.currency(locale: 'en_US', symbol: 'S/ ', decimalDigits: 0);
    final fecha = fechaCorta(cotizacion.fecha);
    final cliente = cotizacion.cliente.isEmpty ? 'Cliente sin nombre' : cotizacion.cliente;
    final productos = cotizacion.items.length;
    final subtitulo = productos > 0 ? '$fecha · $cliente · $productos productos' : '$fecha · $cliente';

    return AnimatedPressable(
      onTap: onPreview,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: BrandColors.menta.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_outlined, color: BrandColors.azulOscuro, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cotización ${cotizacion.numero}',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: BrandColors.azulMarino),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  moneda.format(cotizacion.total),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: BrandColors.cian),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _accion(Icons.visibility_outlined, 'Ver detalle', BrandColors.azulMarino, onPreview),
                _accion(Icons.share_outlined, 'Compartir', BrandColors.cian, onShare),
                _accion(Icons.delete_outline, 'Eliminar', Colors.redAccent, onDelete),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accion(IconData icono, String texto, Color color, VoidCallback onTap) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icono, size: 16),
        label: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

/// Detalle completo de una cotización guardada: cliente, RUC/DNI, teléfono,
/// fecha, vendedor, datos bancarios y todos los productos (con su foto),
/// más ver el PDF, compartirlo o eliminarla. Devuelve true al cerrarse si
/// se eliminó, para que el historial se actualice.
class CotizacionDetalleScreen extends StatelessWidget {
  final CotizacionGuardada cotizacion;

  const CotizacionDetalleScreen({super.key, required this.cotizacion});

  Future<void> _verPdf(BuildContext context) async {
    if (!await _verificarArchivo(context, cotizacion.archivoPdf)) return;
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VistaPreviaPdfScreen(
          titulo: 'Cotización ${cotizacion.numero}',
          nombreArchivo: 'cotizacion_${cotizacion.numero}.pdf',
          generar: () => File(cotizacion.archivoPdf).readAsBytes(),
        ),
      ),
    );
  }

  Future<void> _eliminar(BuildContext context) async {
    if (!await eliminarCotizacion(context, cotizacion)) return;
    if (context.mounted) Navigator.of(context).pop(true);
  }

  Widget _filaTotal(String etiqueta, String valor, ColorScheme colorScheme, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: destacado ? 15 : 13,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
              color: destacado ? BrandColors.azulMarino : colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: destacado ? 20 : 14,
              fontWeight: FontWeight.bold,
              color: destacado ? BrandColors.cian : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaDatos(String e1, String? v1, String e2, String? v2) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ParDato(etiqueta: e1, valor: v1 ?? '')),
          Expanded(child: ParDato(etiqueta: e2, valor: v2 ?? '', alinearDerecha: true)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moneda = NumberFormat.currency(locale: 'en_US', symbol: 'S/ ', decimalDigits: 2);
    final colorScheme = Theme.of(context).colorScheme;

    final totalBruto = cotizacion.total;
    final subtotal = totalBruto / 1.18;
    final igv = totalBruto - subtotal;
    final items = cotizacion.items;
    final tieneBanco = [cotizacion.banco, cotizacion.nroCuenta, cotizacion.cci].any((v) => (v ?? '').isNotEmpty);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'COTIZACIÓN',
              titulo: cotizacion.numero,
              color: BrandColors.cian,
              conVolver: true,
              acciones: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Eliminar',
                  onPressed: () => _eliminar(context),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                children: [
                  _filaDatos(
                    'CLIENTE',
                    cotizacion.cliente.isEmpty ? 'Cliente sin nombre' : cotizacion.cliente,
                    'FECHA',
                    DateFormat('dd/MM/yyyy · HH:mm').format(cotizacion.fecha),
                  ),
                  _filaDatos('RUC / DNI', cotizacion.rucDni, 'TELÉFONO', cotizacion.telefono),
                  _filaDatos('VENDEDOR', cotizacion.vendedor, 'MONEDA', cotizacion.moneda),
                  if (tieneBanco) ...[
                    _filaDatos('BANCO', cotizacion.banco, 'N.° DE CUENTA', cotizacion.nroCuenta),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ParDato(etiqueta: 'CCI', valor: cotizacion.cci ?? ''),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text('PRODUCTOS · ${items.length}', style: AppTextStyles.etiqueta),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Esta cotización se guardó antes de registrar el detalle de productos.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ...items.map((item) => _FilaProductoDetalle(item: item, moneda: moneda)),
                  const SizedBox(height: 8),
                  Divider(color: colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  _filaTotal('Subtotal', moneda.format(subtotal), colorScheme),
                  _filaTotal('IGV 18%', moneda.format(igv), colorScheme),
                  const SizedBox(height: 6),
                  _filaTotal('TOTAL', moneda.format(totalBruto), colorScheme, destacado: true),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _verPdf(context),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.azulMarino,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: const StadiumBorder(),
                        ),
                        label: const Text('VER PDF', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => compartirCotizacion(context, cotizacion),
                        icon: const Icon(Icons.share_outlined, size: 18),
                        style: estiloBotonSecundario,
                        label: const Text('Compartir cotización'),
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

String _cantidadCorta(double n) => n == n.truncateToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);

class _FilaProductoDetalle extends StatelessWidget {
  final ItemCotizacionGuardado item;
  final NumberFormat moneda;

  const _FilaProductoDetalle({required this.item, required this.moneda});

  @override
  Widget build(BuildContext context) {
    final unidad = (item.unidadMedida ?? '').trim();
    final cantidadTexto = unidad.isEmpty ? _cantidadCorta(item.cantidad) : '${_cantidadCorta(item.cantidad)} $unidad';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ProductoThumbnail(archivoImagen: item.archivoImagen, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombre,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cantidadTexto × S/ ${item.precioUnitario.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(moneda.format(item.subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        ],
      ),
    );
  }
}
