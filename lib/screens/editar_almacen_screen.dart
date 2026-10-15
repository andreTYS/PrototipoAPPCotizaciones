import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/checklist_categoria.dart';
import '../models/item_catalogo_checklist.dart';
import '../models/producto.dart';
import '../services/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../utils/formato.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/buscador_productos.dart';
import '../widgets/config_widgets.dart';
import '../widgets/encabezado_curvo.dart';

/// Lo que devuelve la edición: los datos y las categorías ya cambiadas, y
/// un resumen de qué se cambió (para dejarlo anotado en el documento).
class ResultadoEdicion {
  final String obra;
  final String persona;
  final String observaciones;
  final bool urgente;
  final List<ChecklistCategoriaState> categorias;
  final List<String> resumen;

  /// Ítems agregados que además se quieren guardar en la lista base.
  final List<ItemCatalogoChecklist> paraLaLista;

  const ResultadoEdicion({
    required this.obra,
    required this.persona,
    required this.observaciones,
    required this.urgente,
    required this.categorias,
    required this.resumen,
    required this.paraLaLista,
  });

  /// Cuántos ítems nuevos se agregaron en esta edición.
  int get nuevos => resumen.where((l) => l.startsWith('+ ')).length;
}

/// Editar un requerimiento o un checklist de herramientas ya registrado
/// (se llega aquí después de ingresar la clave): cambiar sus datos, agregar
/// lo que se olvidó o se pidió a último momento (material, herramienta o
/// producto nuevo), cambiar cantidades y precios, o quitar algo.
class EditarAlmacenScreen extends StatefulWidget {
  final TipoChecklist tipo;
  final String numero;
  final String obra;
  final String persona;
  final String observaciones;
  final bool urgente;
  final List<ChecklistCategoriaState> categorias;

  const EditarAlmacenScreen({
    super.key,
    required this.tipo,
    required this.numero,
    required this.obra,
    required this.persona,
    required this.observaciones,
    required this.urgente,
    required this.categorias,
  });

  @override
  State<EditarAlmacenScreen> createState() => _EditarAlmacenScreenState();
}

class _EditarAlmacenScreenState extends State<EditarAlmacenScreen> {
  late final _obraController = TextEditingController(text: widget.obra);
  late final _personaController = TextEditingController(text: widget.persona);
  late final _observacionesController = TextEditingController(text: widget.observaciones);
  late bool _urgente = widget.urgente;

  /// Copia de trabajo (los cambios se aplican al guardar).
  late final List<ChecklistCategoriaState> _categorias = soloMarcados(widget.categorias);

  /// Cómo estaba cada ítem al abrir, para saber qué cambió.
  late final Map<String, int> _original;
  final List<ItemCatalogoChecklist> _paraLaLista = [];
  bool _intentoGuardar = false;

  bool get _esMateriales => widget.tipo == TipoChecklist.materiales;

  static String _clave(String categoria, String texto) => '$categoria|$texto';

  @override
  void initState() {
    super.initState();
    _original = {
      for (final c in _categorias)
        for (final i in c.items) _clave(c.nombre, i.texto): i.cantidad,
    };
  }

  @override
  void dispose() {
    _obraController.dispose();
    _personaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  double get _total => totalPrecioCategorias(_categorias);

  void _quitar(ChecklistCategoriaState c, ChecklistItemEntry i) => setState(() {
        c.items.remove(i);
        if (c.items.isEmpty) _categorias.remove(c);
      });

  Future<void> _cambiarPrecio(ChecklistItemEntry i) async {
    final precio = await pedirNumero(
      context,
      titulo: 'Precio unitario',
      etiqueta: 'Precio por unidad',
      valorInicial: i.precio,
      prefijo: 'S/ ',
    );
    if (precio != null) setState(() => i.precio = precio);
  }

  Future<void> _agregar() async {
    final nuevo = await showModalBottomSheet<_NuevoItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HojaAgregar(tipo: widget.tipo, categorias: [for (final c in _categorias) c.nombre]),
    );
    if (nuevo == null) return;
    setState(() {
      var categoria = _categorias.where((c) => c.nombre == nuevo.categoria).firstOrNull;
      if (categoria == null) {
        categoria = ChecklistCategoriaState(nombre: nuevo.categoria, items: []);
        _categorias.add(categoria);
      }
      final existente = categoria.items.where((i) => i.texto.toLowerCase() == nuevo.nombre.toLowerCase()).firstOrNull;
      if (existente != null) {
        existente.cantidad += nuevo.cantidad;
        if (nuevo.precio != null) existente.precio = nuevo.precio;
      } else {
        categoria.items.add(ChecklistItemEntry(
          texto: nuevo.nombre,
          cantidad: nuevo.cantidad,
          unidad: nuevo.unidad,
          precio: _esMateriales ? nuevo.precio : null,
          esExtra: true,
          esProducto: nuevo.esProducto,
          agregadoDespues: true,
        ));
      }
    });
    if (nuevo.guardarEnLista) {
      _paraLaLista.add(ItemCatalogoChecklist(
        tipo: widget.tipo,
        categoria: nuevo.categoria,
        nombre: nuevo.nombre,
        unidad: nuevo.unidad,
        fecha: DateTime.now(),
        precio: _esMateriales ? nuevo.precio : null,
      ));
    }
  }

