import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/almacen_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/encabezado_curvo.dart';
import 'checklists_anteriores_screen.dart';
import 'herramientas_detalle_screen.dart';
import 'herramientas_screen.dart';
import 'requerimiento_detalle_screen.dart';
import 'requerimientos_screen.dart';

/// Pestaña "Almacén": dos entradas — Requerimientos (pedir materiales, con
/// aprobación del jefe de obra y entrega) y Checklist de herramientas
/// (salida a obra y devolución) — más lo último que se movió en cada una.
class AlmacenScreen extends StatelessWidget {
  const AlmacenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.watch<AlmacenState>();
    final porAprobar = almacen.pendientesAprobacion.length;
    final porDevolver = almacen.herramientasPorDevolver.length;
    final ultimosRequerimientos = almacen.requerimientos.take(3).toList();
    final ultimasSalidas = almacen.herramientas.take(2).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            const EncabezadoCurvo(etiqueta: 'ALMACÉN', titulo: 'Requerimientos y herramientas'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: almacen.cargar,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    _BotonAlmacen(
                      titulo: 'Requerimientos',
                      subtitulo: 'Pide materiales para una obra.\nLos aprueba el jefe de obra con su código.',
                      icono: Icons.assignment_outlined,
                      colores: const [BrandColors.azulOscuro, BrandColors.azulMarino],
                      contador: porAprobar == 1 ? '1 por aprobar' : '$porAprobar por aprobar',
                      onTap: () => Navigator.of(context).push(rutaRequerimientos()),
                    ),
                    const SizedBox(height: 14),
                    _BotonAlmacen(
                      titulo: 'Checklist herramientas',
                      subtitulo: 'Registra las herramientas que salen a obra\ny confirma cuando vuelven.',
                      icono: Icons.handyman_outlined,
                      colores: const [BrandColors.menta, BrandColors.cian],
                      contador: porDevolver == 1 ? '1 por devolver' : '$porDevolver por devolver',
                      onTap: () => Navigator.of(context).push(rutaHerramientas()),
                    ),
                    if (ultimosRequerimientos.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      TituloSeccion(
                        'ÚLTIMOS REQUERIMIENTOS',
                        accion: _VerTodos(onTap: () => Navigator.of(context).push(rutaRequerimientos())),
                      ),
                      for (final r in ultimosRequerimientos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TarjetaRequerimiento(
                            requerimiento: r,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => RequerimientoDetalleScreen(id: r.id!)),
                            ),
                          ),
                        ),
                    ],
                    if (ultimasSalidas.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      TituloSeccion(
                        'ÚLTIMAS SALIDAS DE HERRAMIENTAS',
                        accion: _VerTodos(onTap: () => Navigator.of(context).push(rutaHerramientas())),
                      ),
                      for (final h in ultimasSalidas)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TarjetaHerramientas(
                            checklist: h,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => HerramientasDetalleScreen(id: h.id!)),
                            ),
                          ),
                        ),
                    ],
                    if (almacen.checklistsAnteriores > 0) ...[
                      const SizedBox(height: 10),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: const Icon(Icons.history, color: BrandColors.grisApoyo),
                        title: Text(
                          'Checklists de obra anteriores (${almacen.checklistsAnteriores})',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600, color: BrandColors.azulMarino),
                        ),
                        subtitle: const Text('Guardados con la versión anterior de la app', style: AppTextStyles.apoyo),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ChecklistsAnterioresScreen()),
                        ),
                      ),
                    ],
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

class _VerTodos extends StatelessWidget {
  final VoidCallback onTap;

  const _VerTodos({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const Text(
        'Ver todos',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BrandColors.cian),
      ),
    );
  }
}

/// Botón grande con gradiente de marca (mismo lenguaje que las tarjetas del
/// Inicio), con un contador de lo pendiente a la derecha.
class _BotonAlmacen extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final List<Color> colores;
  final String contador;
  final VoidCallback onTap;

  const _BotonAlmacen({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.colores,
    required this.contador,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colores),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icono, color: Colors.white, size: 24),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    contador,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(titulo, style: AppTextStyles.titulo.copyWith(color: Colors.white, fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: AppTextStyles.cuerpo
                  .copyWith(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
