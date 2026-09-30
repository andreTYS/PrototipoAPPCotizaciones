import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/checklist_categoria.dart';
import '../models/item_catalogo_checklist.dart';
import '../services/db_helper.dart';
import '../state/checklist_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';

const _unidadesMedida = ['Unidades', 'm', 'Otra'];

/// Agrega un ítem nuevo a la lista base de un checklist (materiales de los
/// requerimientos o herramientas) para que aparezca en todos los que se
/// armen de ahí en adelante — el equivalente de "Agregar producto" para los
/// checklists. Debajo del formulario se ven los que ya se agregaron, con la
/// opción de quitarlos.
class AgregarItemChecklistScreen extends StatefulWidget {
  final TipoChecklist tipo;

  const AgregarItemChecklistScreen({super.key, required this.tipo});

  @override
  State<AgregarItemChecklistScreen> createState() => _AgregarItemChecklistScreenState();
}

class _AgregarItemChecklistScreenState extends State<AgregarItemChecklistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _categoriaOtraController = TextEditingController();
  final _unidadOtraController = TextEditingController();
  List<String> _categorias = [];
  List<ItemCatalogoChecklist> _agregados = [];
  String? _categoriaSeleccionada;
  String _unidadSeleccionada = 'Unidades';
  bool _guardando = false;

  bool get _esMateriales => widget.tipo == TipoChecklist.materiales;
  ChecklistState get _borrador => context.read<BorradoresChecklist>().de(widget.tipo);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _categoriaOtraController.dispose();
    _unidadOtraController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final categorias = await _borrador.nombresCategorias();
    final agregados = await DbHelper.instance.getItemsCatalogoChecklist(widget.tipo);
    if (!mounted) return;
    setState(() {
      _categorias = categorias;
      _agregados = agregados.reversed.toList();
      // Herramientas tiene una sola categoría: se deja elegida de entrada.
      if (_categoriaSeleccionada == null && categorias.length == 1) _categoriaSeleccionada = categorias.first;
    });
  }

  String? get _categoriaEfectiva {
    if (_categoriaSeleccionada == null) return null;
    if (_categoriaSeleccionada == 'Otra') {
      final texto = _categoriaOtraController.text.trim();
      return texto.isEmpty ? null : texto.toUpperCase();
    }
    return _categoriaSeleccionada;
  }

  String? get _unidadEfectiva {
    final texto = _unidadSeleccionada == 'Otra' ? _unidadOtraController.text.trim() : _unidadSeleccionada;
    // "Unidades" es lo implícito de todo el checklist: no hace falta mostrarlo.
    if (texto.isEmpty || texto == 'Unidades') return null;
    return texto;
  }

  Future<void> _guardar() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final categoria = _categoriaEfectiva;
    if (categoria == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige o escribe una categoría.')),
      );
      return;
    }
    if (!formOk) return;

    final nombre = capitalizarPrimeraLetra(_nombreController.text.trim());
    final repetido = _agregados.any(
      (i) => i.nombre.toLowerCase() == nombre.toLowerCase() && i.categoria == categoria,
    );
    if (repetido) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$nombre" ya está en esa categoría.')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final item = ItemCatalogoChecklist(
        tipo: widget.tipo,
        categoria: categoria,
        nombre: nombre,
        unidad: _unidadEfectiva,
        fecha: DateTime.now(),
      );
      final id = await DbHelper.instance.agregarItemCatalogoChecklist(item);
      final guardado = ItemCatalogoChecklist(
        id: id,
        tipo: item.tipo,
        categoria: item.categoria,
        nombre: item.nombre,
        unidad: item.unidad,
        fecha: item.fecha,
      );
      _borrador.incorporarItemCatalogo(guardado);
      if (!mounted) return;
      _nombreController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$nombre" agregado a ${quitarNumeroCategoria(categoria)}.')),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el ítem: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _quitar(ItemCatalogoChecklist item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Quitar de la lista?'),
        content: Text('"${item.nombre}" ya no aparecerá en los próximos checklists. Lo ya registrado no cambia.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (confirmar != true) return;
    await DbHelper.instance.eliminarItemCatalogoChecklist(item.id!);
    _borrador.quitarItemCatalogo(item);
    await _cargar();
  }

  Widget _etiqueta(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(texto, style: AppTextStyles.etiqueta),
    );
  }

  InputDecoration _decoracionCampo({String? hint}) {
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: borde,
      enabledBorder: borde,
      errorBorder: borde.copyWith(borderSide: const BorderSide(color: Colors.red)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: BrandColors.azulMarino,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 20, 20),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _esMateriales ? 'LISTA DE MATERIALES' : 'LISTA DE HERRAMIENTAS',
                              style: AppTextStyles.etiqueta.copyWith(color: Colors.white70),
                            ),
                            Text('Agregar ítem', style: AppTextStyles.titulo.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    Text(
                      _esMateriales
                          ? 'Aparecerá en el checklist de todos los requerimientos nuevos.'
                          : 'Aparecerá en el checklist de todas las salidas de herramientas nuevas.',
                      style: AppTextStyles.apoyo,
                    ),
                    const SizedBox(height: 14),
                    _etiqueta('NOMBRE'),
                    TextFormField(
                      controller: _nombreController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _decoracionCampo(
                          hint: _esMateriales ? 'Ej. Cable PV Solar 10 mm' : 'Ej. Escalera telescópica'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre del ítem.' : null,
                    ),
                    const SizedBox(height: 12),
                    _etiqueta('CATEGORÍA'),
                    DropdownButtonFormField<String>(
                      initialValue: _categoriaSeleccionada,
                      key: ValueKey('categoria-${_categorias.length}-$_categoriaSeleccionada'),
                      isExpanded: true,
                      hint: const Text('Elegir', style: TextStyle(fontSize: 13)),
                      decoration: _decoracionCampo(),
                      items: [
                        ..._categorias.map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(quitarNumeroCategoria(c),
                                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                        const DropdownMenuItem(
                            value: 'Otra', child: Text('Otra (nueva categoría)', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) => setState(() => _categoriaSeleccionada = v),
                    ),
                    if (_categoriaSeleccionada == 'Otra') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _categoriaOtraController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _decoracionCampo(hint: 'Nombre de la categoría'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _etiqueta('UNIDAD DE MEDIDA'),
                    DropdownButtonFormField<String>(
                      initialValue: _unidadSeleccionada,
                      isExpanded: true,
                      decoration: _decoracionCampo(),
                      items: _unidadesMedida
                          .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _unidadSeleccionada = v);
                      },
                    ),
                    if (_unidadSeleccionada == 'Otra') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _unidadOtraController,
                        decoration: _decoracionCampo(hint: 'Ej. rollo, caja, par'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'AGREGADOS A LA LISTA · ${_agregados.length}',
                      style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino),
                    ),
                    const SizedBox(height: 8),
                    if (_agregados.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child:
                            Text('Todavía no agregaste ninguno: la lista es la del Excel.', style: AppTextStyles.apoyo),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Column(
                          children: [
                            for (final item in _agregados)
                              ListTile(
                                dense: true,
                                title: Text(item.nombre,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  [quitarNumeroCategoria(item.categoria), if (item.unidad != null) item.unidad!]
                                      .join(' · '),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  tooltip: 'Quitar de la lista',
                                  onPressed: () => _quitar(item),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.azulMarino,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: const StadiumBorder(),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('AGREGAR A LA LISTA',
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
