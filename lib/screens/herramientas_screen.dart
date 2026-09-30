import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../state/almacen_state.dart';
import '../utils/rutas.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/fade_slide_in.dart';
import 'agregar_item_checklist_screen.dart';
import 'checklist_screen.dart';
import 'herramientas_detalle_screen.dart';

enum FiltroHerramientas { todos, pendiente, conforme }

Route<void> rutaHerramientas({FiltroHerramientas filtro = FiltroHerramientas.todos}) {
  return MaterialPageRoute<void>(
    settings: const RouteSettings(name: Rutas.listaHerramientas),
    builder: (_) => HerramientasScreen(filtroInicial: filtro),
  );
}

/// Checklists de herramientas: cada salida a obra queda pendiente de
/// devolución hasta que un encargado confirma que volvió todo (Conforme).
class HerramientasScreen extends StatefulWidget {
  final FiltroHerramientas filtroInicial;

  const HerramientasScreen({super.key, this.filtroInicial = FiltroHerramientas.todos});

  @override
  State<HerramientasScreen> createState() => _HerramientasScreenState();
}

class _HerramientasScreenState extends State<HerramientasScreen> {
  late FiltroHerramientas _filtro = widget.filtroInicial;
  final _busquedaController = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  bool _pasaFiltro(ChecklistHerramientas h, FiltroHerramientas filtro) => switch (filtro) {
        FiltroHerramientas.todos => true,
        FiltroHerramientas.pendiente => h.estado == EstadoHerramientas.pendiente,
        FiltroHerramientas.conforme => h.estado == EstadoHerramientas.conforme,
      };

  bool _coincideBusqueda(ChecklistHerramientas h) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return h.obra.toLowerCase().contains(q) ||
        h.responsable.toLowerCase().contains(q) ||
        h.numero.toLowerCase().contains(q);
  }

  Widget _pildora(List<ChecklistHerramientas> todos, FiltroHerramientas filtro, String texto) {
    final cantidad = todos.where((h) => _pasaFiltro(h, filtro)).length;
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
    final todos = almacen.herramientas;
    final lista = todos.where((h) => _pasaFiltro(h, _filtro) && _coincideBusqueda(h)).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'ALMACÉN',
              titulo: 'Checklist de herramientas',
              conVolver: true,
              acciones: [
                IconButton(
                  icon: const Icon(Icons.playlist_add, color: Colors.white),
                  tooltip: 'Agregar herramienta a la lista',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AgregarItemChecklistScreen(tipo: TipoChecklist.herramientas)),
                  ),
                ),
              ],
              abajo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BuscadorEncabezado(
                    controller: _busquedaController,
                    hint: 'Buscar por obra, responsable o número',
                    onChanged: (v) => setState(() => _busqueda = v),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _pildora(todos, FiltroHerramientas.todos, 'Todos'),
                        _pildora(todos, FiltroHerramientas.pendiente, 'Pendiente devolución'),
                        _pildora(todos, FiltroHerramientas.conforme, 'Conforme'),
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
                        icono: Icons.handyman_outlined,
                        titulo: 'Aún no hay salidas de herramientas',
                        subtitulo:
                            'Registra la primera con el checklist de siempre: queda pendiente hasta que se devuelva.',
                      )
                    : lista.isEmpty
                        ? EstadoVacio(
                            icono: Icons.search_off,
                            titulo: 'Ningún checklist coincide',
                            subtitulo: 'Prueba con otra búsqueda o cambia el filtro de estado.',
                            textoBoton: 'Ver todos',
                            onBoton: () => setState(() {
                              _filtro = FiltroHerramientas.todos;
                              _busqueda = '';
                              _busquedaController.clear();
                            }),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            itemCount: lista.length,
                            itemBuilder: (context, index) {
                              final h = lista[index];
                              return FadeSlideIn(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TarjetaHerramientas(
                                    checklist: h,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => HerramientasDetalleScreen(id: h.id!)),
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
          texto: 'REGISTRAR SALIDA',
          icono: Icons.add,
          onPressed: () => abrirChecklist(context, TipoChecklist.herramientas),
        ),
      ),
    );
  }
}
