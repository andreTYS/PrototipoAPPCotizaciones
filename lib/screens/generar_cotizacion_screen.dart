import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cotizacion_guardada.dart';
import '../models/producto.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';
import '../services/erp_config_service.dart';
import '../services/pdf_service.dart';
import '../state/cotizacion_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/buscador_productos.dart';
import '../widgets/lottie_gate_screen.dart';
import 'cotizacion_creada_screen.dart';

const _bancos = ['BCP', 'BBVA', 'Interbank', 'Scotiabank', 'Banco de la Nación', 'Banco Pichincha', 'Banco Falabella', 'Otro'];
const _monedas = ['Soles', 'Dólares'];

/// Paso final para armar una cotización: datos del cliente, datos
/// bancarios, y un resumen de cuántos productos se eligieron (ajustar
/// cantidades se hace en la pestaña "Cotizar"; acá solo se puede agregar
/// alguno que se haya olvidado). Se llega acá desde "Cotizar" al presionar
/// "Generar cotización"; al terminar, reemplaza esta pantalla por la de
/// confirmación con la vista previa del PDF.
class GenerarCotizacionScreen extends StatefulWidget {
  const GenerarCotizacionScreen({super.key});
  @override
  State<GenerarCotizacionScreen> createState() => _GenerarCotizacionScreenState();
}

