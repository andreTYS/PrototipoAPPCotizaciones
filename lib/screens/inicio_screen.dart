import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/almacen_state.dart';
import '../state/navegacion_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/brand_icon.dart';
import '../widgets/fade_slide_in.dart';
import 'config_screen.dart';
import 'herramientas_detalle_screen.dart';
import 'herramientas_screen.dart';
import 'requerimiento_detalle_screen.dart';
import 'requerimientos_screen.dart';

/// Pestaña "Inicio": tablero con lo que requiere atención — requerimientos
/// urgentes o pendientes de aprobación, aprobados que falta entregar, y
/// herramientas que no han vuelto — más los accesos a Almacén y Cotización.
/// No hay sistema de usuarios en la app, así que el saludo es genérico.
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  void _abrirRequerimiento(BuildContext context, int id) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RequerimientoDetalleScreen(id: id)));
  }

  @override
  Widget build(BuildContext context) {
    final almacen = context.watch<AlmacenState>();
    final navegacion = context.read<NavegacionState>();
    final atencion = almacen.requierenAtencion;
    final porEntregar = almacen.aprobadosPorEntregar;
    final herramientas = almacen.herramientasPorDevolver;
    final pendientes = almacen.pendientesAprobacion.length;
    final todoAlDia = atencion.isEmpty && porEntregar.isEmpty && herramientas.isEmpty;

    var indice = 0;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: almacen.cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/icon/icon.png', width: 40, height: 40),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Inversiones ICR',
                      style: AppTextStyles.subtitulo.copyWith(color: BrandColors.azulMarino),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BotonCuadrado(
                    icono: Icons.notifications_none_rounded,
                    contador: pendientes,
                    tooltip: 'Pendientes de aprobación',
                    onTap: () => Navigator.of(context).push(rutaRequerimientos(filtro: FiltroRequerimientos.pendiente)),
                  ),
                  const SizedBox(width: 8),
                  _BotonCuadrado(
                    icono: Icons.settings_outlined,
                    tooltip: 'Sincronizar catálogo',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfigScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('Hola,', style: TextStyle(color: BrandColors.cian, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                todoAlDia ? 'Todo está al día' : 'Esto requiere atención',
                style: AppTextStyles.titulo.copyWith(color: BrandColors.azulMarino),
              ),
              const SizedBox(height: 4),
              const Text('Requerimientos y herramientas de almacén', style: AppTextStyles.apoyo),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Indicador(
                      valor: pendientes,
                      texto: 'Pendientes de aprobación',
                      color: ColoresEstado.pendiente,
                      onTap: () =>
                          Navigator.of(context).push(rutaRequerimientos(filtro: FiltroRequerimientos.pendiente)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Indicador(
                      valor: almacen.urgentesSinEntregar.length,
                      texto: 'Urgentes sin entregar',
                      color: ColoresEstado.urgente,
                      onTap: () =>
                          Navigator.of(context).push(rutaRequerimientos(filtro: FiltroRequerimientos.urgentes)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Indicador(
                      valor: herramientas.length,
                      texto: 'Herramientas por devolver',
                      color: BrandColors.azulMarino,
                      onTap: () => Navigator.of(context).push(rutaHerramientas(filtro: FiltroHerramientas.pendiente)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 132,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _TarjetaAcceso(
                        titulo: 'ALMACÉN',
                        subtitulo: 'Requerimientos y herramientas',
                        icono: const Icon(Icons.warehouse_outlined, color: Colors.white, size: 26),
                        colores: const [BrandColors.azulOscuro, BrandColors.azulMarino],
                        onTap: () => navegacion.irA(TabsApp.almacen),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TarjetaAcceso(
                        titulo: 'COTIZACIÓN',
                        subtitulo: 'Productos, voz e historial',
                        icono: const BrandIcon('documents.svg', color: Colors.white, size: 26),
                        colores: const [BrandColors.menta, BrandColors.cian],
                        onTap: () => navegacion.irA(TabsApp.cotizacion),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (almacen.cargando)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (todoAlDia)
                const _AlDia()
              else ...[
                if (atencion.isNotEmpty) ...[
                  const TituloSeccion('REQUERIMIENTOS URGENTES O PENDIENTES'),
                  for (final r in atencion)
                    FadeSlideIn(
                      index: indice++,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TarjetaRequerimiento(requerimiento: r, onTap: () => _abrirRequerimiento(context, r.id!)),
                      ),
                    ),
                ],
                if (porEntregar.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const TituloSeccion('APROBADOS, FALTA ENTREGAR'),
                  for (final r in porEntregar)
                    FadeSlideIn(
                      index: indice++,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TarjetaRequerimiento(requerimiento: r, onTap: () => _abrirRequerimiento(context, r.id!)),
                      ),
                    ),
                ],
                if (herramientas.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const TituloSeccion('HERRAMIENTAS POR DEVOLVER'),
                  for (final h in herramientas)
                    FadeSlideIn(
                      index: indice++,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TarjetaHerramientas(
                          checklist: h,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => HerramientasDetalleScreen(id: h.id!)),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonCuadrado extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final int contador;
  final VoidCallback onTap;

  const _BotonCuadrado({required this.icono, required this.tooltip, required this.onTap, this.contador = 0});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AnimatedPressable(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Badge(
          isLabelVisible: contador > 0,
          label: Text('$contador'),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(color: BrandColors.grisApoyo.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icono, color: BrandColors.azulMarino, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Número grande con su descripción — tocarlo lleva a la lista filtrada.
class _Indicador extends StatelessWidget {
  final int valor;
  final String texto;
  final Color color;
  final VoidCallback onTap;

  const _Indicador({required this.valor, required this.texto, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 96,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$valor',
              style:
                  TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: valor > 0 ? color : colorScheme.outline),
            ),
            const Spacer(),
            Text(
              texto,
              maxLines: 2,
              style:
                  const TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w600, color: BrandColors.grisApoyo),
            ),
          ],
        ),
      ),
    );
  }
}

/// Acceso directo con gradiente de marca (el mismo lenguaje de las tarjetas
/// grandes que tenía el Home), en versión más compacta para ir de a dos.
class _TarjetaAcceso extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final Widget icono;
  final List<Color> colores;
  final VoidCallback onTap;

  const _TarjetaAcceso({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.colores,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colores),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(child: icono),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(titulo, style: AppTextStyles.subtitulo.copyWith(color: Colors.white, fontSize: 16)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlDia extends StatelessWidget {
  const _AlDia();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: BrandColors.cian, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No hay requerimientos pendientes ni herramientas por devolver.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BrandColors.azulMarino),
            ),
          ),
        ],
      ),
    );
  }
}
