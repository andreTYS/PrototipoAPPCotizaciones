import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../models/checklist_categoria.dart';
import '../state/checklist_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../widgets/agregar_item_checklist.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/porcentaje_animado.dart';
import 'checklist_resumen_screen.dart';

/// Ruta a una pantalla del recorrido del checklist, entregándole el
/// borrador con el que trabaja — las rutas empujadas no heredan los
/// providers de la pantalla anterior, así que cada una lo recibe acá.
Route<T> rutaConChecklist<T>(ChecklistState checklist, Widget pantalla) {
  return MaterialPageRoute<T>(
    builder: (_) => ChangeNotifierProvider<ChecklistState>.value(value: checklist, child: pantalla),
  );
}

/// Abre el checklist de siempre para armar un requerimiento de materiales o
/// una salida de herramientas. Si ya había uno a medias, pregunta si
/// continuarlo o empezar de cero (antes se perdía sin preguntar).
Future<void> abrirChecklist(BuildContext context, TipoChecklist tipo) async {
  final checklist = context.read<BorradoresChecklist>().de(tipo);
  await checklist.cargar();
  if (!context.mounted) return;

  if (checklist.tieneProgreso) {
    final continuar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(tipo == TipoChecklist.materiales ? 'Tienes un requerimiento a medias' : 'Tienes una salida a medias'),
        content: Text(
          'Ibas en el paso ${checklist.indice + 1} de ${checklist.categorias.length} con '
          '${checklist.totalMarcados} ítems marcados. ¿Lo continúas o empiezas uno nuevo?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Empezar nuevo')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (continuar == null) return;
    if (!continuar) await checklist.reiniciar();
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(rutaConChecklist<void>(checklist, const ChecklistScreen()));
}

/// Recorrido obligatorio categoría por categoría (herramientas y materiales
/// para instalación Victron, tomadas del Excel real de la empresa) para que
/// no se quede nada por pedir o por llevar. Se puede retroceder libremente
/// a una categoría ya vista, pero avanzar es siempre de una en una. Cada
/// categoría permite agregar un ítem que se haya olvidado; el resumen final
/// (al terminar la última) muestra las categorías juntas.
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ChecklistState>().cargar();
  }

  Future<void> _finalizar(ChecklistState checklist) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const _OverlayCompletado(),
      transitionBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    );
    if (!mounted) return;
    Navigator.of(context).push(rutaConChecklist<void>(checklist, const ChecklistResumenScreen()));
  }

  Widget _encabezado(
      BuildContext context, ChecklistState checklist, ChecklistCategoriaState categoria, int porcentaje) {
    final total = checklist.categorias.length;
    final esMateriales = checklist.tipo == TipoChecklist.materiales;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: BrandColors.azulMarino,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Salir (se guarda lo avanzado)',
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                  Expanded(
                    child: Text(
                      '${esMateriales ? 'REQUERIMIENTO' : 'HERRAMIENTAS'} · PASO ${checklist.indice + 1} DE $total',
                      style: AppTextStyles.etiqueta.copyWith(color: Colors.white70),
                    ),
                  ),
                  PorcentajeAnimado(valor: porcentaje),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: List.generate(total, (i) {
                    final alcanzado = i <= checklist.indice;
                    return Expanded(
                      child: GestureDetector(
                        onTap: alcanzado ? () => checklist.irACategoria(i) : null,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 5,
                          decoration: BoxDecoration(
                            color: alcanzado ? BrandColors.cian : Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quitarNumeroCategoria(categoria.nombre),
                        style: AppTextStyles.titulo.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      esMateriales
                          ? 'Marca los materiales que necesitas pedir'
                          : 'Marca las herramientas que salen a obra',
                      style: AppTextStyles.apoyo.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checklist = context.watch<ChecklistState>();

    if (checklist.cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (checklist.error != null || checklist.categorias.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(checklist.error ?? 'Este checklist no tiene categorías.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final categoria = checklist.categoriaActual;
    final porcentaje = checklist.porcentajeAvance;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            _encabezado(context, checklist, categoria, porcentaje),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  ...categoria.items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return FadeSlideIn(
                      index: index,
                      child: _FilaItemChecklist(
                        item: item,
                        onToggle: () => checklist.toggleItem(index),
                        onCantidad: (c) => checklist.setCantidad(checklist.indice, index, c),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  AnimatedPressable(
                    onTap: () => mostrarAgregarItemChecklist(
                      context,
                      checklist: checklist,
                      categoriaIndex: checklist.indice,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BrandColors.cian, width: 1.4),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 18, color: BrandColors.cian),
                          SizedBox(width: 8),
                          Text(
                            'Añadir objeto a este paso',
                            style: TextStyle(color: BrandColors.cian, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!checklist.esUltimaCategoria) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        'Siguiente paso: ${quitarNumeroCategoria(checklist.categorias[checklist.indice + 1].nombre)}',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.apoyo,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _BarraAvanzar(
          esPrimera: checklist.esPrimeraCategoria,
          esUltima: checklist.esUltimaCategoria,
          onAnterior: checklist.retroceder,
          onSiguiente: () {
            if (checklist.esUltimaCategoria) {
              _finalizar(checklist);
            } else {
              checklist.avanzar();
            }
          },
        ),
      ),
    );
  }
}

/// Fila de un ítem: casillero + nombre, y — a diferencia de un checklist de
/// verificación simple — un stepper de cantidad que aparece al marcarlo,
/// porque esta lista es de qué llevar a la obra y no siempre se lleva todo
/// (mismo lenguaje visual que el casillero+stepper de Productos/Cotizar).
class _FilaItemChecklist extends StatelessWidget {
  final ChecklistItemEntry item;
  final VoidCallback onToggle;
  final ValueChanged<int> onCantidad;

  const _FilaItemChecklist({required this.item, required this.onToggle, required this.onCantidad});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final marcado = item.marcado;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          _Casillero(marcado: marcado, onTap: onToggle),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.texto,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: marcado ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                decoration: marcado ? TextDecoration.lineThrough : TextDecoration.none,
                decorationColor: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (item.esExtra) ...[
            const SizedBox(width: 8),
            Icon(
              item.esProducto ? Icons.inventory_2_outlined : Icons.edit_note_outlined,
              size: 16,
              color: colorScheme.outline,
            ),
          ],
          if (marcado) ...[
            const SizedBox(width: 6),
            _botonStepper(Icons.remove, () => onCantidad(item.cantidad - 1)),
            SizedBox(
              width: 24,
              child: Text(
                '${item.cantidad}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            _botonStepper(Icons.add, () => onCantidad(item.cantidad + 1)),
          ],
        ],
      ),
    );
  }

  Widget _botonStepper(IconData icono, VoidCallback onTap) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: BrandColors.azulMarino.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icono, size: 15, color: BrandColors.azulMarino),
      ),
    );
  }
}

/// Casillero de selección — mismo lenguaje visual que el de Productos
/// (cuadrado redondeado, se rellena de cian con un check al marcarlo). Es
/// tappable por su cuenta (no toda la fila) para no chocar con el stepper.
class _Casillero extends StatelessWidget {
  final bool marcado;
  final VoidCallback onTap;
  const _Casillero({required this.marcado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: marcado ? BrandColors.cian : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: marcado ? BrandColors.cian : Theme.of(context).colorScheme.outline,
            width: 1.6,
          ),
        ),
        child: marcado ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
      ),
    );
  }
}

