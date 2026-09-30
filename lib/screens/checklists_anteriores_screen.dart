import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_guardado.dart';
import '../services/db_helper.dart';
import '../state/almacen_state.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/brand_app_bar_title.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/fade_slide_in.dart';
import 'vista_previa_pdf_screen.dart';

/// Checklists de obra guardados con la versión anterior de la app (antes de
/// separar requerimientos y herramientas). Ya no se crean nuevos, pero los
/// que había se siguen pudiendo ver, compartir y eliminar.
class ChecklistsAnterioresScreen extends StatefulWidget {
  const ChecklistsAnterioresScreen({super.key});

  @override
  State<ChecklistsAnterioresScreen> createState() => _ChecklistsAnterioresScreenState();
}

class _ChecklistsAnterioresScreenState extends State<ChecklistsAnterioresScreen> {
  List<ChecklistGuardado> _checklists = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final checklists = await DbHelper.instance.getChecklistsGuardados();
    if (!mounted) return;
    setState(() {
      _checklists = checklists;
      _cargando = false;
    });
  }

  Future<void> _compartir(ChecklistGuardado c) async {
    final ruta = c.archivoPdf;
    if (ruta == null || !await File(ruta).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este checklist no tiene PDF. Ábrelo y usa "Copiar como mensaje".')),
      );
      return;
    }
    await Printing.sharePdf(bytes: await File(ruta).readAsBytes(), filename: 'checklist_de_obra.pdf');
  }

  Future<void> _eliminar(ChecklistGuardado c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este checklist?'),
        content: const Text('Se eliminará del historial. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true) return;
    await DbHelper.instance.eliminarChecklist(c.id!);
    final ruta = c.archivoPdf;
    if (ruta != null) {
      try {
        final archivo = File(ruta);
        if (await archivo.exists()) await archivo.delete();
      } catch (_) {
        // No pasa nada si el archivo ya no está o no se puede borrar.
      }
    }
    if (!mounted) return;
    await context.read<AlmacenState>().recontarChecklistsAnteriores();
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy · HH:mm');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            const EncabezadoCurvo(etiqueta: 'ALMACÉN', titulo: 'Checklists anteriores', conVolver: true),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _checklists.isEmpty
                      ? const EstadoVacio(
                          icono: Icons.checklist,
                          titulo: 'No quedan checklists anteriores',
                          subtitulo: 'Los nuevos se registran como requerimientos o checklists de herramientas.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: _checklists.length,
                          itemBuilder: (context, index) {
                            final c = _checklists[index];
                            return FadeSlideIn(
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _TarjetaChecklist(
                                  checklist: c,
                                  formatoFecha: formatoFecha,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => _ChecklistDetalleScreen(checklist: c)),
                                  ),
                                  onShare: () => _compartir(c),
                                  onDelete: () => _eliminar(c),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaAccionesTarjeta extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _FilaAccionesTarjeta({required this.onShare, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share_outlined, size: 16),
            label: const Text('Compartir'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 11),
              foregroundColor: BrandColors.cian,
              side: const BorderSide(color: BrandColors.cian),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            label: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 11),
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ],
    );
  }
}

