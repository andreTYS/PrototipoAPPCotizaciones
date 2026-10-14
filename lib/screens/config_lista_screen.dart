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
import '../utils/formato.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/config_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/estado_vacio.dart';

/// Configuración › Lista de herramientas / Lista de materiales: todo lo
/// que aparece al armar un checklist, por categoría. Se puede agregar un
/// ítem, cambiarle el nombre, la categoría, la unidad (y el precio, en
/// materiales) o quitarlo, y cambiar el nombre de una categoría.
class ConfigListaScreen extends StatefulWidget {
  final TipoChecklist tipo;

  const ConfigListaScreen({super.key, required this.tipo});

  @override
  State<ConfigListaScreen> createState() => _ConfigListaScreenState();
}

class _ConfigListaScreenState extends State<ConfigListaScreen> {
  List<ItemCatalogoChecklist> _items = [];
  bool _cargando = true;
  String _busqueda = '';

  bool get _esMateriales => widget.tipo == TipoChecklist.materiales;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final items = await DbHelper.instance.getItemsCatalogoChecklist(widget.tipo);
    if (!mounted) return;
    setState(() {
      _items = items;
      _cargando = false;
    });
  }

  /// Categorías en el orden en que se arma el checklist.
  List<String> get _categorias {
    final categorias = <String>[];
    for (final i in _items) {
      if (!categorias.contains(i.categoria)) categorias.add(i.categoria);
    }
    return categorias;
  }

  /// Lo que se cambió ya se usa en los próximos checklists.
  void _avisarCambio() => context.read<BorradoresChecklist>().listasCambiadas();

  Future<void> _formulario([ItemCatalogoChecklist? item]) async {
    final resultado = await showModalBottomSheet<ItemCatalogoChecklist>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioItem(tipo: widget.tipo, categorias: _categorias, item: item),
    );
    if (resultado == null) return;
    if (item == null) {
      await DbHelper.instance.agregarItemCatalogoChecklist(resultado);
    } else {
      await DbHelper.instance.actualizarItemCatalogoChecklist(resultado, categoriaAnterior: item.categoria);
    }
    _avisarCambio();
    _cargar();
  }

  Future<void> _eliminar(ItemCatalogoChecklist item) async {
    final confirmar = await confirmarBorrado(
      context,
      titulo: '¿Quitar de la lista?',
      texto: '"${item.nombre}" ya no aparecerá al armar un checklist. Lo ya registrado no cambia.',
    );
    if (!confirmar) return;
    await DbHelper.instance.eliminarItemCatalogoChecklist(item.id!);
    _avisarCambio();
    _cargar();
  }

  Future<void> _renombrarCategoria(String categoria) async {
    final controller = TextEditingController(text: categoria);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre de la categoría'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Categoría'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    final limpio = (nuevo ?? '').trim().toUpperCase();
    if (limpio.isEmpty || limpio == categoria) return;
    await DbHelper.instance.renombrarCategoriaCatalogo(widget.tipo, categoria, limpio);
    _avisarCambio();
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final q = _busqueda.trim().toLowerCase();
    final visibles = [
      for (final i in _items)
        if (q.isEmpty || i.nombre.toLowerCase().contains(q) || i.categoria.toLowerCase().contains(q)) i,
    ];
    final categorias = <String>[];
    for (final i in visibles) {
      if (!categorias.contains(i.categoria)) categorias.add(i.categoria);
    }
    final sinPrecio = _esMateriales ? _items.where((i) => i.precio == null).length : 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'CONFIGURACIÓN',
              titulo: _esMateriales ? 'Materiales y precios' : 'Lista de herramientas',
              conVolver: true,
              abajo: TextField(
                onChanged: (v) => setState(() => _busqueda = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar',
                  hintStyle: const TextStyle(color: Colors.white60),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.14),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : visibles.isEmpty
                      ? const EstadoVacio(
                          icono: Icons.search_off,
                          titulo: 'No hay nada que mostrar',
                          subtitulo: 'Prueba con otra búsqueda o agrega un ítem nuevo.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 10),
                              child: Text(
                                '${cantidadConPalabra(_items.length, 'ÍTEM', 'ÍTEMS')}'
                                '${_esMateriales && sinPrecio > 0 ? ' · $sinPrecio SIN PRECIO' : ''}'
                                ' · TOCA UNO PARA CAMBIARLO',
                                style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino),
                              ),
                            ),
                            for (final categoria in categorias) _bloqueCategoria(categoria, visibles),
                          ],
                        ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: _esMateriales ? 'AGREGAR MATERIAL' : 'AGREGAR HERRAMIENTA',
          icono: Icons.add,
          onPressed: () => _formulario(),
        ),
      ),
    );
  }

  Widget _bloqueCategoria(String categoria, List<ItemCatalogoChecklist> visibles) {
    final colorScheme = Theme.of(context).colorScheme;
    final estilo = estiloDeCategoriaChecklist(categoria);
    final items = visibles.where((i) => i.categoria == categoria).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: estilo.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(estilo.icono, color: estilo.color, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    quitarNumeroCategoria(categoria),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: BrandColors.azulMarino),
                  ),
                ),
                Text('${items.length}', style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w800)),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 18, color: colorScheme.outline),
                  tooltip: 'Cambiar nombre de la categoría',
                  onPressed: () => _renombrarCategoria(categoria),
                ),
              ],
            ),
          ),
          for (final item in items)
            InkWell(
              onTap: () => _formulario(item),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.nombre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          if ((item.unidad ?? '').isNotEmpty) Text('Unidad: ${item.unidad}', style: AppTextStyles.apoyo),
                        ],
                      ),
                    ),
                    if (_esMateriales)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: item.precio == null ? ColoresEstado.pendienteFondo : BrandColors.cian.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.precio == null ? 'Poner precio' : soles(item.precio!),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: item.precio == null ? ColoresEstado.pendiente : BrandColors.azulMarino,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.outline),
                      tooltip: 'Quitar de la lista',
                      onPressed: () => _eliminar(item),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Alta o cambio de un ítem de la lista: nombre, categoría (una existente
/// o una nueva), unidad y — en materiales — precio por defecto.
class _FormularioItem extends StatefulWidget {
  final TipoChecklist tipo;
  final List<String> categorias;
  final ItemCatalogoChecklist? item;

  const _FormularioItem({required this.tipo, required this.categorias, this.item});

  @override
  State<_FormularioItem> createState() => _FormularioItemState();
}

class _FormularioItemState extends State<_FormularioItem> {
  static const _nueva = '__nueva__';

  late final _nombreController = TextEditingController(text: widget.item?.nombre ?? '');
  late final _unidadController = TextEditingController(text: widget.item?.unidad ?? '');
  late final _precioController = TextEditingController(text: widget.item?.precio?.toStringAsFixed(2) ?? '');
  final _categoriaNuevaController = TextEditingController();
  late String? _categoria = widget.item?.categoria ??
      (widget.categorias.length == 1 ? widget.categorias.first : null);
  bool _intento = false;

  bool get _esMateriales => widget.tipo == TipoChecklist.materiales;

  @override
  void dispose() {
    _nombreController.dispose();
    _unidadController.dispose();
    _precioController.dispose();
    _categoriaNuevaController.dispose();
    super.dispose();
  }

  String? get _categoriaEfectiva {
    if (_categoria == _nueva) {
      final t = _categoriaNuevaController.text.trim().toUpperCase();
      return t.isEmpty ? null : t;
    }
    return _categoria;
  }

  void _guardar() {
    final nombre = _nombreController.text.trim();
    final categoria = _categoriaEfectiva;
    if (nombre.isEmpty || categoria == null) {
      setState(() => _intento = true);
      return;
    }
    final precioTexto = _precioController.text.trim().replaceAll(',', '.');
    final unidad = _unidadController.text.trim();
    final base = widget.item;
    Navigator.pop(
      context,
      ItemCatalogoChecklist(
        id: base?.id,
        tipo: widget.tipo,
        categoria: categoria,
        nombre: capitalizarPrimeraLetra(nombre),
        unidad: unidad.isEmpty ? null : unidad,
        fecha: base?.fecha ?? DateTime.now(),
        precio: _esMateriales && precioTexto.isNotEmpty ? double.tryParse(precioTexto) : null,
        orden: base?.orden,
        esBase: base?.esBase ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HojaAlmacen(
      titulo: widget.item == null ? (_esMateriales ? 'Nuevo material' : 'Nueva herramienta') : 'Cambiar ítem',
      texto: _esMateriales
          ? 'Se usa en los próximos requerimientos. El precio es el que sale por defecto (se puede cambiar en cada requerimiento).'
          : 'Se usa en los próximos checklists de herramientas.',
      children: [
        TextField(
          controller: _nombreController,
          textCapitalization: TextCapitalization.sentences,
          decoration: decoracionCampoHoja('Nombre *', icono: Icons.label_outline)
              .copyWith(errorText: _intento && _nombreController.text.trim().isEmpty ? 'Escribe el nombre' : null),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _categoria,
          isExpanded: true,
          decoration: decoracionCampoHoja('Categoría *', icono: Icons.category_outlined)
              .copyWith(errorText: _intento && _categoriaEfectiva == null ? 'Elige o escribe una categoría' : null),
          items: [
            for (final c in widget.categorias) DropdownMenuItem(value: c, child: Text(quitarNumeroCategoria(c))),
            const DropdownMenuItem(value: _nueva, child: Text('Otra categoría nueva…')),
          ],
          onChanged: (v) => setState(() => _categoria = v),
        ),
        if (_categoria == _nueva) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _categoriaNuevaController,
            textCapitalization: TextCapitalization.characters,
            decoration: decoracionCampoHoja('Nombre de la categoría nueva', icono: Icons.add_circle_outline),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _unidadController,
                decoration: decoracionCampoHoja('Unidad (opcional)', icono: Icons.straighten_outlined),
              ),
            ),
            if (_esMateriales) ...[
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _precioController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: decoracionCampoHoja('Precio S/', icono: Icons.sell_outlined),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        BotonPrincipal(texto: 'GUARDAR', icono: Icons.check_rounded, color: BrandColors.cian, onPressed: _guardar),
      ],
    );
  }
}