/// Barra inferior de la pantalla: "Anterior" (oculto en la primera
/// categoría) y la acción de avanzar, que cambia a "Ir al resumen" en la
/// última — así siempre se sabe qué viene después sin adivinar.
class _BarraAvanzar extends StatelessWidget {
  final bool esPrimera;
  final bool esUltima;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;

  const _BarraAvanzar({
    required this.esPrimera,
    required this.esUltima,
    required this.onAnterior,
    required this.onSiguiente,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (!esPrimera) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: onAnterior,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: BrandColors.azulMarino,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Anterior'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: esPrimera ? 1 : 2,
              child: FilledButton(
                onPressed: onSiguiente,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: BrandColors.cian,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  esUltima ? 'IR AL RESUMEN' : 'SIGUIENTE PASO',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlay de transición al terminar la última categoría: difumina lo que
/// ya había en pantalla y reproduce el check hasta su fin natural, antes
/// de pasar al resumen final.
class _OverlayCompletado extends StatefulWidget {
  const _OverlayCompletado();

  @override
  State<_OverlayCompletado> createState() => _OverlayCompletadoState();
}

class _OverlayCompletadoState extends State<_OverlayCompletado> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: BrandColors.azulMarino.withValues(alpha: 0.4),
        child: Center(
          child: Lottie.asset(
            'assets/animations/checkmark.lottie',
            controller: _controller,
            onLoaded: (composicion) {
              _controller.duration = composicion.duration;
              _controller.forward().whenComplete(() {
                if (mounted) Navigator.of(context).pop();
              });
            },
            width: 180,
            height: 180,
            repeat: false,
          ),
        ),
      ),
    );
  }
}
