import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/checklist_categoria.dart';
import '../models/maleta.dart';
import '../services/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/formato.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/config_widgets.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/estado_vacio.dart';

/// Configuración › Maletas: las maletas armadas que se pueden elegir al
/// registrar una salida de herramientas. Se crean, se abren para cambiar
/// sus herramientas y fotos, y se eliminan.
class ConfigMaletasScreen extends StatefulWidget {
  const ConfigMaletasScreen({super.key});

  @override
  State<ConfigMaletasScreen> createState() => _ConfigMaletasScreenState();
}

class _ConfigMaletasScreenState extends State<ConfigMaletasScreen> {
  List<Maleta> _maletas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final maletas = await DbHelper.instance.getMaletas();
    if (!mounted) return;
    setState(() {
      _maletas = maletas;
      _cargando = false;
    });
  }

  Future<void> _nueva() async {
    final nombre = await pedirTexto(context, titulo: 'Nueva maleta', etiqueta: 'Nombre de la maleta', texto: '');
    if (nombre == null || !mounted) return;
    final id = await DbHelper.instance.crearMaleta(nombre);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MaletaEditorScreen(maletaId: id)));
    _cargar();
  }

  Future<void> _eliminar(Maleta m) async {
    final confirmar = await confirmarBorrado(
      context,
      titulo: '¿Eliminar la maleta?',
      texto: '"${m.nombre}" con sus ${cantidadConPalabra(m.totalItems, 'herramienta', 'herramientas')} ya no se podrá elegir. '
          'Las salidas ya registradas no cambian.',
    );
    if (!confirmar) return;
    for (final c in m.categorias) {
      for (final i in c.items) {
        await borrarFotoGuardada(i.imagen);
      }
    }
    await DbHelper.instance.eliminarMaleta(m.id!);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            const EncabezadoCurvo(etiqueta: 'CONFIGURACIÓN', titulo: 'Maletas', conVolver: true),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _maletas.isEmpty
                      ? const EstadoVacio(
                          icono: Icons.work_outline_rounded,
                          titulo: 'Aún no hay maletas',
                          subtitulo: 'Crea una maleta y agrégale sus herramientas, cada una con su foto.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          children: [
                            for (final m in _maletas)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: colorScheme.outlineVariant),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => MaletaEditorScreen(maletaId: m.id!)),
                                      );
                                      _cargar();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: BrandColors.azulMarino.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.work_outline_rounded, color: BrandColors.azulMarino),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  m.nombre,
                                                  style: AppTextStyles.subtitulo
                                                      .copyWith(color: BrandColors.azulMarino, fontSize: 14.5),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${cantidadConPalabra(m.totalItems, 'herramienta', 'herramientas')} · '
                                                  '${cantidadConPalabra(m.categorias.length, 'nivel', 'niveles')}',
                                                  style: AppTextStyles.apoyo,
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete_outline, color: colorScheme.outline),
                                            tooltip: 'Eliminar maleta',
                                            onPressed: () => _eliminar(m),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(texto: 'NUEVA MALETA', icono: Icons.add, onPressed: _nueva),
      ),
    );
  }
}

/// Pide un nombre en un cuadro de diálogo; devuelve el texto (no vacío) o
/// null si se canceló.
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  required String texto,
}) async {
  final controller = TextEditingController(text: texto);
  final resultado = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: etiqueta),
        onSubmitted: (v) => Navigator.pop(dialogContext, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Guardar')),
      ],
    ),
  );
  final limpio = (resultado ?? '').trim();
  return limpio.isEmpty ? null : limpio;
}

/// Una maleta abierta para configurarla: cambiarle el nombre, agregar,
/// cambiar o quitar herramientas (con su foto y su nivel), cambiar el
/// nombre de un nivel, o eliminarla.
class MaletaEditorScreen extends StatefulWidget {
  final int maletaId;

  const MaletaEditorScreen({super.key, required this.maletaId});

  @override
  State<MaletaEditorScreen> createState() => _MaletaEditorScreenState();
}

