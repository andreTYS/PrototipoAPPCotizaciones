import 'package:flutter/material.dart';
import '../models/checklist_categoria.dart';
import '../models/item_catalogo_checklist.dart';
import '../models/producto.dart';
import '../services/db_helper.dart';
import '../state/checklist_state.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import 'buscador_productos.dart';

/// Hoja para agregar un ítem a una categoría del checklist — a mano o
/// buscando en el catálogo. La usan tanto la pantalla de cada categoría
/// como el resumen final, así que vive en un solo lugar.
///
/// Por defecto el ítem se suma solo a este checklist; con "Guardar también
/// en la lista" queda además en la lista base, para que aparezca en todos
/// los que se armen después.
Future<void> mostrarAgregarItemChecklist(
  BuildContext context, {
  required ChecklistState checklist,
  required int categoriaIndex,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HojaAgregarItem(checklist: checklist, categoriaIndex: categoriaIndex),
  );
}

class _HojaAgregarItem extends StatefulWidget {
  final ChecklistState checklist;
  final int categoriaIndex;

  const _HojaAgregarItem({required this.checklist, required this.categoriaIndex});

  @override
  State<_HojaAgregarItem> createState() => _HojaAgregarItemState();
}

class _HojaAgregarItemState extends State<_HojaAgregarItem> {
  final _controller = TextEditingController();
  bool _guardarEnLista = false;
  bool _guardando = false;

  String get _nombreCategoria => widget.checklist.categorias[widget.categoriaIndex].nombre;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _agregar(String texto, {bool esProducto = false}) async {
    final limpio = texto.trim();
    if (limpio.isEmpty || _guardando) return;
    setState(() => _guardando = true);

    if (_guardarEnLista) {
      try {
        await DbHelper.instance.agregarItemCatalogoChecklist(
          ItemCatalogoChecklist(
            tipo: widget.checklist.tipo,
            categoria: _nombreCategoria,
            nombre: capitalizarPrimeraLetra(limpio),
            fecha: DateTime.now(),
          ),
        );
      } catch (e) {
        if (mounted) {
          setState(() => _guardando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar en la lista: $e')),
          );
        }
        return;
      }
    }

    widget.checklist.agregarItemEn(widget.categoriaIndex, limpio, esProducto: esProducto);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _buscarEnCatalogo() async {
    final producto = await showModalBottomSheet<Producto>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BuscadorProductos(titulo: 'Buscar en el catálogo'),
    );
    if (producto != null) await _agregar(producto.nombre, esProducto: true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agregar ítem a "${quitarNumeroCategoria(_nombreCategoria)}"',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: BrandColors.azulMarino),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (texto) => _agregar(texto),
                decoration: InputDecoration(
                  hintText: 'Nombre del ítem',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _guardarEnLista,
                onChanged: (v) => setState(() => _guardarEnLista = v),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: BrandColors.cian,
                title: const Text(
                  'Guardar también en la lista',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Aparecerá en los próximos checklists',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _guardando ? null : _buscarEnCatalogo,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Del catálogo'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: BrandColors.cian),
                        foregroundColor: BrandColors.azulMarino,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _guardando ? null : () => _agregar(_controller.text),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Agregar'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
