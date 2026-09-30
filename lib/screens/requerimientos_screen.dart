import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/checklist_categoria.dart';
import '../models/requerimiento.dart';
import '../state/almacen_state.dart';
import '../utils/rutas.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/fade_slide_in.dart';
import 'agregar_item_checklist_screen.dart';
import 'checklist_screen.dart';
import 'requerimiento_detalle_screen.dart';

/// Qué requerimientos mostrar: por estado, o solo los urgentes que aún no se
/// entregan (a lo que lleva la tarjeta "Urgentes" del Inicio).
enum FiltroRequerimientos { todos, pendiente, aprobado, entregado, urgentes }

Route<void> rutaRequerimientos({FiltroRequerimientos filtro = FiltroRequerimientos.todos}) {
  return MaterialPageRoute<void>(
    settings: const RouteSettings(name: Rutas.listaRequerimientos),
    builder: (_) => RequerimientosScreen(filtroInicial: filtro),
  );
}

/// Requerimientos de materiales a almacén: su estado de un vistazo, filtros
/// por estado, búsqueda por obra/solicitante/número, y el botón para crear
/// uno nuevo con el checklist de siempre.
class RequerimientosScreen extends StatefulWidget {
  final FiltroRequerimientos filtroInicial;

  const RequerimientosScreen({super.key, this.filtroInicial = FiltroRequerimientos.todos});

  @override
  State<RequerimientosScreen> createState() => _RequerimientosScreenState();
}

class _RequerimientosScreenState extends State<RequerimientosScreen> {
  late FiltroRequerimientos _filtro = widget.filtroInicial;
  final _busquedaController = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  bool _pasaFiltro(Requerimiento r, FiltroRequerimientos filtro) => switch (filtro) {
        FiltroRequerimientos.todos => true,
        FiltroRequerimientos.pendiente => r.estado == EstadoRequerimiento.pendiente,
        FiltroRequerimientos.aprobado => r.estado == EstadoRequerimiento.aprobado,
        FiltroRequerimientos.entregado => r.estado == EstadoRequerimiento.entregado,
        FiltroRequerimientos.urgentes => r.urgente && !r.entregado,
      };

  bool _coincideBusqueda(Requerimiento r) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.obra.toLowerCase().contains(q) ||
        r.solicitante.toLowerCase().contains(q) ||
        r.numero.toLowerCase().contains(q);
  }

  Widget _pildora(List<Requerimiento> todos, FiltroRequerimientos filtro, String texto) {
    final cantidad = todos.where((r) => _pasaFiltro(r, filtro)).length;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PildoraFiltro(
        texto: '$texto · $cantidad',
        activo: _filtro == filtro,
        onTap: () => setState(() => _filtro = filtro),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final almacen = context.watch<AlmacenState>();
    final todos = almacen.requerimientos;
    final lista = todos.where((r) => _pasaFiltro(r, _filtro) && _coincideBusqueda(r)).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'ALMACÉN',
              titulo: 'Requerimientos',
              conVolver: true,
              acciones: [
                IconButton(
                  icon: const Icon(Icons.playlist_add, color: Colors.white),
                  tooltip: 'Agregar ítem a la lista de materiales',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AgregarItemChecklistScreen(tipo: TipoChecklist.materiales)),
                  ),
                ),
              ],
              abajo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BuscadorEncabezado(
                    controller: _busquedaController,
                    hint: 'Buscar por obra, solicitante o número',
                    onChanged: (v) => setState(() => _busqueda = v),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _pildora(todos, FiltroRequerimientos.todos, 'Todos'),
                        _pildora(todos, FiltroRequerimientos.pendiente, 'Pendiente aprobación'),
                        _pildora(todos, FiltroRequerimientos.aprobado, 'Aprobado'),
                        _pildora(todos, FiltroRequerimientos.entregado, 'Entregado'),
                        _pildora(todos, FiltroRequerimientos.urgentes, 'Urgentes'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: almacen.cargar,
                child: todos.isEmpty
                    ? const EstadoVacio(
                        icono: Icons.assignment_outlined,
                        titulo: 'Aún no hay requerimientos',
                        subtitulo:
                            'Crea el primero: marcas los materiales en el checklist de siempre y se envía para aprobación.',
                      )
                    : lista.isEmpty
                        ? EstadoVacio(
                            icono: Icons.search_off,
                            titulo: 'Ningún requerimiento coincide',
                            subtitulo: 'Prueba con otra búsqueda o cambia el filtro de estado.',
                            textoBoton: 'Ver todos',
                            onBoton: () => setState(() {
                              _filtro = FiltroRequerimientos.todos;
                              _busqueda = '';
                              _busquedaController.clear();
                            }),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            itemCount: lista.length,
                            itemBuilder: (context, index) {
                              final r = lista[index];
                              return FadeSlideIn(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TarjetaRequerimiento(
                                    requerimiento: r,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => RequerimientoDetalleScreen(id: r.id!)),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: 'NUEVO REQUERIMIENTO',
          icono: Icons.add,
          onPressed: () => abrirChecklist(context, TipoChecklist.materiales),
        ),
      ),
    );
  }
}