class _MaletaEditorScreenState extends State<MaletaEditorScreen> {
  Maleta? _maleta;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final maletas = await DbHelper.instance.getMaletas();
    if (!mounted) return;
    final encontrada = maletas.where((m) => m.id == widget.maletaId);
    if (encontrada.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _maleta = encontrada.first);
  }

  Future<void> _renombrar() async {
    final nombre = await pedirTexto(context, titulo: 'Nombre de la maleta', etiqueta: 'Nombre', texto: _maleta!.nombre);
    if (nombre == null) return;
    await DbHelper.instance.renombrarMaleta(widget.maletaId, nombre);
    _cargar();
  }

  Future<void> _eliminarMaleta() async {
    final m = _maleta!;
    final confirmar = await confirmarBorrado(
      context,
      titulo: '¿Eliminar la maleta?',
      texto: '"${m.nombre}" con sus ${cantidadConPalabra(m.totalItems, 'herramienta', 'herramientas')} ya no se podrá elegir. '
          'Las salidas ya registradas no cambian.',
    );
    if (!confirmar) return;
    for (final c in m.categorias) {
      for (final i in c.items) {
        await borrarFotoGuardada(i.imagen);
      }
    }
    await DbHelper.instance.eliminarMaleta(widget.maletaId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _renombrarNivel(String nivel) async {
    final nuevo = await pedirTexto(context, titulo: 'Nombre del nivel', etiqueta: 'Nivel', texto: nivel);
    if (nuevo == null || nuevo == nivel) return;
    await DbHelper.instance.renombrarNivelMaleta(widget.maletaId, nivel, nuevo);
    _cargar();
  }

  Future<void> _formulario([ItemMaleta? item, String? nivelInicial]) async {
    final resultado = await showModalBottomSheet<_DatosHerramienta>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioHerramienta(
        niveles: [for (final c in _maleta!.categorias) c.nombre],
        item: item,
        nivelInicial: nivelInicial,
      ),
    );
    if (resultado == null) return;
    if (item == null) {
      await DbHelper.instance.agregarItemMaleta(
        widget.maletaId,
        nivel: resultado.nivel,
        nombre: resultado.nombre,
        imagen: resultado.imagen,
      );
    } else {
      await DbHelper.instance.actualizarItemMaleta(
        item.id!,
        nivel: resultado.nivel,
        nombre: resultado.nombre,
        imagen: resultado.imagen,
      );
      if (item.imagen != resultado.imagen) await borrarFotoGuardada(item.imagen);
    }
    _cargar();
  }

  Future<void> _eliminarItem(ItemMaleta item) async {
    final confirmar = await confirmarBorrado(
      context,
      titulo: '¿Quitar de la maleta?',
      texto: '"${item.nombre}" ya no saldrá en esta maleta. Las salidas ya registradas no cambian.',
    );
    if (!confirmar) return;
    await DbHelper.instance.eliminarItemMaleta(item.id!);
    await borrarFotoGuardada(item.imagen);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final maleta = _maleta;
    final colorScheme = Theme.of(context).colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'CONFIGURAR MALETA',
              titulo: maleta?.nombre ?? '',
              conVolver: true,
              acciones: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: 'Cambiar nombre',
                  onPressed: maleta == null ? null : _renombrar,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Eliminar maleta',
                  onPressed: maleta == null ? null : _eliminarMaleta,
                ),
              ],
            ),
            Expanded(
              child: maleta == null
                  ? const Center(child: CircularProgressIndicator())
                  : maleta.categorias.isEmpty
                      ? const EstadoVacio(
                          icono: Icons.handyman_outlined,
                          titulo: 'Esta maleta está vacía',
                          subtitulo: 'Agrega las herramientas que lleva, cada una con su nivel y su foto.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 10),
                              child: Text(
                                '${cantidadConPalabra(maleta.totalItems, 'HERRAMIENTA', 'HERRAMIENTAS')} · TOCA UNA PARA CAMBIARLA',
                                style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino),
                              ),
                            ),
                            for (final nivel in maleta.categorias)
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
                                      padding: const EdgeInsets.fromLTRB(14, 8, 4, 6),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.layers_outlined, size: 18, color: BrandColors.cian),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              nivel.nombre,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: BrandColors.azulMarino,
                                              ),
                                            ),
                                          ),
                                          Text('${nivel.items.length}',
                                              style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w800)),
                                          IconButton(
                                            icon: Icon(Icons.edit_outlined, size: 18, color: colorScheme.outline),
                                            tooltip: 'Cambiar nombre del nivel',
                                            onPressed: () => _renombrarNivel(nivel.nombre),
                                          ),
                                        ],
                                      ),
                                    ),
                                    for (final item in nivel.items)
                                      InkWell(
                                        onTap: () => _formulario(item, nivel.nombre),
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              FotoHerramienta(ruta: item.imagen, titulo: item.nombre, tamano: 48),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(item.nombre,
                                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.outline),
                                                tooltip: 'Quitar de la maleta',
                                                onPressed: () => _eliminarItem(item),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: 'AGREGAR HERRAMIENTA',
          icono: Icons.add,
          onPressed: maleta == null ? () {} : () => _formulario(),
        ),
      ),
    );
  }
}

