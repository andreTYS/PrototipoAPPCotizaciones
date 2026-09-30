import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/requerimiento.dart';
import '../services/notificaciones_service.dart';
import '../services/pdf_service.dart';
import '../state/almacen_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../utils/texto_compartir.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import 'vista_previa_pdf_screen.dart';

/// Detalle de un requerimiento: datos, recorrido de estados, lo pedido por
/// categoría, y la acción que toca según el estado — aprobarlo (solo con el
/// código del jefe de obra) o confirmar que se entregó. El PDF se arma en el
/// momento con el estado actual, así nunca queda desactualizado.
class RequerimientoDetalleScreen extends StatelessWidget {
  final int id;

  const RequerimientoDetalleScreen({super.key, required this.id});

  static final _formatoFecha = DateFormat('dd/MM/yyyy · HH:mm');

  Future<void> _verPdf(BuildContext context, Requerimiento r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VistaPreviaPdfScreen(
          titulo: 'Requerimiento ${r.numero}',
          nombreArchivo: 'requerimiento_${r.numero}.pdf',
          generar: () => PdfService.generarRequerimiento(r),
        ),
      ),
    );
  }

  Future<void> _compartir(Requerimiento r) async {
    final bytes = await PdfService.generarRequerimiento(r);
    await Printing.sharePdf(bytes: bytes, filename: 'requerimiento_${r.numero}.pdf');
  }

  Future<void> _copiar(BuildContext context, Requerimiento r) async {
    await Clipboard.setData(ClipboardData(text: textoRequerimiento(r)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Requerimiento copiado — pégalo donde quieras enviarlo.'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _aprobar(BuildContext context, Requerimiento r) async {
    final aprobadoPor = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HojaAprobacion(),
    );
    if (aprobadoPor == null || !context.mounted) return;
    final actualizado = await context.read<AlmacenState>().aprobarRequerimiento(
          r,
          aprobadoPor: aprobadoPor.isEmpty ? null : aprobadoPor,
        );
    NotificacionesService.quitarAviso(actualizado);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${r.numero} aprobado por el jefe de obra.')),
    );
  }

  Future<void> _entregar(BuildContext context, Requerimiento r) async {
    final recibidoPor = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HojaEntrega(requerimiento: r),
    );
    if (recibidoPor == null || !context.mounted) return;
    await context.read<AlmacenState>().entregarRequerimiento(
          r,
          recibidoPor: recibidoPor.isEmpty ? null : recibidoPor,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${r.numero} marcado como entregado.')),
    );
  }

  Future<void> _eliminar(BuildContext context, Requerimiento r) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este requerimiento?'),
        content: Text('${r.numero} · "${r.obra}" se eliminará. Esta acción no se puede deshacer.'),
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
    NotificacionesService.quitarAviso(r);
    await context.read<AlmacenState>().eliminarRequerimiento(r);
    if (context.mounted) Navigator.of(context).pop();
  }

  List<PasoEstado> _pasos(Requerimiento r) {
    final aprobadoPor = (r.aprobadoPor ?? '').trim();
    final recibidoPor = (r.recibidoPor ?? '').trim();
    return [
      PasoEstado(
        titulo: 'Pendiente aprobación',
        detalle: 'Creado ${_formatoFecha.format(r.fechaCreacion)} por ${r.solicitante}',
        hecho: true,
      ),
      PasoEstado(
        titulo: 'Aprobado por jefe de obra',
        detalle: r.fechaAprobacion == null
            ? 'Falta que el jefe de obra lo apruebe con su código'
            : '${_formatoFecha.format(r.fechaAprobacion!)}${aprobadoPor.isEmpty ? '' : ' · $aprobadoPor'}',
        hecho: r.fechaAprobacion != null,
      ),
      PasoEstado(
        titulo: 'Entregado',
        detalle: r.fechaEntrega == null
            ? 'Cuando almacén confirme la entrega'
            : '${_formatoFecha.format(r.fechaEntrega!)}${recibidoPor.isEmpty ? '' : ' · recibió $recibidoPor'}',
        hecho: r.fechaEntrega != null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<AlmacenState>().requerimientoPorId(id);
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Este requerimiento ya no existe.')),
      );
    }
    final observaciones = (r.observaciones ?? '').trim();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'REQUERIMIENTO',
              titulo: r.numero,
              color: BrandColors.cian,
              conVolver: true,
              acciones: [
                IconButton(
                  icon: const Icon(Icons.copy_outlined, color: Colors.white),
                  tooltip: 'Copiar como mensaje',
                  onPressed: () => _copiar(context, r),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Eliminar',
                  onPressed: () => _eliminar(context, r),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                children: [
                  Text(
                    r.obra.isEmpty ? 'Obra sin nombre' : r.obra,
                    style: AppTextStyles.subtitulo.copyWith(fontSize: 18, color: BrandColors.azulMarino),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      PildoraEstado.requerimiento(r.estado),
                      if (r.urgente && !r.entregado) PildoraEstado.urgente(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: ParDato(etiqueta: 'SOLICITANTE', valor: r.solicitante)),
                      Expanded(
                        child: ParDato(
                          etiqueta: 'FECHA',
                          valor: DateFormat('dd/MM/yyyy').format(r.fechaCreacion),
                          alinearDerecha: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LineaTiempoEstados(pasos: _pasos(r)),
                  if (observaciones.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const TituloSeccion('OBSERVACIONES'),
                    Text(observaciones, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ],
                  const SizedBox(height: 18),
                  TituloSeccion(
                    'MATERIALES SOLICITADOS · ${cantidadConPalabra(r.totalItems, 'ÍTEM', 'ÍTEMS')}',
                  ),
                  ListaItemsPorCategoria(categorias: r.categorias, completado: r.entregado),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    if (r.estado == EstadoRequerimiento.pendiente)
                      BotonPrincipal(
                        texto: 'APROBAR COMO JEFE DE OBRA',
                        icono: Icons.verified_user_outlined,
                        color: BrandColors.azulMarino,
                        onPressed: () => _aprobar(context, r),
                      )
                    else if (r.estado == EstadoRequerimiento.aprobado)
                      BotonPrincipal(
                        texto: 'CONFIRMAR ENTREGA',
                        icono: Icons.local_shipping_outlined,
                        color: ColoresEstado.listo,
                        onPressed: () => _entregar(context, r),
                      ),
                    if (!r.entregado) const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _verPdf(context, r),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('Ver PDF'),
                            style: estiloBotonSecundario,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _compartir(r),
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

/// Pide el código del jefe de obra; devuelve su nombre (puede ser vacío)
/// solo si el código es correcto, o null si se canceló.
class _HojaAprobacion extends StatefulWidget {
  const _HojaAprobacion();

  @override
  State<_HojaAprobacion> createState() => _HojaAprobacionState();
}

class _HojaAprobacionState extends State<_HojaAprobacion> {
  final _codigoController = TextEditingController();
  final _nombreController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted && _nombreController.text.isEmpty) {
        _nombreController.text = prefs.getString('ultimo_jefe_obra') ?? '';
      }
    });
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _nombreController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_codigoController.text.trim() != codigoJefeDeObra) {
      setState(() => _error = 'Código incorrecto. Solo el jefe de obra puede aprobar.');
      _codigoController.clear();
      return;
    }
    final nombre = _nombreController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ultimo_jefe_obra', nombre);
    if (mounted) Navigator.of(context).pop(nombre);
  }

  @override
  Widget build(BuildContext context) {
    return HojaAlmacen(
      titulo: 'Aprobación del jefe de obra',
      texto: 'Ingresa el código de 4 dígitos para aprobar el requerimiento. Sin el código no se puede aprobar.',
      children: [
        TextField(
          controller: _codigoController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 14),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _confirmar(),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••',
            filled: true,
            errorText: _error,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nombreController,
          textCapitalization: TextCapitalization.words,
          decoration: decoracionCampoHoja('Nombre del jefe de obra (para el PDF)', icono: Icons.badge_outlined),
        ),
        const SizedBox(height: 16),
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
                onPressed: _confirmar,
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.azulMarino,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: const Text('APROBAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Confirma la entrega; devuelve quién recibió (puede ser vacío) o null si
/// se canceló.
class _HojaEntrega extends StatefulWidget {
  final Requerimiento requerimiento;

  const _HojaEntrega({required this.requerimiento});

  @override
  State<_HojaEntrega> createState() => _HojaEntregaState();
}

class _HojaEntregaState extends State<_HojaEntrega> {
  late final _recibidoController = TextEditingController(text: widget.requerimiento.solicitante);

  @override
  void dispose() {
    _recibidoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.requerimiento;
    return HojaAlmacen(
      titulo: '¿Se entregó el requerimiento?',
      texto:
          'Confirma que los materiales de ${r.numero} (${cantidadConPalabra(r.totalItems, 'ítem', 'ítems')}) ya se entregaron. Pasará a estado Entregado.',
      children: [
        TextField(
          controller: _recibidoController,
          textCapitalization: TextCapitalization.words,
          decoration: decoracionCampoHoja('Recibido por', icono: Icons.person_outline),
        ),
        const SizedBox(height: 16),
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
                onPressed: () => Navigator.of(context).pop(_recibidoController.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: ColoresEstado.listo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: const Text('SÍ, ENTREGADO', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
