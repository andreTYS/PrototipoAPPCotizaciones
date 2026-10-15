import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/requerimiento.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/encabezado_curvo.dart';

/// Lo que devuelve el alistado: las categorías con cada material marcado
/// (quién lo alistó y cuándo).
class ResultadoAlistado {
  final List<ChecklistCategoriaState> categorias;

  const ResultadoAlistado(this.categorias);
}

/// Alistar un requerimiento aprobado material por material: se marca lo que
/// ya se preparó y se guarda el avance. Otra persona puede abrirlo después y
/// seguir donde se quedó: lo ya alistado aparece marcado, con quién lo hizo,
/// y solo faltan los demás. Al marcar todo, el requerimiento pasa a "listo
/// para entrega".
class AlistarRequerimientoScreen extends StatefulWidget {
  final Requerimiento requerimiento;

  const AlistarRequerimientoScreen({super.key, required this.requerimiento});

  @override
  State<AlistarRequerimientoScreen> createState() => _AlistarRequerimientoScreenState();
}

class _AlistarRequerimientoScreenState extends State<AlistarRequerimientoScreen> {
  static const _clavePersona = 'ultimo_almacenero';
  static final _formatoFecha = DateFormat('dd/MM · HH:mm');

  /// Copia de trabajo: los cambios se aplican solo al guardar.
  late final List<ChecklistCategoriaState> _categorias = soloMarcados(categoriasDesdeJson(widget.requerimiento.categoriasJson));

  /// Quién y cuándo alistó cada uno antes de abrir esta pantalla.
  late final Map<ChecklistItemEntry, bool> _yaAlistado = {
    for (final i in _items) i: i.alistado == true,
  };

  final _nombreController = TextEditingController();
  bool _intentoGuardar = false;

  Iterable<ChecklistItemEntry> get _items => _categorias.expand((c) => c.items);
  int get _total => _items.length;
  int get _alistados => _items.where((i) => i.alistado == true).length;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted && _nombreController.text.isEmpty) {
        setState(() => _nombreController.text = prefs.getString(_clavePersona) ?? '');
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  void _poner(ChecklistItemEntry i, bool valor) => setState(() => i.alistado = valor);

  void _marcarTodos(bool valor) => setState(() {
        for (final i in _items) {
          i.alistado = valor;
        }
      });

  String? get _errorNombre =>
      _intentoGuardar && _nombreController.text.trim().isEmpty ? 'El nombre es obligatorio' : null;

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _intentoGuardar = true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clavePersona, nombre);
    final ahora = DateTime.now();
    for (final i in _items) {
      final antes = _yaAlistado[i] ?? false;
      final ahoraMarcado = i.alistado == true;
      if (ahoraMarcado && !antes) {
        // Lo marcó quien guarda ahora.
        i.alistadoPor = nombre;
        i.fechaAlistado = ahora;
      } else if (!ahoraMarcado) {
        i.alistado = false;
        i.alistadoPor = null;
        i.fechaAlistado = null;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(ResultadoAlistado(_categorias));
  }

  String _detalleAlistado(ChecklistItemEntry i) {
    final quien = (i.alistadoPor ?? '').trim();
    final cuando = i.fechaAlistado == null ? '' : _formatoFecha.format(i.fechaAlistado!);
    return 'Alistado${quien.isEmpty ? '' : ' por $quien'}${cuando.isEmpty ? '' : ' · $cuando'}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.requerimiento;
    final colorScheme = Theme.of(context).colorScheme;
    final faltan = _total - _alistados;
    final todo = faltan == 0;
    final yaHabiaAvance = r.totalAlistados > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: '${r.numero} · ${r.obra}',
              titulo: 'Alistar materiales',
              conVolver: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text(
                      yaHabiaAvance
                          ? 'Ya hay materiales alistados por otra persona. Marca los que faltan y guarda: el avance queda para quien siga.'
                          : 'Marca cada material que ya preparaste y guarda. Si no alcanzas a terminar, otra persona puede continuar después.',
                      style: AppTextStyles.apoyo.copyWith(fontSize: 13, height: 1.4),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: todo ? ColoresEstado.listoFondo : ColoresEstado.pendienteFondo,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              todo ? Icons.check_circle : Icons.inventory_2_outlined,
                              size: 20,
                              color: todo ? ColoresEstado.listo : ColoresEstado.pendiente,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$_alistados de $_total alistados',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _marcarTodos(!todo),
                              child: Text(todo ? 'Quitar marcas' : 'Marcar todos'),
                            ),
                          ],
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _total == 0 ? 0 : _alistados / _total,
                            minHeight: 6,
                            backgroundColor: Colors.white,
                            color: todo ? ColoresEstado.listo : ColoresEstado.pendiente,
                          ),
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
                                  '${categoria.items.where((i) => i.alistado == true).length} / ${categoria.items.length}',
                                  style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          for (final item in categoria.items)
                            InkWell(
                              onTap: () => _poner(item, item.alistado != true),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.texto,
                                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                          ),
                                          if (item.alistado == true && (_yaAlistado[item] ?? false))
                                            Text(_detalleAlistado(item), style: AppTextStyles.apoyo)
                                          else if (item.agregadoDespues)
                                            const Text('Agregado después', style: AppTextStyles.apoyo),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      item.cantidadTexto,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: BrandColors.cian,
                                      ),
                                    ),
                                    Checkbox(
                                      value: item.alistado == true,
                                      activeColor: ColoresEstado.preparado,
                                      onChanged: (v) => _poner(item, v ?? false),
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
                    decoration: decoracionCampoHoja('Alistado por (almacenero) *', icono: Icons.person_outline)
                        .copyWith(errorText: _errorNombre),
                  ),
                  if (todo)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: Text(
                        'Al guardar, el requerimiento pasa a "Listo para entrega".',
                        style: AppTextStyles.apoyo,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: todo ? 'GUARDAR · TODO ALISTADO' : 'GUARDAR AVANCE · $_alistados DE $_total',
          icono: todo ? Icons.inventory_2_outlined : Icons.save_outlined,
          onPressed: _guardar,
        ),
      ),
    );
  }
}