class _DatosHerramienta {
  final String nombre;
  final String nivel;
  final String? imagen;

  const _DatosHerramienta({required this.nombre, required this.nivel, this.imagen});
}

/// Alta o cambio de una herramienta de la maleta: nombre, nivel (uno
/// existente o uno nuevo) y foto (cámara o galería).
class _FormularioHerramienta extends StatefulWidget {
  final List<String> niveles;
  final ItemMaleta? item;
  final String? nivelInicial;

  const _FormularioHerramienta({required this.niveles, this.item, this.nivelInicial});

  @override
  State<_FormularioHerramienta> createState() => _FormularioHerramientaState();
}

class _FormularioHerramientaState extends State<_FormularioHerramienta> {
  static const _nuevo = '__nuevo__';

  late final _nombreController = TextEditingController(text: widget.item?.nombre ?? '');
  final _nivelNuevoController = TextEditingController();
  late String? _nivel = _nivelInicial();
  late String? _imagen = widget.item?.imagen;
  bool _intento = false;

  String? _nivelInicial() => widget.nivelInicial ?? (widget.niveles.isEmpty ? _nuevo : null);

  @override
  void dispose() {
    _nombreController.dispose();
    _nivelNuevoController.dispose();
    super.dispose();
  }

  String? get _nivelEfectivo {
    if (_nivel == _nuevo) {
      final t = _nivelNuevoController.text.trim();
      return t.isEmpty ? null : t;
    }
    return _nivel;
  }

  Future<void> _foto() async {
    final ruta = await elegirFotoGuardada(context, carpeta: 'fotos_maletas');
    if (ruta == null || !mounted) return;
    // La foto nueva reemplaza a la anterior que se hubiera elegido en este mismo formulario.
    if (_imagen != widget.item?.imagen) await borrarFotoGuardada(_imagen);
    setState(() => _imagen = ruta);
  }

  Future<void> _cancelar() async {
    if (_imagen != widget.item?.imagen) await borrarFotoGuardada(_imagen);
    if (mounted) Navigator.pop(context);
  }

  void _guardar() {
    final nombre = _nombreController.text.trim();
    final nivel = _nivelEfectivo;
    if (nombre.isEmpty || nivel == null) {
      setState(() => _intento = true);
      return;
    }
    Navigator.pop(context, _DatosHerramienta(nombre: capitalizarPrimeraLetra(nombre), nivel: nivel, imagen: _imagen));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && result == null && _imagen != widget.item?.imagen) await borrarFotoGuardada(_imagen);
      },
      child: HojaAlmacen(
        titulo: widget.item == null ? 'Nueva herramienta' : 'Cambiar herramienta',
        texto: 'Se usa en las próximas salidas de esta maleta.',
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _foto,
                child: FotoHerramienta(ruta: _imagen, titulo: _nombreController.text, tamano: 76),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _foto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(_imagen == null ? 'Agregar foto' : 'Cambiar foto'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BrandColors.azulMarino,
                        side: const BorderSide(color: BrandColors.cian),
                      ),
                    ),
                    if (_imagen != null)
                      TextButton(
                        onPressed: () async {
                          if (_imagen != widget.item?.imagen) await borrarFotoGuardada(_imagen);
                          setState(() => _imagen = null);
                        },
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        child: const Text('Quitar foto'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nombreController,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: decoracionCampoHoja('Nombre *', icono: Icons.handyman_outlined)
                .copyWith(errorText: _intento && _nombreController.text.trim().isEmpty ? 'Escribe el nombre' : null),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _nivel,
            isExpanded: true,
            decoration: decoracionCampoHoja('Nivel *', icono: Icons.layers_outlined)
                .copyWith(errorText: _intento && _nivelEfectivo == null ? 'Elige o escribe un nivel' : null),
            items: [
              for (final n in widget.niveles) DropdownMenuItem(value: n, child: Text(n)),
              const DropdownMenuItem(value: _nuevo, child: Text('Otro nivel nuevo…')),
            ],
            onChanged: (v) => setState(() => _nivel = v),
          ),
          if (_nivel == _nuevo) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _nivelNuevoController,
              textCapitalization: TextCapitalization.sentences,
              decoration: decoracionCampoHoja('Nombre del nivel nuevo', icono: Icons.add_circle_outline),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelar,
                  style: estiloBotonSecundario,
                  child: const Text('Cancelar'),
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
        ],
      ),
    );
  }
}
