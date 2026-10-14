import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../utils/formato.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';

/// Qué se está revisando herramienta por herramienta.
enum ModoRevision { salida, devolucion }

/// Lo que devuelve la revisión: quién la hizo, sus observaciones y las
/// categorías con cada herramienta ya marcada (salio / volvio).
class ResultadoRevision {
  final String nombre;
  final String observaciones;
  final List<ChecklistCategoriaState> categorias;

  const ResultadoRevision({required this.nombre, required this.observaciones, required this.categorias});
}

/// Confirmar la salida o la devolución de las herramientas marcando cada
/// una (como las columnas SALIDA y ENTRADA del formato en papel). Las que
/// no se marcan quedan anotadas: no salieron, o no volvieron. El nombre de
/// quien confirma es obligatorio, y al devolver con faltantes también el
/// motivo en las observaciones.
class RevisionHerramientasScreen extends StatefulWidget {
  final ChecklistHerramientas checklist;
  final ModoRevision modo;

  const RevisionHerramientasScreen({super.key, required this.checklist, required this.modo});

  @override
  State<RevisionHerramientasScreen> createState() => _RevisionHerramientasScreenState();
}

class _RevisionHerramientasScreenState extends State<RevisionHerramientasScreen> {
  /// Copia de trabajo: las marcas se aplican al confirmar, no antes.
  late final List<ChecklistCategoriaState> _categorias = _copiaDeTrabajo();
  final _nombreController = TextEditingController();
  final _observacionesController = TextEditingController();
  bool _intentoConfirmar = false;

  bool get _esSalida => widget.modo == ModoRevision.salida;

  String get _clavePersona => _esSalida ? 'ultimo_almacenero' : 'ultimo_encargado_almacen';

  List<ChecklistCategoriaState> _copiaDeTrabajo() {
    final copia = soloMarcados(categoriasDesdeJson(widget.checklist.categoriasJson));
    // Las de una devolución son solo las que salieron; todas parten sin marcar.
    for (final c in copia) {
      for (final i in c.items) {
        if (i.salio == null && widget.checklist.estado != EstadoHerramientas.registrado) i.salio = true;
      }
    }
    if (_esSalida) return copia;
    return [
      for (final c in copia)
        if (c.items.any((i) => i.salio != false))
          ChecklistCategoriaState(nombre: c.nombre, items: c.items.where((i) => i.salio != false).toList()),
    ];
  }

  /// Marcado en esta revisión (salida: salio; devolución: volvio).
  bool _marcado(ChecklistItemEntry i) => (_esSalida ? i.salio : i.volvio) == true;

  void _poner(ChecklistItemEntry i, bool valor) {
    if (_esSalida) {
      i.salio = valor;
    } else {
      i.volvio = valor;
    }
  }

  Iterable<ChecklistItemEntry> get _items => _categorias.expand((c) => c.items);
  int get _total => _items.length;
  int get _marcados => _items.where(_marcado).length;
  int get _faltantes => _total - _marcados;

  @override
  void initState() {
    super.initState();
    // Lo que no se marque queda como "no salió" / "no volvió": se parte de
    // "sin marcar" para que cada herramienta se revise de verdad.
    for (final i in _items) {
      _poner(i, false);
    }
    SharedPreferences.getInstance().then((prefs) {
      if (mounted && _nombreController.text.isEmpty) {
        setState(() => _nombreController.text = prefs.getString(_clavePersona) ?? '');
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _marcarTodas(bool valor) => setState(() {
        for (final i in _items) {
          _poner(i, valor);
        }
      });

  String? get _errorNombre =>
      _intentoConfirmar && _nombreController.text.trim().isEmpty ? 'El nombre es obligatorio' : null;

  bool get _faltaMotivo => !_esSalida && _faltantes > 0 && _observacionesController.text.trim().isEmpty;

  String? get _errorObservaciones => _intentoConfirmar && _faltaMotivo
      ? 'Explica por qué no volvieron ${cantidadConPalabra(_faltantes, 'herramienta', 'herramientas')}'
      : null;

  Future<void> _confirmar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty || _faltaMotivo || (_esSalida && _marcados == 0)) {
      setState(() => _intentoConfirmar = true);
      if (_esSalida && _marcados == 0 && nombre.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marca al menos una herramienta que salió.')),
        );
      }
      return;
    }
    final observaciones = _observacionesController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clavePersona, nombre);
    if (!mounted) return;
    Navigator.of(context).pop(ResultadoRevision(nombre: nombre, observaciones: observaciones, categorias: _resultado()));
  }

