import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_cliente.dart';
import '../state/auth_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';

/// Ingreso con usuario y clave (solo con servidor). Cada persona entra con
/// el suyo: así todos ven lo mismo y queda anotado quién hizo cada cambio.
class LoginScreen extends StatefulWidget {
  /// Se llama cuando el ingreso fue correcto.
  final VoidCallback alEntrar;

  const LoginScreen({super.key, required this.alEntrar});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _entrando = false;
  bool _verClave = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_usuario.text.trim().isEmpty || _clave.text.isEmpty) {
      setState(() => _error = 'Escribe tu usuario y tu clave.');
      return;
    }
    setState(() {
      _entrando = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().entrar(_usuario.text, _clave.text);
      if (mounted) widget.alEntrar();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/icon/icon.png', width: 84, height: 84)),
                  const SizedBox(height: 16),
                  Text(
                    'ICR Energy',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitulo.copyWith(fontSize: 24, color: BrandColors.azulMarino),
                  ),
                  const SizedBox(height: 4),
                  const Text('Ingresa con tu usuario', textAlign: TextAlign.center, style: AppTextStyles.apoyo),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _usuario,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: _decoracion('Usuario', Icons.person_outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _clave,
                    obscureText: !_verClave,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _entrar(),
                    decoration: _decoracion('Clave', Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _verClave = !_verClave),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _entrando ? null : _entrar,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.azulMarino,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: const StadiumBorder(),
                    ),
                    child: _entrando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Text('ENTRAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '¿No tienes usuario o olvidaste tu clave? Pídeselo al administrador.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.apoyo,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoracion(String etiqueta, IconData icono) => InputDecoration(
        labelText: etiqueta,
        prefixIcon: Icon(icono, size: 20),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );
}
