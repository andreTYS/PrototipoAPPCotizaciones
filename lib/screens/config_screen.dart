import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';
import '../services/erp_config_service.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _sincronizando = false;
  String? _mensaje;
  bool _mensajeOk = false;
  int _totalLocal = 0;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    _urlController.text = await ErpConfigService.getBaseUrl() ?? '';
    _tokenController.text = await ErpConfigService.getToken() ?? '';
    final total = await DbHelper.instance.countTotal();
    if (!mounted) return;
    setState(() => _totalLocal = total);
  }

  Future<void> _sincronizar() async {
    final baseUrl = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final token = _tokenController.text.trim();

    if (baseUrl.isEmpty || token.isEmpty) {
      setState(() {
        _mensaje = 'Completa la URL del ERP y el token de servicio.';
        _mensajeOk = false;
      });
      return;
    }

    setState(() {
      _sincronizando = true;
      _mensaje = null;
    });

    try {
      final productos = await ApiService.obtenerTodos(baseUrl, token);
      await DbHelper.instance.replaceAll(productos);
      await ErpConfigService.guardar(baseUrl: baseUrl, token: token);

      if (!mounted) return;
      setState(() {
        _mensaje = 'Sincronizado con el ERP: ${productos.length} productos.';
        _mensajeOk = true;
        _totalLocal = productos.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensaje =
            'No se pudo conectar con el ERP. Revisa la URL, el token de servicio y tu conexión.\n\nDetalle: $e';
        _mensajeOk = false;
      });
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conexión con el ERP')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Productos guardados en este dispositivo: $_totalLocal'),
            const SizedBox(height: 20),
            const Text(
              'Conecta esta app al ERP real de Inversiones ICR (ICR-LOGISTICA). '
              'El token de servicio se genera desde el ERP en '
              'Administración → Tokens de servicio, eligiendo un usuario con rol VENTAS.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL de la API del ERP',
                hintText: 'https://erp.inversionesicr.com/api',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Token de servicio',
                hintText: 'icr_...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _sincronizando ? null : _sincronizar,
              icon: _sincronizando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(_sincronizando ? 'Sincronizando...' : 'Sincronizar ahora'),
            ),
            if (_mensaje != null) ...[
              const SizedBox(height: 16),
              Text(
                _mensaje!,
                style: TextStyle(
                  color: _mensajeOk ? Colors.green[700] : Colors.red[700],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
