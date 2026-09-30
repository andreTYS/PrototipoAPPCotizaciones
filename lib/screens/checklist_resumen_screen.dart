import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../services/notificaciones_service.dart';
import '../services/pdf_service.dart';
import '../state/almacen_state.dart';
import '../state/checklist_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../utils/formato.dart';
import '../utils/rutas.dart';
import '../utils/texto_compartir.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/lottie_gate_screen.dart';
import '../widgets/porcentaje_animado.dart';
import '../widgets/seccion_card.dart';
import 'documento_creado_screen.dart';
import 'herramientas_detalle_screen.dart';
import 'requerimiento_detalle_screen.dart';

/// Resumen final del checklist, después de pasar por las categorías: un
/// vistazo por categoría (tocar una vuelve a ella para revisar o agregar
/// algo) y los datos del documento. Para materiales, "Enviar para
/// aprobación" crea el requerimiento (pendiente, con aviso en el celular);
/// para herramientas, "Registrar salida" deja las herramientas pendientes
/// de devolución. En ambos casos se genera el PDF y se muestra la
/// confirmación con su vista previa.
class ChecklistResumenScreen extends StatefulWidget {
  const ChecklistResumenScreen({super.key});

  @override
  State<ChecklistResumenScreen> createState() => _ChecklistResumenScreenState();
}

class _ChecklistResumenScreenState extends State<ChecklistResumenScreen> {
  final _obraController = TextEditingController();
  final _personaController = TextEditingController();
  final _observacionesController = TextEditingController();
  bool _urgente = false;
  bool _guardando = false;

  late final TipoChecklist _tipo = context.read<ChecklistState>().tipo;
  bool get _esMateriales => _tipo == TipoChecklist.materiales;

  /// Quién pide / quién se lleva las herramientas suele ser la misma persona
  /// de la vez anterior: se recuerda para no tipearlo cada vez.
  String get _clavePersona => _esMateriales ? 'ultimo_solicitante' : 'ultimo_responsable_herramientas';

  @override
  void initState() {
    super.initState();
    _cargarUltimaPersona();
  }

  Future<void> _cargarUltimaPersona() async {
    final prefs = await SharedPreferences.getInstance();
    final ultima = prefs.getString(_clavePersona) ?? '';
    if (!mounted || _personaController.text.isNotEmpty) return;
    setState(() => _personaController.text = ultima);
  }

  @override
  void dispose() {
    _obraController.dispose();
    _personaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  String? get _faltante {
    final checklist = context.read<ChecklistState>();
    if (checklist.totalMarcados == 0) {
      return _esMateriales ? 'Marca al menos un material para pedir.' : 'Marca al menos una herramienta.';
    }
    if (_obraController.text.trim().isEmpty) return 'Escribe la obra o proyecto.';
    if (_personaController.text.trim().isEmpty) {
      return _esMateriales ? 'Escribe quién solicita.' : 'Escribe quién se lleva las herramientas.';
    }
    return null;
  }

  Future<void> _guardar(ChecklistState checklist) async {
    final faltante = _faltante;
    if (faltante != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(faltante)));
      return;
    }
    setState(() => _guardando = true);

