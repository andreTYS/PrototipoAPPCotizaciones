import 'package:flutter/material.dart';
import '../theme/brand_colors.dart';

/// Clave que se pide para editar cotizaciones, requerimientos y checklists
/// ya registrados. Fija por ahora; si más adelante debe cambiarse o ser por
/// usuario, este es el único lugar (y, con servidor, se valida allá).
const claveEdicion = '1234';

/// Pide la clave de edición. Devuelve true si se escribió bien, false si se
/// canceló. Si se equivoca, avisa y deja intentar de nuevo.
Future<bool> pedirClaveEdicion(BuildContext context, {String motivo = 'Para editar hay que ingresar la clave.'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoClave(motivo: motivo),
  );
  return ok == true;
}

class _DialogoClave extends StatefulWidget {
  final String motivo;

  const _DialogoClave({required this.motivo});

  @override
  State<_DialogoClave> createState() => _DialogoClaveState();
}

class _DialogoClaveState extends State<_DialogoClave> {
  final _controller = TextEditingController();
  String? _error;

  void _confirmar() {
    if (_controller.text.trim() == claveEdicion) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Clave incorrecta');
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: BrandColors.azulMarino),
          SizedBox(width: 8),
          Text('Editar'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.motivo),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 10),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _confirmar(),
            decoration: InputDecoration(
              hintText: '••••',
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Entrar')),
      ],
    );
  }
}