  List<String> _resumen() {
    final r = <String>[];
    if (_obraController.text.trim() != widget.obra) r.add('obra: "${widget.obra}" → "${_obraController.text.trim()}"');
    if (_personaController.text.trim() != widget.persona) {
      r.add('${_esMateriales ? 'solicitante' : 'responsable'}: "${widget.persona}" → "${_personaController.text.trim()}"');
    }
    final ahora = <String, ChecklistItemEntry>{
      for (final c in _categorias)
        for (final i in c.items) _clave(c.nombre, i.texto): i,
    };
    for (final e in ahora.entries) {
      final antes = _original[e.key];
      if (antes == null) {
        r.add('+ ${e.value.texto} ${e.value.cantidadTexto}');
      } else if (antes != e.value.cantidad) {
        r.add('${e.value.texto}: ×$antes → ×${e.value.cantidad}');
      }
    }
    for (final k in _original.keys) {
      if (!ahora.containsKey(k)) r.add('− ${k.split('|').last}');
    }
    return r;
  }

  void _guardar() {
    final obra = _obraController.text.trim();
    final persona = _personaController.text.trim();
    if (obra.isEmpty || persona.isEmpty) {
      setState(() => _intentoGuardar = true);
      return;
    }
    if (_categorias.every((c) => c.items.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe quedar al menos un ítem. Para quitarlo todo, elimina el documento.')),
      );
      return;
    }
    Navigator.of(context).pop(ResultadoEdicion(
      obra: obra,
      persona: persona,
      observaciones: _observacionesController.text.trim(),
      urgente: _esMateriales && _urgente,
      categorias: _categorias,
      resumen: _resumen(),
      paraLaLista: _paraLaLista,
    ));
  }