  /// Todas las categorías originales (también las herramientas que no
  /// entraron en la devolución) con las marcas hechas aquí.
  List<ChecklistCategoriaState> _resultado() {
    if (_esSalida) return _categorias;
    final original = soloMarcados(categoriasDesdeJson(widget.checklist.categoriasJson));
    final marcas = {
      for (final c in _categorias)
        for (final i in c.items) '${c.nombre}|${i.texto}': i.volvio,
    };
    for (final c in original) {
      for (final i in c.items) {
        if (i.salio == null && widget.checklist.estado != EstadoHerramientas.registrado) i.salio = true;
        final clave = '${c.nombre}|${i.texto}';
        if (marcas.containsKey(clave)) i.volvio = marcas[clave];
      }
    }
    return original;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.checklist;
    final colorScheme = Theme.of(context).colorScheme;
    final color = _esSalida ? ColoresEstado.pendiente : ColoresEstado.listo;
    final faltantes = _faltantes;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: '${h.numero}${h.maleta == null ? '' : ' · ${h.maleta}'}',
              titulo: _esSalida ? 'Confirmar salida' : 'Confirmar devolución',
              conVolver: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text(
                      _esSalida
                          ? 'Marca cada herramienta que sale a obra con ${h.responsable}. Las que no marques quedan anotadas como "no salió".'
                          : 'Marca cada herramienta que volvió. Las que no marques quedan anotadas como "no volvió".',
                      style: AppTextStyles.apoyo.copyWith(fontSize: 13, height: 1.4),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: faltantes == 0 ? ColoresEstado.listoFondo : ColoresEstado.pendienteFondo,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          faltantes == 0 ? Icons.check_circle : Icons.pending_actions_outlined,
                          size: 20,
                          color: faltantes == 0 ? ColoresEstado.listo : ColoresEstado.pendiente,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$_marcados de $_total marcadas',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _marcarTodas(faltantes != 0),
                          child: Text(faltantes != 0 ? 'Marcar todas' : 'Quitar marcas'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final categoria in _categorias)
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
                                Expanded(
                                  child: Text(
                                    quitarNumeroCategoria(categoria.nombre),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: BrandColors.azulMarino,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${categoria.items.where(_marcado).length} / ${categoria.items.length}',
                                  style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          for (final item in categoria.items)
                            InkWell(
                              onTap: () => setState(() => _poner(item, !_marcado(item))),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    FotoHerramienta(ruta: item.imagen, titulo: item.texto, tamano: 44),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item.texto,
                                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Checkbox(
                                      value: _marcado(item),
                                      activeColor: color,
                                      onChanged: (v) => setState(() => _poner(item, v ?? false)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _nombreController,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: decoracionCampoHoja(
                      _esSalida ? 'Entregado por (almacén) *' : 'Encargado que recibe *',
                      icono: Icons.person_outline,
                    ).copyWith(errorText: _errorNombre),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _observacionesController,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: decoracionCampoHoja(
                      !_esSalida && faltantes > 0 ? 'Observaciones (obligatorio) *' : 'Observaciones (opcional)',
                      icono: Icons.notes_outlined,
                    ).copyWith(errorText: _errorObservaciones),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: _esSalida
              ? 'CONFIRMAR SALIDA · $_marcados DE $_total'
              : (faltantes == 0 ? 'CONFIRMAR DEVOLUCIÓN' : 'DEVOLVER CON $faltantes FALTANTE${faltantes == 1 ? '' : 'S'}'),
          icono: _esSalida ? Icons.outbox_outlined : Icons.assignment_return_outlined,
          onPressed: _confirmar,
        ),
      ),
    );
  }
}
