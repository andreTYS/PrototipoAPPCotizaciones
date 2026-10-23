import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_cliente.dart';
import '../services/db_helper.dart';
import '../state/almacen_state.dart';
import '../state/auth_state.dart';
import '../theme/brand_colors.dart';
import '../widgets/config_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import 'checklists_anteriores_screen.dart';
import 'config_lista_screen.dart';
import 'config_maletas_screen.dart';
import 'config_productos_screen.dart';
import 'config_screen.dart';
import 'herramientas_screen.dart';
import 'historial_cotizaciones_screen.dart';
import 'requerimientos_screen.dart';
import '../models/checklist_categoria.dart';

/// Configuración: desde aquí se puede cambiar todo lo que usa la app —
/// los productos de las cotizaciones, las maletas, las listas de
/// materiales (con sus precios) y de herramientas — y ver el historial
/// completo de cotizaciones, requerimientos y checklists.
class ConfiguracionScreen extends StatelessWidget {
  const ConfiguracionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.watch<AlmacenState>();
    final auth = context.watch<AuthState>();
    final servidor = DbHelper.instance.esServidor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            const EncabezadoCurvo(
                etiqueta: 'AJUSTES', titulo: 'Configuración', conVolver: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (servidor && auth.usuario != null) ...[
                    const GrupoConfig('MI CUENTA'),
                    OpcionConfig(
                      icono: Icons.account_circle_outlined,
                      color: BrandColors.azulOscuro,
                      titulo: auth.usuario!.nombre,
                      subtitulo:
                          'Rol: ${auth.usuario!.rolEtiqueta} · toca para cerrar sesión',
                      onTap: () async {
                        final salir = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Cerrar sesión'),
                            content: const Text(
                                '¿Salir de tu cuenta en este dispositivo?'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Salir')),
                            ],
                          ),
                        );
                        if (salir != true || !context.mounted) return;
                        context
                            .read<AlmacenState>()
                            .detenerActualizacionAutomatica();
                        await context.read<AuthState>().salir();
                        // El ingreso se abre solo desde el arranque: se reinicia la app.
                        ApiCliente.instancia.alVencerSesion?.call();
                      },
                    ),
                  ],
                  const GrupoConfig('COTIZACIÓN'),
                  OpcionConfig(
                    icono: Icons.inventory_2_outlined,
                    color: BrandColors.cian,
                    titulo: 'Productos de cotización',
                    subtitulo:
                        'Agregar productos y cambiar su precio, costo, categoría, foto y demás datos',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ConfigProductosScreen())),
                  ),
                  OpcionConfig(
                    icono: Icons.receipt_long_outlined,
                    color: BrandColors.cian,
                    titulo: 'Historial de cotizaciones',
                    subtitulo:
                        'Todas las cotizaciones: ver, compartir o eliminar',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const HistorialCotizacionesScreen())),
                  ),
                  const GrupoConfig('ALMACÉN'),
                  OpcionConfig(
                    icono: Icons.work_outline_rounded,
                    titulo: 'Maletas',
                    subtitulo:
                        'Crear maletas, cambiar sus herramientas y fotos, o eliminarlas',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ConfigMaletasScreen())),
                  ),
                  OpcionConfig(
                    icono: Icons.handyman_outlined,
                    titulo: 'Lista de herramientas',
                    subtitulo:
                        'Las herramientas del checklist: agregar, cambiar o quitar',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ConfigListaScreen(
                              tipo: TipoChecklist.herramientas)),
                    ),
                  ),
                  OpcionConfig(
                    icono: Icons.assignment_outlined,
                    titulo: 'Lista de materiales y precios',
                    subtitulo:
                        'Los materiales de los requerimientos: agregar, cambiar y ponerles precio',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ConfigListaScreen(
                              tipo: TipoChecklist.materiales)),
                    ),
                  ),
                  const GrupoConfig('HISTORIALES'),
                  OpcionConfig(
                    icono: Icons.assignment_turned_in_outlined,
                    titulo: 'Historial de requerimientos',
                    subtitulo: 'Todos los requerimientos, en cualquier estado',
                    contador: '${almacen.requerimientos.length}',
                    onTap: () =>
                        Navigator.of(context).push(rutaRequerimientos()),
                  ),
                  OpcionConfig(
                    icono: Icons.luggage_outlined,
                    titulo: 'Historial de checklists de herramientas',
                    subtitulo: 'Todas las salidas de herramientas y maletas',
                    contador: '${almacen.herramientas.length}',
                    onTap: () => Navigator.of(context).push(rutaHerramientas()),
                  ),
                  if (!servidor && almacen.checklistsAnteriores > 0)
                    OpcionConfig(
                      icono: Icons.history,
                      titulo: 'Checklists de obra anteriores',
                      subtitulo: 'Guardados con la versión anterior de la app',
                      contador: '${almacen.checklistsAnteriores}',
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const ChecklistsAnterioresScreen())),
                    ),
                  if (!servidor) ...[
                    const GrupoConfig('AVANZADO'),
                    OpcionConfig(
                      icono: Icons.sync,
                      color: BrandColors.grisApoyo,
                      titulo: 'Sincronizar catálogo con un servidor',
                      subtitulo:
                          'Trae el catálogo desde la PC. Lo que cambiaste aquí se conserva.',
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ConfigScreen())),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