  InputDecoration _decoracion(String label, IconData icono, {String? error}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono, size: 20),
        filled: true,
        errorText: error,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'EDITAR · ${widget.numero}',
              titulo: _esMateriales ? 'Editar requerimiento' : 'Editar checklist',
              conVolver: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  TextField(
                    controller: _obraController,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: _decoracion('Obra / proyecto *', Icons.home_work_outlined,
                        error: _intentoGuardar && _obraController.text.trim().isEmpty ? 'Escribe la obra' : null),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _personaController,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: _decoracion(
                      _esMateriales ? 'Solicitante *' : 'Responsable que se las lleva *',
                      Icons.person_outline,
                      error: _intentoGuardar && _personaController.text.trim().isEmpty ? 'Escribe el nombre' : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _observacionesController,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    decoration: _decoracion('Observaciones', Icons.notes_outlined),
                  ),
                  if (_esMateriales)
                    Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile(
                        value: _urgente,
                        onChanged: (v) => setState(() => _urgente = v),
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: Colors.white,
                        activeTrackColor: ColoresEstado.urgente,
                        title: const Text('Urgente', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      '${_esMateriales ? 'MATERIALES' : 'HERRAMIENTAS'} · ${_categorias.fold<int>(0, (s, c) => s + c.items.length)}',
                      style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino),
                    ),
                  ),
                  for (final categoria in List.of(_categorias))
                    Container(
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
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: Row(
                              children: [
                                Icon(estiloDeCategoriaChecklist(categoria.nombre).icono,
                                    size: 18, color: estiloDeCategoriaChecklist(categoria.nombre).color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    quitarNumeroCategoria(categoria.nombre),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 14, color: BrandColors.azulMarino),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final item in List.of(categoria.items))
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                              decoration: BoxDecoration(
                                border: Border(
                                    top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.texto,
                                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                        if (item.agregadoDespues)
                                          const Text('Nuevo', style: TextStyle(fontSize: 11, color: BrandColors.cian, fontWeight: FontWeight.w800)),
                                        if (_esMateriales)
                                          InkWell(
                                            onTap: () => _cambiarPrecio(item),
                                            child: Text(
                                              item.precio == null
                                                  ? 'Poner precio'
                                                  : '${soles(item.precio!)} c/u · ${soles(item.subtotal)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: item.precio == null ? ColoresEstado.pendiente : BrandColors.azulMarino,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                                    onPressed: item.cantidad > 1 ? () => setState(() => item.cantidad--) : null,
                                  ),
                                  Text(item.cantidadTexto, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.add_circle_outline, size: 22),
                                    onPressed: () => setState(() => item.cantidad++),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.outline),
                                    tooltip: 'Quitar',
                                    onPressed: () => _quitar(categoria, item),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_esMateriales && _categorias.any((c) => c.items.any((i) => i.precio != null)))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: BrandColors.azulMarino, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('TOTAL ESTIMADO',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12)),
                          ),
                          Text(soles(_total),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _agregar,
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(_esMateriales ? 'Agregar material' : 'Agregar herramienta'),
                    style: estiloBotonSecundario,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.cian,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NuevoItem {
  final String nombre;
  final String categoria;
  final int cantidad;
  final String? unidad;
  final double? precio;
  final bool esProducto;
  final bool guardarEnLista;

  const _NuevoItem({
    required this.nombre,
    required this.categoria,
    required this.cantidad,
    this.unidad,
    this.precio,
    this.esProducto = false,
    this.guardarEnLista = false,
  });
}

/// Agregar un ítem a lo que se está editando: escrito a mano (algo nuevo),
/// o elegido de la lista de materiales/herramientas o del catálogo de
/// productos.
class _HojaAgregar extends StatefulWidget {
  final TipoChecklist tipo;
  final List<String> categorias;

  const _HojaAgregar({required this.tipo, required this.categorias});

  @override
  State<_HojaAgregar> createState() => _HojaAgregarState();
}

class _HojaAgregarState extends State<_HojaAgregar> {
  static const _otra = '__otra__';

  final _nombreController = TextEditingController();
  final _cantidadController = TextEditingController(text: '1');
  final _unidadController = TextEditingController();
  final _precioController = TextEditingController();
  final _categoriaNuevaController = TextEditingController();
  late String? _categoria = widget.categorias.length == 1 ? widget.categorias.first : null;
  bool _esProducto = false;
  bool _guardarEnLista = false;
  bool _intento = false;

  bool get _esMateriales => widget.tipo == TipoChecklist.materiales;

  @override
  void dispose() {
    _nombreController.dispose();
    _cantidadController.dispose();
    _unidadController.dispose();
    _precioController.dispose();
    _categoriaNuevaController.dispose();
    super.dispose();
  }

  String? get _categoriaEfectiva {
    if (_categoria == _otra) {
      final t = _categoriaNuevaController.text.trim().toUpperCase();
      return t.isEmpty ? null : t;
    }
    return _categoria;
  }

  /// Si el nombre ya existe en la lista, no hace falta guardarlo de nuevo.
  Future<void> _deLaLista() async {
    final item = await showModalBottomSheet<ItemCatalogoChecklist>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ElegirDeLista(tipo: widget.tipo),
    );
    if (item == null) return;
    setState(() {
      _nombreController.text = item.nombre;
      _unidadController.text = item.unidad ?? '';
      if (item.precio != null) _precioController.text = item.precio!.toStringAsFixed(2);
      final existente = widget.categorias.where((c) => c.toUpperCase() == item.categoria.toUpperCase());
      if (existente.isNotEmpty) {
        _categoria = existente.first;
      } else {
        _categoria = _otra;
        _categoriaNuevaController.text = item.categoria;
      }
      _esProducto = false;
      _guardarEnLista = false;
    });
  }

  Future<void> _deProductos() async {
    final producto = await showModalBottomSheet<Producto>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BuscadorProductos(titulo: 'Buscar en el catálogo'),
    );
    if (producto == null) return;
    setState(() {
      _nombreController.text = producto.nombre;
      if (producto.precioVenta != null) _precioController.text = producto.precioVenta!.toStringAsFixed(2);
      _esProducto = true;
      _guardarEnLista = false;
    });
  }

  void _guardar() {
    final nombre = _nombreController.text.trim();
    final categoria = _categoriaEfectiva;
    final cantidad = int.tryParse(_cantidadController.text.trim()) ?? 0;
    if (nombre.isEmpty || categoria == null || cantidad < 1) {
      setState(() => _intento = true);
      return;
    }
    final unidad = _unidadController.text.trim();
    final precio = double.tryParse(_precioController.text.trim().replaceAll(',', '.'));
    Navigator.pop(
      context,
      _NuevoItem(
        nombre: capitalizarPrimeraLetra(nombre),
        categoria: categoria,
        cantidad: cantidad,
        unidad: unidad.isEmpty ? null : unidad,
        precio: precio,
        esProducto: _esProducto,
        guardarEnLista: _guardarEnLista,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HojaAlmacen(
      titulo: _esMateriales ? 'Agregar material' : 'Agregar herramienta',
      texto: _esMateriales
          ? 'Algo que se olvidó o que se pidió a último momento. Elígelo de la lista o escríbelo si es nuevo.'
          : 'Una herramienta que se olvidó. Elígela de la lista o escríbela si es nueva.',
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _deLaLista,
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('De la lista'),
                style: estiloBotonSecundario,
              ),
            ),
            if (_esMateriales) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deProductos,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('De productos'),
                  style: estiloBotonSecundario,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nombreController,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _esProducto = false),
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
            const DropdownMenuItem(value: _otra, child: Text('Otra categoría…')),
          ],
          onChanged: (v) => setState(() => _categoria = v),
        ),
        if (_categoria == _otra) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _categoriaNuevaController,
            textCapitalization: TextCapitalization.characters,
            decoration: decoracionCampoHoja('Nombre de la categoría', icono: Icons.add_circle_outline),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cantidadController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: decoracionCampoHoja('Cantidad *', icono: Icons.numbers),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unidadController,
                decoration: decoracionCampoHoja('Unidad', icono: Icons.straighten_outlined),
              ),
            ),
          ],
        ),
        if (_esMateriales) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _precioController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: decoracionCampoHoja('Precio unitario S/', icono: Icons.sell_outlined),
          ),
        ],
        if (!_esProducto)
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              value: _guardarEnLista,
              onChanged: (v) => setState(() => _guardarEnLista = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: BrandColors.cian,
              title: Text(
                _esMateriales ? 'Guardar también en la lista de materiales' : 'Guardar también en la lista de herramientas',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Así aparecerá en los próximos checklists', style: TextStyle(fontSize: 12)),
            ),
          ),
        const SizedBox(height: 10),
        BotonPrincipal(texto: 'AGREGAR', icono: Icons.add, color: BrandColors.cian, onPressed: _guardar),
      ],
    );
  }
}

/// Elegir un ítem de la lista (materiales o herramientas) buscando por nombre.
class _ElegirDeLista extends StatefulWidget {
  final TipoChecklist tipo;

  const _ElegirDeLista({required this.tipo});

  @override
  State<_ElegirDeLista> createState() => _ElegirDeListaState();
}

class _ElegirDeListaState extends State<_ElegirDeLista> {
  List<ItemCatalogoChecklist> _items = [];
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    DbHelper.instance.getItemsCatalogoChecklist(widget.tipo).then((items) {
      if (mounted) setState(() => _items = items);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _busqueda.trim().toLowerCase();
    final lista = _items.where((i) => q.isEmpty || i.nombre.toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: decoracionCampoHoja('Buscar en la lista', icono: Icons.search),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: ListView.builder(
                  itemCount: lista.length,
                  itemBuilder: (context, i) {
                    final item = lista[i];
                    return ListTile(
                      dense: true,
                      title: Text(item.nombre),
                      subtitle: Text(quitarNumeroCategoria(item.categoria)),
                      trailing: item.precio == null ? null : Text(soles(item.precio!)),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