class _GenerarCotizacionScreenState extends State<GenerarCotizacionScreen> {
  final _clienteController = TextEditingController();
  final _rucDniController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _vendedorController = TextEditingController();
  final _bancoOtroController = TextEditingController();
  final _nroCuentaController = TextEditingController();
  final _cciController = TextEditingController();
  String? _bancoSeleccionado;
  String _monedaSeleccionada = 'Soles';
  bool _generando = false;
  bool _consultandoSunat = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosBancarios();
  }

  Future<void> _cargarDatosBancarios() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final bancoGuardado = prefs.getString('cotizacion_banco') ?? '';
    final monedaGuardada = prefs.getString('cotizacion_moneda') ?? 'Soles';
    setState(() {
      if (bancoGuardado.isEmpty) {
        _bancoSeleccionado = null;
      } else if (_bancos.contains(bancoGuardado)) {
        _bancoSeleccionado = bancoGuardado;
      } else {
        _bancoSeleccionado = 'Otro';
        _bancoOtroController.text = bancoGuardado;
      }
      _monedaSeleccionada = _monedas.contains(monedaGuardada) ? monedaGuardada : 'Soles';
      _nroCuentaController.text = prefs.getString('cotizacion_nro_cuenta') ?? '';
      _cciController.text = prefs.getString('cotizacion_cci') ?? '';
    });
  }

  String get _bancoEfectivo {
    if (_bancoSeleccionado == null) return '';
    if (_bancoSeleccionado == 'Otro') return _bancoOtroController.text.trim();
    return _bancoSeleccionado!;
  }

  Future<void> _guardarDatosBancarios() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cotizacion_banco', _bancoEfectivo);
    await prefs.setString('cotizacion_moneda', _monedaSeleccionada);
    await prefs.setString('cotizacion_nro_cuenta', _nroCuentaController.text.trim());
    await prefs.setString('cotizacion_cci', _cciController.text.trim());
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _rucDniController.dispose();
    _telefonoController.dispose();
    _vendedorController.dispose();
    _bancoOtroController.dispose();
    _nroCuentaController.dispose();
    _cciController.dispose();
    super.dispose();
  }

  // Sin API oficial gratuita de SUNAT: se usa un wrapper de terceros bien
  // conocido, siempre con try/catch — si no responde (sin red, o caído),
  // el cliente simplemente se completa a mano, sin bloquear nada.
  Future<void> _consultarSunat() async {
    final ruc = _rucDniController.text.trim();
    if (ruc.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un RUC de 11 dígitos para buscar en SUNAT.')),
      );
      return;
    }
    setState(() => _consultandoSunat = true);
    try {
      final resp = await http
          .get(Uri.parse('https://api.apis.net.pe/v2/sunat/ruc?numero=$ruc'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final razonSocial = (data['razonSocial'] ?? data['nombre'] ?? '').toString().trim();
      if (razonSocial.isEmpty) throw Exception('sin razón social');

      _clienteController.text = razonSocial;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente completado desde SUNAT.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo consultar SUNAT ahora. Completa el nombre a mano.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _consultandoSunat = false);
    }
  }

  void _copiar(String valor, String etiqueta) {
    if (valor.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: valor));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$etiqueta copiado.'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _agregarProducto() async {
    final producto = await showModalBottomSheet<Producto>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BuscadorProductos(),
    );
    if (producto != null && mounted) {
      context.read<CotizacionState>().agregarUno(producto);
    }
  }

  Future<(Uint8List, int)> _procesoDeGeneracion(CotizacionState cotizacion) async {
    final numero = await PdfService.siguienteNumero();
    final cliente = _clienteController.text.trim();
    final rucDni = _rucDniController.text.trim();
    final telefono = _telefonoController.text.trim();
    final vendedor = _vendedorController.text.trim();
    final banco = _bancoEfectivo;
    final moneda = _monedaSeleccionada;
    final nroCuenta = _nroCuentaController.text.trim();
    final cci = _cciController.text.trim();

    final bytes = await PdfService.generar(
      numero: numero,
      items: cotizacion.items,
      cliente: cliente,
      rucDni: rucDni,
      telefono: telefono,
      vendedor: vendedor,
      banco: banco,
      moneda: moneda,
      nroCuenta: nroCuenta,
      cci: cci,
    );

    final rutaArchivo = await PdfService.guardarEnDisco(bytes, numero);
    await DbHelper.instance.guardarCotizacion(
      CotizacionGuardada(
        numero: PdfService.formatearNumero(numero),
        cliente: cliente,
        rucDni: rucDni.isEmpty ? null : rucDni,
        telefono: telefono.isEmpty ? null : telefono,
        vendedor: vendedor.isEmpty ? null : vendedor,
        banco: banco.isEmpty ? null : banco,
        moneda: moneda.isEmpty ? null : moneda,
        nroCuenta: nroCuenta.isEmpty ? null : nroCuenta,
        cci: cci.isEmpty ? null : cci,
        fecha: DateTime.now(),
        total: cotizacion.totalGeneral,
        archivoPdf: rutaArchivo,
        items: cotizacion.items
            .map(
              (i) => ItemCotizacionGuardado(
                nombre: i.producto.nombre,
                cantidad: i.cantidad.toDouble(),
                precioUnitario: i.producto.precioVenta ?? 0,
                archivoImagen: i.producto.archivoImagen,
                unidadMedida: i.producto.unidadMedida,
              ),
            )
            .toList(),
      ),
    );
    await _guardarDatosBancarios();
    await _enviarLeadAlErp(
      cliente: cliente,
      rucDni: rucDni,
      telefono: telefono,
      numero: PdfService.formatearNumero(numero),
      items: cotizacion.items,
      total: cotizacion.totalGeneral,
    );
    return (bytes, numero);
  }

  // Best-effort: si el ERP no está configurado, o el envío falla (sin
  // señal, token vencido), no se avisa ni se interrumpe nada — el PDF ya
  // se generó y se guardó localmente, así que la cotización de campo
  // nunca se pierde por esto. Mismo criterio que NotificacionesService.
  Future<void> _enviarLeadAlErp({
    required String cliente,
    required String rucDni,
    required String telefono,
    required String numero,
    required List<ItemCotizacion> items,
    required double total,
  }) async {
    if (!await ErpConfigService.estaConfigurado()) return;
    try {
      final baseUrl = await ErpConfigService.getBaseUrl();
      final token = await ErpConfigService.getToken();
      await ApiService.enviarLeadCotizacion(
        baseUrl: baseUrl!,
        token: token!,
        cliente: cliente,
        rucDni: rucDni,
        telefono: telefono,
        notas: _notasParaElCrm(numero: numero, items: items, total: total),
      );
    } catch (e) {
      debugPrint('No se pudo enviar la cotización $numero al CRM del ERP: $e');
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

  Future<void> _generarCotizacion(CotizacionState cotizacion) async {
    setState(() => _generando = true);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LottieGateScreen<(Uint8List, int)>(
          lottieAsset: 'assets/animations/verification.lottie',
          mensaje: 'Generando tu cotización...',
          proceso: () => _procesoDeGeneracion(cotizacion),
          alTerminar: (context, resultado) {
            final (bytes, numero) = resultado;
            final total = cotizacion.totalGeneral;
            cotizacion.limpiar();
            Navigator.of(context).pop();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => CotizacionCreadaScreen(
                  numero: PdfService.formatearNumero(numero),
                  total: total,
                  bytes: bytes,
                ),
              ),
            );
          },
          alFallar: (context, error) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo generar la cotización: $error')),
            );
          },
        ),
      ),
    );

    if (mounted) setState(() => _generando = false);
  }

  Future<void> _confirmarVaciar(CotizacionState cotizacion) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Vaciar cotización?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              cotizacion.limpiar();
              Navigator.pop(context);
            },
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
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

  InputDecoration _decoracionCampo({Widget? suffix, String? hint}) {
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: borde,
      enabledBorder: borde,
    );
  }

  Widget _campo(String label, TextEditingController controller, {TextInputType? keyboardType, Widget? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta(label),
        TextField(controller: controller, keyboardType: keyboardType, decoration: _decoracionCampo(suffix: suffix)),
      ],
    );
  }

  Widget _campoBanco() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('BANCO'),
        DropdownButtonFormField<String>(
          initialValue: _bancoSeleccionado,
          isExpanded: true,
          hint: const Text('Elegir', style: TextStyle(fontSize: 13)),
          decoration: _decoracionCampo(),
          items: _bancos
              .map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (v) => setState(() => _bancoSeleccionado = v),
        ),
        if (_bancoSeleccionado == 'Otro') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _bancoOtroController,
            decoration: _decoracionCampo(hint: 'Nombre del banco'),
          ),
        ],
      ],
    );
  }

  Widget _campoMoneda() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('MONEDA'),
        DropdownButtonFormField<String>(
          initialValue: _monedaSeleccionada,
          isExpanded: true,
          decoration: _decoracionCampo(),
          items: _monedas.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _monedaSeleccionada = v);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cotizacion = context.watch<CotizacionState>();
    final items = cotizacion.items;

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
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 20),
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
                            Text('PASO FINAL', style: AppTextStyles.etiqueta.copyWith(color: Colors.white70)),
                            Text('Generar cotización', style: AppTextStyles.titulo.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                      if (items.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white),
                          tooltip: 'Vaciar',
                          onPressed: () => _confirmarVaciar(cotizacion),
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
                  _tituloSeccion('DATOS DEL CLIENTE'),
                  _campo('CLIENTE', _clienteController),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _campo(
                          'RUC / DNI',
                          _rucDniController,
                          keyboardType: TextInputType.number,
                          suffix: _consultandoSunat
                              ? const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.travel_explore, size: 20),
                                  tooltip: 'Buscar en SUNAT',
                                  onPressed: _consultarSunat,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _campo('TELÉFONO', _telefonoController, keyboardType: TextInputType.phone),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _campo('VENDEDOR', _vendedorController),
                  const SizedBox(height: 20),
                  _tituloSeccion('DATOS BANCARIOS'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _campoBanco()),
                      const SizedBox(width: 10),
                      Expanded(child: _campoMoneda()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _campo(
                    'N.° DE CUENTA',
                    _nroCuentaController,
                    suffix: IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: 'Copiar',
                      onPressed: () => _copiar(_nroCuentaController.text, 'Nro de cuenta'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _campo(
                    'CCI',
                    _cciController,
                    suffix: IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: 'Copiar',
                      onPressed: () => _copiar(_cciController.text, 'CCI'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _tituloSeccion('RESUMEN'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          items.isEmpty ? 'Aún no agregaste productos' : '${items.length} productos seleccionados',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          'S/ ${cotizacion.totalGeneral.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: BrandColors.azulMarino),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedPressable(
                    onTap: _agregarProducto,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BrandColors.cian, width: 1.4),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 18, color: BrandColors.cian),
                          SizedBox(width: 8),
                          Text(
                            'Agregar otro producto',
                            style: TextStyle(color: BrandColors.cian, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total con IGV', style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          'S/ ${cotizacion.totalGeneral.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: BrandColors.azulMarino),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (items.isEmpty || _generando) ? null : () => _generarCotizacion(cotizacion),
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.azulMarino,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: const StadiumBorder(),
                        ),
                        child: _generando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('CREAR COTIZACIÓN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
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

