import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_herramientas.dart';
import '../services/pdf_service.dart';
import '../state/almacen_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../utils/texto_compartir.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import 'vista_previa_pdf_screen.dart';

/// Detalle de un checklist de herramientas: quién se las llevó, a qué obra,
/// qué salió, y — mientras esté pendiente — la confirmación de devolución
/// con el encargado que las recibe, que lo deja "Conforme".
class HerramientasDetalleScreen extends StatelessWidget {
  final int id;

  const HerramientasDetalleScreen({super.key, required this.id});

  static final _formatoFecha = DateFormat('dd/MM/yyyy · HH:mm');

  Future<void> _verPdf(BuildContext context, ChecklistHerramientas h) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VistaPreviaPdfScreen(
          titulo: 'Herramientas ${h.numero}',
          nombreArchivo: 'herramientas_${h.numero}.pdf',
          generar: () => PdfService.generarChecklistHerramientas(h),
        ),
      ),
    );
  }

  Future<void> _compartir(ChecklistHerramientas h) async {
    final bytes = await PdfService.generarChecklistHerramientas(h);
    await Printing.sharePdf(bytes: bytes, filename: 'herramientas_${h.numero}.pdf');
  }

  Future<void> _copiar(BuildContext context, ChecklistHerramientas h) async {
    await Clipboard.setData(ClipboardData(text: textoHerramientas(h)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Checklist copiado — pégalo donde quieras enviarlo.'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _confirmarDevolucion(BuildContext context, ChecklistHerramientas h) async {
    final resultado = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HojaDevolucion(checklist: h),
    );
    if (resultado == null || !context.mounted) return;
    final (encargado, observaciones) = resultado;
    await context.read<AlmacenState>().confirmarDevolucion(
          h,
          encargado: encargado,
          observaciones: observaciones.isEmpty ? null : observaciones,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${h.numero} conforme: herramientas devueltas.')),
    );
  }

  Future<void> _eliminar(BuildContext context, ChecklistHerramientas h) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este checklist?'),
        content: Text('${h.numero} · "${h.obra}" se eliminará. Esta acción no se puede deshacer.'),
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
    if (confirmar != true || !context.mounted) return;
    await context.read<AlmacenState>().eliminarHerramientas(h);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<AlmacenState>().herramientasPorId(id);
    if (h == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Este checklist ya no existe.')),
      );
    }
    final observaciones = (h.observaciones ?? '').trim();
    final observacionesDevolucion = (h.observacionesDevolucion ?? '').trim();
    final encargado = (h.encargado ?? '').trim();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'CHECKLIST DE HERRAMIENTAS',
              titulo: h.numero,
              color: BrandColors.cian,
              conVolver: true,
              acciones: [
                IconButton(
                  icon: const Icon(Icons.copy_outlined, color: Colors.white),
                  tooltip: 'Copiar como mensaje',
                  onPressed: () => _copiar(context, h),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Eliminar',
                  onPressed: () => _eliminar(context, h),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                children: [
                  Text(
                    h.obra.isEmpty ? 'Obra sin nombre' : h.obra,
                    style: AppTextStyles.subtitulo.copyWith(fontSize: 18, color: BrandColors.azulMarino),
                  ),
                  const SizedBox(height: 8),
                  Wrap(children: [PildoraEstado.herramientas(h.estado)]),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: ParDato(etiqueta: 'RESPONSABLE', valor: h.responsable)),
                      Expanded(
                        child: ParDato(
                          etiqueta: 'FECHA DE SALIDA',
                          valor: DateFormat('dd/MM/yyyy').format(h.fechaSalida),
                          alinearDerecha: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LineaTiempoEstados(
                    pasos: [
                      PasoEstado(
                        titulo: 'Registrado · pendiente de devolución',
                        detalle: 'Salida ${_formatoFecha.format(h.fechaSalida)} · ${h.responsable}',
                        hecho: true,
                      ),
                      PasoEstado(
                        titulo: 'Conforme',
                        detalle: h.fechaDevolucion == null
                            ? 'Cuando un encargado confirme que volvieron todas'
                            : '${_formatoFecha.format(h.fechaDevolucion!)}${encargado.isEmpty ? '' : ' · recibió $encargado'}',
                        hecho: h.conforme,
                      ),
                    ],
                  ),
                  if (observaciones.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const TituloSeccion('OBSERVACIONES DE LA SALIDA'),
                    Text(observaciones, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ],
                  if (observacionesDevolucion.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const TituloSeccion('OBSERVACIONES DE LA DEVOLUCIÓN'),
                    Text(observacionesDevolucion, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ],
                  const SizedBox(height: 18),
                  TituloSeccion(
                    'HERRAMIENTAS · ${cantidadConPalabra(h.totalItems, 'ÍTEM', 'ÍTEMS')}',
                  ),
                  ListaItemsPorCategoria(categorias: h.categorias, completado: h.conforme),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    if (!h.conforme) ...[
                      BotonPrincipal(
                        texto: 'CONFIRMAR DEVOLUCIÓN',
                        icono: Icons.assignment_return_outlined,
                        color: ColoresEstado.listo,
                        onPressed: () => _confirmarDevolucion(context, h),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _verPdf(context, h),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('Ver PDF'),
                            style: estiloBotonSecundario,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _compartir(h),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Compartir'),
                            style: estiloBotonSecundario,
                          ),
                        ),
                      ],
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

/// El encargado revisa que volvió todo y lo confirma; devuelve (encargado,
/// observaciones) o null si se canceló.
class _HojaDevolucion extends StatefulWidget {
  final ChecklistHerramientas checklist;

  const _HojaDevolucion({required this.checklist});

  @override
  State<_HojaDevolucion> createState() => _HojaDevolucionState();
}

class _HojaDevolucionState extends State<_HojaDevolucion> {
  final _encargadoController = TextEditingController();
  final _observacionesController = TextEditingController();
  bool _revisado = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted && _encargadoController.text.isEmpty) {
        setState(() => _encargadoController.text = prefs.getString('ultimo_encargado_almacen') ?? '');
      }
    });
  }

  @override
  void dispose() {
    _encargadoController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  bool get _listo => _revisado && _encargadoController.text.trim().isNotEmpty;

  Future<void> _confirmar() async {
    final encargado = _encargadoController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ultimo_encargado_almacen', encargado);
    if (mounted) Navigator.of(context).pop((encargado, _observacionesController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.checklist;
    return HojaAlmacen(
      titulo: 'Confirmar devolución',
      texto:
          'El encargado revisa que volvieron las ${cantidadConPalabra(h.totalItems, 'herramienta', 'herramientas')} de ${h.numero}. Quedará en estado Conforme.',
      children: [
        TextField(
          controller: _encargadoController,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: decoracionCampoHoja('Encargado que recibe', icono: Icons.person_outline),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _observacionesController,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 3,
          decoration: decoracionCampoHoja('Observaciones (opcional)', icono: Icons.notes_outlined),
        ),
        CheckboxListTile(
          value: _revisado,
          onChanged: (v) => setState(() => _revisado = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: BrandColors.cian,
          title: const Text('Revisé y volvieron todas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: estiloBotonSecundario,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _listo ? _confirmar : null,
                style: FilledButton.styleFrom(
                  backgroundColor: ColoresEstado.listo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: const Text('MARCAR CONFORME', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