class _TarjetaChecklist extends StatelessWidget {
  final ChecklistGuardado checklist;
  final DateFormat formatoFecha;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _TarjetaChecklist({
    required this.checklist,
    required this.formatoFecha,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final completo = checklist.totalItems > 0 && checklist.itemsMarcados == checklist.totalItems;

    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist, size: 14, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  'Checklist de obra',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.outline,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (checklist.archivoPdf != null) ...[
                  const Icon(Icons.picture_as_pdf_outlined, size: 14, color: BrandColors.cian),
                  const SizedBox(width: 6),
                ],
                const Text(
                  'Ver detalle',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BrandColors.cian),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right, size: 16, color: BrandColors.cian),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              checklist.responsable.isEmpty ? 'Sin responsable especificado' : checklist.responsable,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: BrandColors.azulMarino,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule_outlined, size: 14, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  formatoFecha.format(checklist.fecha),
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ítems marcados',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  '${checklist.itemsMarcados} / ${checklist.totalItems}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: completo ? BrandColors.cian : BrandColors.azulMarino,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FilaAccionesTarjeta(onShare: onShare, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}

/// Detalle de un checklist guardado: cada categoría con lo que se marcó y
/// lo que no (si el registro tiene ese detalle guardado — [categoriasJson]
/// — o si no, el texto plano tal como se hubiera copiado), más "copiar
/// como mensaje" y, si en su momento se generó, el PDF correspondiente.
class _ChecklistDetalleScreen extends StatelessWidget {
  final ChecklistGuardado checklist;

  const _ChecklistDetalleScreen({required this.checklist});

  Future<void> _copiar(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: checklist.resumenTexto));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checklist copiado.'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _verPdf(BuildContext context) async {
    final ruta = checklist.archivoPdf;
    if (ruta == null) return;
    if (!await File(ruta).exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese PDF ya no está disponible en el celular.')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VistaPreviaPdfScreen(
          titulo: 'Checklist de obra',
          nombreArchivo: 'checklist_de_obra.pdf',
          generar: () => File(ruta).readAsBytes(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy · HH:mm');
    final colorScheme = Theme.of(context).colorScheme;
    final categorias = categoriasDesdeJson(checklist.categoriasJson);

    return Scaffold(
      appBar: AppBar(title: const BrandAppBarTitle(subtitulo: 'Checklist de obra')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            checklist.responsable.isEmpty ? 'Sin responsable especificado' : checklist.responsable,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: BrandColors.azulMarino),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatoFecha.format(checklist.fecha)} · ${checklist.itemsMarcados} de ${checklist.totalItems} ítems marcados',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (categorias.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                checklist.resumenTexto,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            )
          else
            ...categorias.asMap().entries.map(
                  (e) => _TarjetaCategoriaDetalle(categoria: e.value),
                ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copiar(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copiar como mensaje'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: BrandColors.cian),
                    foregroundColor: BrandColors.azulMarino,
                  ),
                ),
              ),
              if (checklist.archivoPdf != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _verPdf(context),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Ver PDF'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaCategoriaDetalle extends StatelessWidget {
  final ChecklistCategoriaState categoria;

  const _TarjetaCategoriaDetalle({required this.categoria});

  @override
  Widget build(BuildContext context) {
    final estilo = estiloDeCategoriaChecklist(categoria.nombre);
    final completo = categoria.items.isNotEmpty && categoria.totalMarcados == categoria.items.length;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: estilo.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(estilo.icono, color: estilo.color, size: 20),
          ),
          title: Text(
            quitarNumeroCategoria(categoria.nombre),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: Text(
            '${categoria.totalMarcados} de ${categoria.items.length}',
            style: TextStyle(
              color: completo ? BrandColors.cian : colorScheme.onSurfaceVariant,
              fontWeight: completo ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
          children: categoria.items.map((item) {
            return ListTile(
              dense: true,
              leading: Icon(
                item.marcado ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: item.marcado ? BrandColors.cian : colorScheme.outline,
              ),
              title: Text(
                item.texto,
                style: TextStyle(
                  fontSize: 13,
                  color: item.marcado ? null : colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: (item.marcado || item.esExtra)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.marcado)
                          Text(
                            '× ${item.cantidad}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: BrandColors.cian),
                          ),
                        if (item.esExtra) ...[
                          const SizedBox(width: 6),
                          Icon(
                            item.esProducto ? Icons.inventory_2_outlined : Icons.edit_note_outlined,
                            size: 16,
                            color: colorScheme.outline,
                          ),
                        ],
                      ],
                    )
                  : null,
            );
          }).toList(),
        ),
      ),
    );
  }
}
