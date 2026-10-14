import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/datos_almacen.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/seccion_card.dart';

/// Primer paso de todo lo de Almacén: antes de marcar materiales, elegir
/// una maleta o lo que sea, se completan los datos — la obra y quién pide
/// (requerimiento) o quién se lleva las herramientas (salida). Sin ellos no
/// se puede continuar. Devuelve los datos al cerrarse, o null si se volvió.
class DatosAlmacenScreen extends StatefulWidget {
  final TipoChecklist tipo;
  final DatosAlmacen? inicial;

  const DatosAlmacenScreen({super.key, required this.tipo, this.inicial});

  @override
  State<DatosAlmacenScreen> createState() => _DatosAlmacenScreenState();
}

class _DatosAlmacenScreenState extends State<DatosAlmacenScreen> {
  late final _obraController = TextEditingController(text: widget.inicial?.obra ?? '');
  late final _personaController = TextEditingController(text: widget.inicial?.persona ?? '');
  late final _observacionesController = TextEditingController(text: widget.inicial?.observaciones ?? '');
  late bool _urgente = widget.inicial?.urgente ?? false;
  bool _intentoContinuar = false;

  bool get _esMateriales => widget.tipo == TipoChecklist.materiales;

  /// La misma persona de la vez anterior suele volver a pedir / llevar: se
  /// propone su nombre (se puede cambiar).
  String get _clavePersona => _esMateriales ? 'ultimo_solicitante' : 'ultimo_responsable_herramientas';

  @override
  void initState() {
    super.initState();
    if (widget.inicial == null) {
      SharedPreferences.getInstance().then((prefs) {
        if (mounted && _personaController.text.isEmpty) {
          setState(() => _personaController.text = prefs.getString(_clavePersona) ?? '');
        }
      });
    }
  }

  @override
  void dispose() {
    _obraController.dispose();
    _personaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  String? _error(TextEditingController controller, String mensaje) =>
      _intentoContinuar && controller.text.trim().isEmpty ? mensaje : null;

  InputDecoration _decoracion(String label, IconData icono, {String? error}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, size: 20),
      filled: true,
      errorText: error,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  void _continuar() {
    final obra = _obraController.text.trim();
    final persona = _personaController.text.trim();
    if (obra.isEmpty || persona.isEmpty) {
      setState(() => _intentoContinuar = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa los datos obligatorios antes de continuar.')),
      );
      return;
    }
    Navigator.of(context).pop(
      DatosAlmacen(
        obra: obra,
        persona: persona,
        observaciones: _observacionesController.text.trim(),
        urgente: _esMateriales && _urgente,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: _esMateriales ? 'NUEVO REQUERIMIENTO · PASO 1' : 'NUEVA SALIDA DE HERRAMIENTAS · PASO 1',
              titulo: _esMateriales ? 'Datos del requerimiento' : 'Datos de la salida',
              conVolver: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                    child: Text(
                      _esMateriales
                          ? 'Primero los datos del pedido. Después marcas los materiales en el checklist.'
                          : 'Primero los datos de la salida. Después eliges si sale con el checklist de herramientas o por maleta.',
                      style: AppTextStyles.apoyo.copyWith(fontSize: 13, height: 1.4),
                    ),
                  ),
                  SeccionCard(
                    icono: _esMateriales ? Icons.assignment_outlined : Icons.handyman_outlined,
                    color: BrandColors.azulOscuro,
                    titulo: _esMateriales ? 'Datos del requerimiento' : 'Datos de la salida',
                    children: [
                      TextField(
                        controller: _obraController,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: _decoracion(
                          'Obra / proyecto *',
                          Icons.home_work_outlined,
                          error: _error(_obraController, 'Escribe la obra o proyecto'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _personaController,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        decoration: _decoracion(
                          _esMateriales ? 'Nombre del solicitante *' : 'Responsable que se las lleva *',
                          Icons.person_outline,
                          error: _error(
                            _personaController,
                            _esMateriales ? 'Escribe quién solicita' : 'Escribe quién se lleva las herramientas',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _observacionesController,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 1,
                        maxLines: 3,
                        decoration: _decoracion('Observaciones (opcional)', Icons.notes_outlined),
                      ),
                      if (_esMateriales) ...[
                        const SizedBox(height: 6),
                        // Material propio: el fondo de la tarjeta taparía el efecto al tocar.
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            value: _urgente,
                            onChanged: (v) => setState(() => _urgente = v),
                            contentPadding: EdgeInsets.zero,
                            activeThumbColor: Colors.white,
                            activeTrackColor: ColoresEstado.urgente,
                            title: const Text(
                              'Marcar como urgente',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            subtitle:
                                const Text('Aparece primero en el Inicio, en rojo', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, top: 2),
                    child: Text('* Obligatorio', style: AppTextStyles.apoyo),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: 'CONTINUAR',
          icono: Icons.arrow_forward_rounded,
          onPressed: _continuar,
        ),
      ),
    );
  }
}