    final almacen = context.read<AlmacenState>();
    final obra = _obraController.text.trim();
    final persona = _personaController.text.trim();
    final observaciones = _observacionesController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clavePersona, persona);
    if (!mounted) return;

    if (_esMateriales) {
      await _crearRequerimiento(checklist, almacen, obra, persona, observaciones);
    } else {
      await _registrarSalida(checklist, almacen, obra, persona, observaciones);
    }
    if (mounted) setState(() => _guardando = false);
  }

  Future<void> _crearRequerimiento(
    ChecklistState checklist,
    AlmacenState almacen,
    String obra,
    String solicitante,
    String observaciones,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LottieGateScreen(
          lottieAsset: 'assets/animations/verification.lottie',
          mensaje: 'Enviando tu requerimiento...',
          proceso: () async {
            final requerimiento = await almacen.crearRequerimiento(
              obra: obra,
              solicitante: solicitante,
              urgente: _urgente,
              observaciones: observaciones.isEmpty ? null : observaciones,
              categorias: checklist.categorias,
            );
            final bytes = await PdfService.generarRequerimiento(requerimiento);
            return (requerimiento, bytes);
          },
          alTerminar: (context, resultado) {
            final (requerimiento, bytes) = resultado;
            NotificacionesService.avisarRequerimientoPendiente(requerimiento);
            // Ya quedó guardado — recién ahora se limpia el borrador para
            // que el próximo empiece de cero.
            checklist.reiniciar();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => DocumentoCreadoScreen(
                  titulo: 'Requerimiento enviado',
                  detalle:
                      '${requerimiento.numero} · ${cantidadConPalabra(requerimiento.totalItems, 'ítem', 'ítems')} · pendiente de aprobación',
                  bytes: bytes,
                  nombreArchivo: 'requerimiento_${requerimiento.numero}.pdf',
                  textoBotonCompartir: 'COMPARTIR REQUERIMIENTO',
                  textoMensaje: textoRequerimiento(requerimiento),
                  textoVerDetalle: 'Ver requerimiento',
                  alVerDetalle: (context) => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => RequerimientoDetalleScreen(id: requerimiento.id!)),
                  ),
                ),
              ),
              (ruta) => ruta.isFirst || ruta.settings.name == Rutas.listaRequerimientos,
            );
          },
          alFallar: (context, error) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo guardar el requerimiento: $error')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _registrarSalida(
    ChecklistState checklist,
    AlmacenState almacen,
    String obra,
    String responsable,
    String observaciones,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LottieGateScreen(
          lottieAsset: 'assets/animations/verification.lottie',
          mensaje: 'Registrando la salida...',
          proceso: () async {
            final salida = await almacen.registrarSalida(
              obra: obra,
              responsable: responsable,
              observaciones: observaciones.isEmpty ? null : observaciones,
              categorias: checklist.categorias,
            );
            final bytes = await PdfService.generarChecklistHerramientas(salida);
            return (salida, bytes);
          },
          alTerminar: (context, resultado) {
            final (salida, bytes) = resultado;
            checklist.reiniciar();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => DocumentoCreadoScreen(
                  titulo: 'Salida registrada',
                  detalle:
                      '${salida.numero} · ${cantidadConPalabra(salida.totalItems, 'herramienta', 'herramientas')} · pendiente de devolución',
                  bytes: bytes,
                  nombreArchivo: 'herramientas_${salida.numero}.pdf',
                  textoBotonCompartir: 'COMPARTIR CHECKLIST',
                  textoMensaje: textoHerramientas(salida),
                  textoVerDetalle: 'Ver checklist de herramientas',
                  alVerDetalle: (context) => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => HerramientasDetalleScreen(id: salida.id!)),
                  ),
                ),
              ),
              (ruta) => ruta.isFirst || ruta.settings.name == Rutas.listaHerramientas,
            );
          },
          alFallar: (context, error) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo registrar la salida: $error')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _empezarNuevo(ChecklistState checklist) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_esMateriales ? '¿Empezar un requerimiento nuevo?' : '¿Empezar un checklist nuevo?'),
        content: const Text('Se limpiará lo marcado y volverás a la primera categoría.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Empezar nuevo'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await checklist.reiniciar();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _encabezado(BuildContext context, ChecklistState checklist, int total, int porcentaje) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: BrandColors.azulMarino,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PASO $total DE $total · RESUMEN',
                      style: AppTextStyles.etiqueta.copyWith(color: Colors.white70)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                        tooltip: 'Empezar de nuevo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _empezarNuevo(checklist),
                      ),
                      const SizedBox(width: 10),
                      PorcentajeAnimado(valor: porcentaje),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: List.generate(
                  total,
                  (i) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 5,
                      decoration: BoxDecoration(color: BrandColors.cian, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _esMateriales
                    ? '${cantidadConPalabra(checklist.totalMarcados, 'material', 'materiales')} para pedir'
                    : '${cantidadConPalabra(checklist.totalMarcados, 'herramienta', 'herramientas')} para sacar',
                style: AppTextStyles.subtitulo.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoracion(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, size: 20),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checklist = context.watch<ChecklistState>();
    final persona = _personaController.text.trim();
    final total = checklist.categorias.length;
    // Llegar al resumen significa que ya se recorrieron todas las
    // categorías — a diferencia de checklist.porcentajeAvance (que en la
    // última categoría todavía marca el % de las anteriores), acá es 100%.
    final porcentaje = total == 0 ? 0 : 100;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            _encabezado(context, checklist, total, porcentaje),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  SeccionCard(
                    icono: _esMateriales ? Icons.assignment_outlined : Icons.handyman_outlined,
                    color: BrandColors.azulOscuro,
                    titulo: _esMateriales ? 'Datos del requerimiento' : 'Datos de la salida',
                    children: [
                      TextField(
                        controller: _obraController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _decoracion('Obra / proyecto', Icons.home_work_outlined),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _personaController,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        decoration: _decoracion(
                          _esMateriales ? 'Solicitante' : 'Responsable que se las lleva',
                          Icons.person_outline,
                        ),
                      ),
                      if (persona.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          persona,
                          style: const TextStyle(
                            fontFamily: 'Dancing Script',
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: BrandColors.azulMarino,
                          ),
                        ),
                        Container(
                          width: 170,
                          height: 1,
                          margin: const EdgeInsets.only(top: 2, bottom: 4),
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        Text(
                          'Firma digitalizada',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
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
                        SwitchListTile(
                          value: _urgente,
                          onChanged: (v) => setState(() => _urgente = v),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: Colors.white,
                          activeTrackColor: ColoresEstado.urgente,
                          title: const Text('Marcar como urgente',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: const Text('Aparece primero en el Inicio, en rojo', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('RESUMEN POR CATEGORÍA',
                        style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final entry in checklist.categorias.asMap().entries)
                          _FilaResumenCategoria(
                            categoria: entry.value,
                            esUltima: entry.key == checklist.categorias.length - 1,
                            onTap: () {
                              checklist.irACategoria(entry.key);
                              Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _guardando ? null : () => _guardar(checklist),
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.cian,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: const StadiumBorder(),
                        ),
                        child: _guardando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _esMateriales ? 'ENVIAR PARA APROBACIÓN' : 'REGISTRAR SALIDA',
                                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          foregroundColor: BrandColors.azulMarino,
                          side: const BorderSide(color: BrandColors.azulMarino),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Volver al paso anterior'),
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

/// Fila plana de una categoría en el resumen: nombre + cuántos se marcaron.
/// Tocarla vuelve a esa categoría (útil junto con "+ Añadir objeto a este
/// paso" de cada pantalla).
class _FilaResumenCategoria extends StatelessWidget {
  final ChecklistCategoriaState categoria;
  final bool esUltima;
  final VoidCallback onTap;

  const _FilaResumenCategoria({required this.categoria, required this.esUltima, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final marcados = categoria.totalMarcados;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: esUltima ? null : Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                quitarNumeroCategoria(categoria.nombre),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
            ),
            Text(
              '$marcados / ${categoria.items.length}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: marcados > 0 ? BrandColors.cian : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
