import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../services/pdf_service.dart';
import '../state/almacen_state.dart';
import '../state/auth_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../utils/seguridad.dart';
import '../utils/texto_compartir.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import 'editar_almacen_screen.dart';
import 'revision_herramientas_screen.dart';
import 'vista_previa_pdf_screen.dart';

/// Detalle de un checklist de herramientas: quién se las llevó, a qué obra,
/// qué salió, y la acción que toca según el estado — confirmar la salida
/// (almacén, recién registrado) o confirmar la devolución con el encargado
/// que las recibe, que lo deja "Conforme".
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

  /// Almacén marca, herramienta por herramienta, qué sale a obra.
  Future<void> _confirmarSalida(BuildContext context, ChecklistHerramientas h) async {
    final resultado = await Navigator.of(context).push<ResultadoRevision>(
      MaterialPageRoute(builder: (_) => RevisionHerramientasScreen(checklist: h, modo: ModoRevision.salida)),
    );
    if (resultado == null || !context.mounted) return;
    final actualizado = await context.read<AlmacenState>().confirmarSalida(
          h,
          confirmadaPor: resultado.nombre,
          categorias: resultado.categorias,
          observaciones: resultado.observaciones,
        );
    if (!context.mounted) return;
    final faltan = actualizado.noSalieron.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          faltan == 0
              ? '${h.numero}: salida confirmada, pendiente de devolución.'
              : '${h.numero}: salida confirmada ($faltan sin salir), pendiente de devolución.',
        ),
      ),
    );
  }

  /// El encargado marca cada herramienta que volvió; las que no, quedan
  /// anotadas como faltantes con su motivo.
  Future<void> _confirmarDevolucion(BuildContext context, ChecklistHerramientas h) async {
    final resultado = await Navigator.of(context).push<ResultadoRevision>(
      MaterialPageRoute(builder: (_) => RevisionHerramientasScreen(checklist: h, modo: ModoRevision.devolucion)),
    );
    if (resultado == null || !context.mounted) return;
    final actualizado = await context.read<AlmacenState>().confirmarDevolucion(
          h,
          encargado: resultado.nombre,
          observaciones: resultado.observaciones.isEmpty ? null : resultado.observaciones,
          categorias: resultado.categorias,
        );
    if (!context.mounted) return;
    final faltan = actualizado.noVolvieron.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          faltan == 0
              ? '${h.numero} conforme: herramientas devueltas.'
              : '${h.numero} cerrado con ${cantidadConPalabra(faltan, 'herramienta', 'herramientas')} sin devolver.',
        ),
      ),
    );
  }

  /// Editar (con la clave): cambiar datos, agregar una herramienta que se
  /// olvidó, cambiar cantidades o quitar alguna.
  Future<void> _editar(BuildContext context, ChecklistHerramientas h) async {
    if (!await pedirClaveEdicion(context) || !context.mounted) return;
    final resultado = await Navigator.of(context).push<ResultadoEdicion>(
      MaterialPageRoute(
        builder: (_) => EditarAlmacenScreen(
          tipo: TipoChecklist.herramientas,
          numero: h.numero,
          obra: h.obra,
          persona: h.responsable,
          observaciones: h.observaciones ?? '',
          urgente: false,
          categorias: [
            for (final c in h.categorias) ChecklistCategoriaState(nombre: c.nombre, items: [...c.items]),
          ],
        ),
      ),
    );
    if (resultado == null || !context.mounted) return;
    if (resultado.nuevos > 0 && h.estado == EstadoHerramientas.conforme) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Se agregaron herramientas'),
          content: Text(
            '${h.numero} está conforme. Al guardar volverá a "Pendiente de devolución" para confirmar la devolución otra vez.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Guardar')),
          ],
        ),
      );
      if (confirmar != true || !context.mounted) return;
    }
    await context.read<AlmacenState>().editarHerramientas(h, resultado);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultado.resumen.isEmpty ? 'Sin cambios.' : '${h.numero} actualizado.')),
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
    final salidaConfirmadaPor = (h.salidaConfirmadaPor ?? '').trim();

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
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: 'Editar',
                  onPressed: () => _editar(context, h),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, color: Colors.white),
                  tooltip: 'Copiar como mensaje',
                  onPressed: () => _copiar(context, h),
                ),
                if (context.watch<AuthState>().esAdmin)
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      PildoraEstado.herramientas(h.estado),
                      if (h.maleta != null)
                        PildoraEstado(
                          texto: h.maleta!,
                          color: BrandColors.azulMarino,
                          fondo: const Color(0xFFE2E8F0),
                          icono: Icons.work_outline_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: ParDato(etiqueta: 'RESPONSABLE', valor: h.responsable)),
                      Expanded(
                        child: ParDato(
                          etiqueta: 'REGISTRADO',
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
                        titulo: 'Registrado',
                        detalle: '${_formatoFecha.format(h.fechaSalida)} · retira ${h.responsable}',
                        hecho: true,
                      ),
                      PasoEstado(
                        titulo: 'Salida confirmada',
                        detalle: h.fechaConfirmacionSalida != null
                            ? '${_formatoFecha.format(h.fechaConfirmacionSalida!)}${salidaConfirmadaPor.isEmpty ? '' : ' · entregó $salidaConfirmadaPor'}'
                            : h.salidaConfirmada
                                ? 'Salió a obra'
                                : 'Cuando almacén confirme que las herramientas salieron',
                        hecho: h.salidaConfirmada,
                      ),
                      PasoEstado(
                        titulo: h.conforme ? 'Devolución confirmada · Conforme' : 'Pendiente de devolución',
                        detalle: h.fechaDevolucion == null
                            ? h.salidaConfirmada
                                ? 'Cuando un encargado confirme que volvieron todas'
                                : 'Después de la salida, se espera que vuelvan todas'
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
                  if (h.noSalieron.isNotEmpty || h.noVolvieron.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ColoresEstado.urgenteFondo,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (h.noSalieron.isNotEmpty)
                            Text(
                              'No salieron (${h.noSalieron.length}): ${h.noSalieron.map((i) => i.texto).join(', ')}',
                              style: const TextStyle(fontSize: 12.5, color: ColoresEstado.urgente, height: 1.35),
                            ),
                          if (h.noSalieron.isNotEmpty && h.noVolvieron.isNotEmpty) const SizedBox(height: 6),
                          if (h.noVolvieron.isNotEmpty)
                            Text(
                              'No volvieron (${h.noVolvieron.length}): ${h.noVolvieron.map((i) => i.texto).join(', ')}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: ColoresEstado.urgente,
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TituloSeccion(
                    'HERRAMIENTAS · ${cantidadConPalabra(h.totalItems, 'ÍTEM', 'ÍTEMS')}',
                  ),
                  ListaItemsPorCategoria(categorias: h.categorias, completado: h.conforme, recorridoHerramientas: true),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    if (h.estado == EstadoHerramientas.registrado) ...[
                      context.watch<AuthState>().puedeConfirmarSalida
                          ? BotonPrincipal(
                              texto: 'CONFIRMAR SALIDA',
                              icono: Icons.outbox_outlined,
                              color: ColoresEstado.pendiente,
                              onPressed: () => _confirmarSalida(context, h),
                            )
                          : const AvisoRol('Almacén debe confirmar la salida.'),
                      const SizedBox(height: 10),
                    ] else if (!h.conforme) ...[
                      context.watch<AuthState>().puedeConfirmarDevolucion
                          ? BotonPrincipal(
                              texto: 'CONFIRMAR DEVOLUCIÓN',
                              icono: Icons.assignment_return_outlined,
                              color: ColoresEstado.listo,
                              onPressed: () => _confirmarDevolucion(context, h),
                            )
                          : const AvisoRol('Almacén o un encargado confirma la devolución.'),
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
