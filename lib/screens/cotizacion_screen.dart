import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cotizacion_guardada.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';
import '../services/erp_config_service.dart';
import '../services/pdf_service.dart';
import '../state/cotizacion_state.dart';
import '../widgets/brand_app_bar_title.dart';
import '../widgets/producto_thumbnail.dart';

class CotizacionScreen extends StatefulWidget {
  const CotizacionScreen({super.key});
  @override
  State<CotizacionScreen> createState() => _CotizacionScreenState();
}

class _CotizacionScreenState extends State<CotizacionScreen> {
  final _clienteController = TextEditingController();
  final _rucDniController = TextEditingController();
  final _vendedorController = TextEditingController();
  final _bancoController = TextEditingController();
  final _monedaController = TextEditingController();
  final _nroCuentaController = TextEditingController();
  final _cciController = TextEditingController();
  bool _generando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosBancarios();
  }

  Future<void> _cargarDatosBancarios() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _bancoController.text = prefs.getString('cotizacion_banco') ?? '';
      _monedaController.text = prefs.getString('cotizacion_moneda') ?? 'Soles';
      _nroCuentaController.text = prefs.getString('cotizacion_nro_cuenta') ?? '';
      _cciController.text = prefs.getString('cotizacion_cci') ?? '';
    });
  }

  Future<void> _guardarDatosBancarios() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cotizacion_banco', _bancoController.text.trim());
    await prefs.setString('cotizacion_moneda', _monedaController.text.trim());
    await prefs.setString('cotizacion_nro_cuenta', _nroCuentaController.text.trim());
    await prefs.setString('cotizacion_cci', _cciController.text.trim());
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _rucDniController.dispose();
    _vendedorController.dispose();
    _bancoController.dispose();
    _monedaController.dispose();
    _nroCuentaController.dispose();
    _cciController.dispose();
    super.dispose();
  }

  Future<void> _generarYCompartir(CotizacionState cotizacion) async {
    setState(() => _generando = true);
    try {
      final numero = await PdfService.siguienteNumero();
      final cliente = _clienteController.text.trim();
      final rucDni = _rucDniController.text.trim();

      final bytes = await PdfService.generar(
        numero: numero,
        items: cotizacion.items,
        cliente: cliente,
        rucDni: rucDni,
        vendedor: _vendedorController.text.trim(),
        banco: _bancoController.text.trim(),
        moneda: _monedaController.text.trim(),
        nroCuenta: _nroCuentaController.text.trim(),
        cci: _cciController.text.trim(),
      );

      final rutaArchivo = await PdfService.guardarEnDisco(bytes, numero);
      await DbHelper.instance.guardarCotizacion(
        CotizacionGuardada(
          numero: PdfService.formatearNumero(numero),
          cliente: cliente,
          rucDni: rucDni.isEmpty ? null : rucDni,
          fecha: DateTime.now(),
          total: cotizacion.totalGeneral,
          archivoPdf: rutaArchivo,
        ),
      );
      await _guardarDatosBancarios();

      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'cotizacion_${PdfService.formatearNumero(numero)}.pdf',
      );

      // El PDF ya se generó y compartió — enviar al CRM es un extra que
      // nunca debe deshacer ni bloquear lo anterior si falla (sin señal,
      // ERP sin configurar, token vencido).
      await _enviarLeadAlErp(
        cliente: cliente,
        rucDni: rucDni,
        numero: PdfService.formatearNumero(numero),
        items: cotizacion.items,
        total: cotizacion.totalGeneral,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la cotización: $e')),
      );
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _enviarLeadAlErp({
    required String cliente,
    required String rucDni,
    required String numero,
    required List<ItemCotizacion> items,
    required double total,
  }) async {
    if (!await ErpConfigService.estaConfigurado()) {
      // No es un error: simplemente no se configuró el ERP todavía (ver
      // Conexión con el ERP). El PDF ya se generó y compartió igual.
      return;
    }
    final baseUrl = await ErpConfigService.getBaseUrl();
    final token = await ErpConfigService.getToken();
    try {
      await ApiService.enviarLeadCotizacion(
        baseUrl: baseUrl!,
        token: token!,
        cliente: cliente,
        rucDni: rucDni,
        notas: _notasParaElCrm(numero: numero, items: items, total: total),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cotización $numero enviada también al CRM del ERP.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('El PDF se generó bien, pero no se pudo enviar al CRM: $e')),
      );
    }
  }

  String _notasParaElCrm({
    required String numero,
    required List<ItemCotizacion> items,
    required double total,
  }) {
    final buffer = StringBuffer()
      ..writeln('Cotización de campo $numero (app Cotizador ICR)')
      ..writeln();
    for (final item in items) {
      final ref = (item.producto.referenciaInterna ?? '').isNotEmpty
          ? '[${item.producto.referenciaInterna}] '
          : '';
      buffer.writeln(
        '- $ref${item.producto.nombre} x${item.cantidad} = S/ ${item.subtotal.toStringAsFixed(2)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('Total: S/ ${total.toStringAsFixed(2)}');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cotizacion = context.watch<CotizacionState>();
    final items = cotizacion.items;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const BrandAppBarTitle(subtitulo: 'Armar cotización'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Vaciar',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('¿Vaciar cotización?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () {
                        cotizacion.limpiar();
                        Navigator.pop(context);
                      },
                      child: const Text('Vaciar'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Aún no agregaste productos.'))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Datos del cliente', style: textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _clienteController,
                        decoration: const InputDecoration(
                          labelText: 'Cliente (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _rucDniController,
                        decoration: const InputDecoration(
                          labelText: 'RUC / DNI del cliente (opcional)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _vendedorController,
                        decoration: const InputDecoration(
                          labelText: 'Vendedor (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Datos bancarios (opcional)', style: textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bancoController,
                              decoration: const InputDecoration(
                                labelText: 'Banco',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _monedaController,
                              decoration: const InputDecoration(
                                labelText: 'Moneda',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nroCuentaController,
                        decoration: const InputDecoration(
                          labelText: 'Nro de cuenta',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cciController,
                        decoration: const InputDecoration(
                          labelText: 'CCI',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      Text('Productos seleccionados', style: textTheme.titleSmall),
                      const SizedBox(height: 4),
                      ...items.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ProductoThumbnail(
                            archivoImagen: item.producto.archivoImagen,
                          ),
                          title: Text(item.producto.nombre),
                          subtitle: Text(
                            'Cant. ${item.cantidad} · S/ ${(item.producto.precioVenta ?? 0).toStringAsFixed(2)} c/u',
                          ),
                          trailing: Text(
                            'S/ ${item.subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TOTAL: S/ ${cotizacion.totalGeneral.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: _generando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf),
                          label: Text(_generando ? 'Generando...' : 'Generar y compartir PDF'),
                          onPressed: _generando ? null : () => _generarYCompartir(cotizacion),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
