import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cotizador_api_service.dart';
import '../services/sesion_service.dart';
import '../theme/brand_colors.dart';
import '../widgets/encabezado_curvo.dart';

/// Inicio de sesión contra el backend compartido del Cotizador — valida con
/// los mismos usuarios del ERP (nunca una clave propia). La URL del
/// servidor solo se pide la primera vez por dispositivo; de ahí en más
/// queda guardada y solo se piden correo y clave.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiUrlCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _cargando = false;
  bool _mostrarApiUrl = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarApiUrlGuardada();
  }

  Future<void> _cargarApiUrlGuardada() async {
    final guardada = await SesionService.getApiUrl();
    if (!mounted) return;
    setState(() {
      _apiUrlCtrl.text = guardada ?? '';
      _mostrarApiUrl = guardada == null || guardada.isEmpty;
    });
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final apiUrl = _apiUrlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final data = await CotizadorApiService.login(
        baseUrl: apiUrl,
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      final usuario = Map<String, dynamic>.from(data['usuario'] as Map);
      await SesionService.guardarApiUrl(apiUrl);
      await SesionService.guardarSesion(
        token: data['token'] as String,
        usuarioId: (usuario['id'] as num).toInt(),
        nombre: usuario['nombre'] as String,
        rol: usuario['rol'] as String,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e is CotizadorApiException ? e.mensaje : 'No se pudo conectar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            const EncabezadoCurvo(etiqueta: 'ICR', titulo: 'Iniciar sesión'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Usa tu mismo correo y clave del ERP. Los requerimientos y checklists se'
                        ' comparten entre todos los que inicien sesión aquí.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 20),
                      if (_mostrarApiUrl) ...[
                        TextFormField(
                          controller: _apiUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Servidor (una sola vez)',
                            hintText: 'https://cotizador.inversionesicr.com/api',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                        ),
                        const SizedBox(height: 12),
                      ] else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() => _mostrarApiUrl = true),
                            child: const Text('Cambiar servidor'),
                          ),
                        ),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordCtrl,
                        decoration: const InputDecoration(labelText: 'Clave', border: OutlineInputBorder()),
                        obscureText: true,
                        validator: (v) => (v == null || v.isEmpty) ? 'Obligatorio' : null,
                        onFieldSubmitted: (_) => _ingresar(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BrandColors.cian,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _cargando ? null : _ingresar,
                        child: _cargando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Ingresar'),
                      ),
                    ],
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
