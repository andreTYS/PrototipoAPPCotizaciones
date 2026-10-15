import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/requerimiento.dart';
import '../services/notificaciones_service.dart';
import '../services/pdf_service.dart';
import '../state/almacen_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../utils/seguridad.dart';
import '../utils/texto_compartir.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import 'alistar_requerimiento_screen.dart';
import 'editar_almacen_screen.dart';
import 'vista_previa_pdf_screen.dart';

/// Detalle de un requerimiento: datos, recorrido de estados, lo pedido por
/// categoría, y la acción que toca según el estado — aprobarlo (solo con el
/// código del jefe de obra), marcarlo listo para entrega (el almacenero, al
/// terminar de alistarlo) o confirmar que se entregó. El PDF se arma en el
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

  /// Alistar material por material: se marca lo que ya se preparó y se
  /// guarda el avance; otra persona puede continuar donde se quedó. Al
  /// marcar todo, pasa solo a "listo para entrega".
  Future<void> _alistar(BuildContext context, Requerimiento r) async {
    final resultado = await Navigator.of(context).push<ResultadoAlistado>(
      MaterialPageRoute(builder: (_) => AlistarRequerimientoScreen(requerimiento: r)),
    );
    if (resultado == null || !context.mounted) return;
    final actualizado = await context.read<AlmacenState>().guardarAlistado(r, categorias: resultado.categorias);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          actualizado.estado == EstadoRequerimiento.listo
              ? '${r.numero} listo para entrega.'
              : '${r.numero}: avance guardado (${actualizado.totalAlistados} de ${actualizado.totalItems} alistados).',
        ),
      ),
    );
  }

  /// Editar (con la clave): cambiar datos, agregar lo que se olvidó o se
  /// pidió a último momento, cambiar cantidades y precios.
  Future<void> _editar(BuildContext context, Requerimiento r) async {
    if (!await pedirClaveEdicion(context) || !context.mounted) return;
    final resultado = await Navigator.of(context).push<ResultadoEdicion>(
      MaterialPageRoute(
        builder: (_) => EditarAlmacenScreen(
          tipo: TipoChecklist.materiales,
          numero: r.numero,
          obra: r.obra,
          persona: r.solicitante,
          observaciones: r.observaciones ?? '',
          urgente: r.urgente,
          categorias: categoriasDesdeJson(r.categoriasJson),
        ),
      ),
    );
    if (resultado == null || !context.mounted) return;
    final reabre = resultado.nuevos > 0 &&
        (r.estado == EstadoRequerimiento.listo || r.estado == EstadoRequerimiento.entregado);
    if (reabre) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Se agregaron materiales'),
          content: Text(
            '${r.numero} está ${r.estado == EstadoRequerimiento.entregado ? 'entregado' : 'listo para entrega'}. '
            'Al guardar volverá a "Aprobado · pendiente de alistar" para que se alisten los nuevos.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Guardar')),
          ],
        ),
      );
      if (confirmar != true || !context.mounted) return;
    }
    await context.read<AlmacenState>().editarRequerimiento(r, resultado);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultado.resumen.isEmpty ? 'Sin cambios.' : '${r.numero} actualizado.')),
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
    final alistadoPor = (r.alistadoPor ?? '').trim();
    final recibidoPor = (r.recibidoPor ?? '').trim();
    final alistado = r.estado == EstadoRequerimiento.listo || r.entregado;
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
      // Empieza junto con la aprobación: es el recordatorio para el
      // almacenero de que tiene que preparar los materiales.
      PasoEstado(
        titulo: 'Pendiente de alistar',
        detalle: alistado
            ? 'Materiales alistados por almacén'
            : r.fechaAprobacion == null
                ? 'Después de la aprobación, almacén prepara los materiales'
                : r.totalAlistados > 0
                    ? 'Alistados ${r.totalAlistados} de ${r.totalItems}${r.quienesAlistaron.isEmpty ? '' : ' · ${r.quienesAlistaron.join(', ')}'}'
                    : 'Almacén debe preparar los materiales',
        hecho: alistado,
      ),
      PasoEstado(
        titulo: 'Listo para entrega',
        detalle: r.fechaListo != null
            ? '${_formatoFecha.format(r.fechaListo!)}${alistadoPor.isEmpty ? '' : ' · $alistadoPor'}'
            : alistado
                ? 'Alistado'
                : 'Cuando el almacenero confirme que está todo preparado',
        hecho: alistado,
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
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: 'Editar',
                  onPressed: () => _editar(context, r),
                ),
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
                      if (r.pendienteDeAlistar)
                        PildoraEstado.porAlistar(
                          r.totalAlistados == 0 ? 'Pendiente de alistar' : 'Alistando ${r.totalAlistados}/${r.totalItems}',
                        ),
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
                  ListaItemsPorCategoria(
                    categorias: r.categorias,
                    completado: r.entregado,
                    mostrarAlistado: r.estado != EstadoRequerimiento.pendiente,
                  ),
                  if (r.conPrecios)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: BrandColors.azulMarino,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'TOTAL ESTIMADO',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ),
                          Text(
                            soles(r.totalPrecio),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
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
                        texto: r.totalAlistados == 0
                            ? 'ALISTAR MATERIALES'
                            : 'CONTINUAR ALISTANDO · ${r.totalAlistados} DE ${r.totalItems}',
                        icono: Icons.inventory_2_outlined,
                        color: ColoresEstado.preparado,
                        onPressed: () => _alistar(context, r),
                      )
                    else if (r.estado == EstadoRequerimiento.listo)
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
  bool _faltaNombre = false;
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
    if (_nombreController.text.trim().isEmpty) {
      setState(() => _faltaNombre = true);
      return;
    }
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
          onChanged: (_) {
            if (_faltaNombre) setState(() => _faltaNombre = false);
          },
          decoration: decoracionCampoHoja('Nombre del jefe de obra *', icono: Icons.badge_outlined)
              .copyWith(errorText: _faltaNombre ? 'Escribe el nombre de quien aprueba' : null),
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
  bool _faltaNombre = false;

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
          onChanged: (_) {
            if (_faltaNombre) setState(() => _faltaNombre = false);
          },
          decoration: decoracionCampoHoja('Recibido por *', icono: Icons.person_outline)
              .copyWith(errorText: _faltaNombre ? 'Escribe quién recibe los materiales' : null),
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
                onPressed: () {
                  final recibido = _recibidoController.text.trim();
                  if (recibido.isEmpty) {
                    setState(() => _faltaNombre = true);
                    return;
                  }
                  Navigator.of(context).pop(recibido);
                },
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
