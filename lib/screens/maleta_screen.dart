import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/datos_almacen.dart';
import '../models/maleta.dart';
import '../services/db_helper.dart';
import '../services/pdf_service.dart';
import '../state/almacen_state.dart';
import '../state/checklist_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../utils/formato.dart';
import '../utils/rutas.dart';
import '../utils/texto_compartir.dart';
import '../widgets/almacen_widgets.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/encabezado_curvo.dart';
import '../widgets/lottie_gate_screen.dart';
import '../widgets/seccion_card.dart';
import 'checklist_screen.dart';
import 'datos_almacen_screen.dart';
import 'documento_creado_screen.dart';
import 'herramientas_detalle_screen.dart';

/// "Nuevo checklist" de herramientas: primero se elige cómo registrar la
/// salida — recorriendo el checklist de herramientas ítem por ítem, o
/// sacando una maleta ya armada completa.
Future<void> nuevaSalidaHerramientas(BuildContext context) async {
  final borrador = context.read<BorradoresChecklist>().de(TipoChecklist.herramientas);
  final continuar = await preguntarContinuarBorrador(context, borrador);
  if (continuar == null || !context.mounted) return;
  if (continuar) {
    // Sigue el checklist que estaba a medias (con sus datos, o pidiéndolos).
    if (borrador.datos == null && (!await pedirDatosChecklist(context, borrador) || !context.mounted)) return;
    await recorrerChecklist(context, borrador);
    return;
  }

  // Lo primero: los datos de la salida. Sin ellos no se elige nada.
  final datos = await Navigator.of(context).push<DatosAlmacen>(
    MaterialPageRoute(builder: (_) => const DatosAlmacenScreen(tipo: TipoChecklist.herramientas)),
  );
  if (datos == null || !context.mounted) return;

  final opcion = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HojaFormaDeSalida(datos: datos),
  );
  if (opcion == null || !context.mounted) return;
  if (opcion == 'checklist') {
    borrador.datos = datos;
    await recorrerChecklist(context, borrador);
    return;
  }

  final List<Maleta> maletas;
  try {
    maletas = await DbHelper.instance.getMaletas();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudieron cargar las maletas: $e')));
    }
    return;
  }
  if (!context.mounted) return;
  if (maletas.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay maletas. Créalas en Inicio › Configuración › Maletas.')),
    );
    return;
  }

  // Con una sola maleta se va directo a su resumen; con varias, se elige.
  final maleta = maletas.length == 1
      ? maletas.first
      : await showModalBottomSheet<Maleta>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _HojaElegirMaleta(maletas: maletas),
        );
  if (maleta == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => MaletaResumenScreen(maleta: maleta, datos: datos)),
  );
}

class _HojaFormaDeSalida extends StatelessWidget {
  final DatosAlmacen datos;

  const _HojaFormaDeSalida({required this.datos});

  @override
  Widget build(BuildContext context) {
    return HojaAlmacen(
      titulo: '¿Cómo registras la salida?',
      texto:
          '${datos.obra} · ${datos.persona}. Elige si vas a marcar las herramientas una por una o si sale una maleta ya armada.',
      children: [
        _OpcionSalida(
          icono: Icons.checklist_rounded,
          color: BrandColors.cian,
          titulo: 'Con checklist de herramientas',
          subtitulo: 'Recorres la lista y marcas lo que sale, con su cantidad',
          onTap: () => Navigator.of(context).pop('checklist'),
        ),
        const SizedBox(height: 10),
        _OpcionSalida(
          icono: Icons.work_outline_rounded,
          color: BrandColors.azulMarino,
          titulo: 'Por maleta',
          subtitulo: 'Sale una maleta armada completa: ves lo que lleva y la registras',
          onTap: () => Navigator.of(context).pop('maleta'),
        ),
      ],
    );
  }
}

class _OpcionSalida extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _OpcionSalida({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icono, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: AppTextStyles.subtitulo.copyWith(color: BrandColors.azulMarino, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(subtitulo, style: AppTextStyles.apoyo.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _HojaElegirMaleta extends StatelessWidget {
  final List<Maleta> maletas;

  const _HojaElegirMaleta({required this.maletas});

  @override
  Widget build(BuildContext context) {
    return HojaAlmacen(
      titulo: '¿Qué maleta sale?',
      texto: 'Cada maleta ya tiene armadas sus herramientas.',
      children: [
        for (final m in maletas) ...[
          _OpcionSalida(
            icono: Icons.work_outline_rounded,
            color: BrandColors.azulMarino,
            titulo: m.nombre,
            subtitulo: cantidadConPalabra(m.totalItems, 'herramienta', 'herramientas'),
            onTap: () => Navigator.of(context).pop(m),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Resumen de una maleta armada antes de registrar su salida: lo que lleva
/// cada nivel con su foto, y los datos de la salida (obra, quién se la
/// lleva). Al registrar queda como cualquier checklist de herramientas
/// (registrado → salida confirmada → pendiente de devolución → conforme).
class MaletaResumenScreen extends StatefulWidget {
  final Maleta maleta;

  /// Los datos que se completaron antes de elegir la maleta.
  final DatosAlmacen datos;

  const MaletaResumenScreen({super.key, required this.maleta, required this.datos});

  @override
  State<MaletaResumenScreen> createState() => _MaletaResumenScreenState();
}

class _MaletaResumenScreenState extends State<MaletaResumenScreen> {
  // Misma clave que el checklist de herramientas: quien se lleva la maleta
  // suele ser el mismo responsable de siempre.
  static const _clavePersona = 'ultimo_responsable_herramientas';

  late final _obraController = TextEditingController(text: widget.datos.obra);
  late final _personaController = TextEditingController(text: widget.datos.persona);
  late final _observacionesController = TextEditingController(text: widget.datos.observaciones);
  bool _guardando = false;

  Maleta get _maleta => widget.maleta;

  @override
  void dispose() {
    _obraController.dispose();
    _personaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  InputDecoration _decoracion(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, size: 20),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Future<void> _registrar() async {
    final obra = _obraController.text.trim();
    final responsable = _personaController.text.trim();
    final observaciones = _observacionesController.text.trim();
    final faltante = obra.isEmpty
        ? 'Escribe la obra o proyecto.'
        : responsable.isEmpty
            ? 'Escribe quién se lleva la maleta.'
            : null;
    if (faltante != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(faltante)));
      return;
    }

    setState(() => _guardando = true);
    final almacen = context.read<AlmacenState>();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clavePersona, responsable);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LottieGateScreen(
          lottieAsset: 'assets/animations/verification.lottie',
          mensaje: 'Registrando...',
          proceso: () async {
            final salida = await almacen.registrarSalida(
              obra: obra,
              responsable: responsable,
              observaciones: observaciones.isEmpty ? null : observaciones,
              categorias: _maleta.comoCategoriasChecklist(),
              maleta: _maleta.nombre,
            );
            final bytes = await PdfService.generarChecklistHerramientas(salida);
            return (salida, bytes);
          },
          alTerminar: (context, resultado) {
            final (salida, bytes) = resultado;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => DocumentoCreadoScreen(
                  titulo: 'Checklist registrado',
                  detalle:
                      '${salida.numero} · ${_maleta.nombre} · ${cantidadConPalabra(salida.totalItems, 'herramienta', 'herramientas')} · falta confirmar la salida',
                  bytes: bytes,
                  nombreArchivo: 'herramientas_${salida.numero}.pdf',
                  textoBotonCompartir: 'COMPARTIR CHECKLIST',
                  textoMensaje: textoHerramientas(salida),
                  textoVerDetalle: 'Ver checklist de herramientas',
                  alVerDetalle: (context) => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => HerramientasDetalleScreen(id: salida.id!)),
                  ),
                ),
              ),
              (ruta) => ruta.isFirst || ruta.settings.name == Rutas.listaHerramientas,
            );
          },
          alFallar: (context, error) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo registrar la salida: $error')),
            );
          },
        ),
      ),
    );
    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoCurvo(
              etiqueta: 'SALIDA POR MALETA',
              titulo: _maleta.nombre,
              conVolver: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  SeccionCard(
                    icono: Icons.work_outline_rounded,
                    color: BrandColors.azulOscuro,
                    titulo: 'Datos de la salida',
                    children: [
                      TextField(
                        controller: _obraController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _decoracion('Obra / proyecto', Icons.home_work_outlined),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _personaController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoracion('Responsable que se la lleva', Icons.person_outline),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _observacionesController,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 1,
                        maxLines: 3,
                        decoration: _decoracion('Observaciones (opcional)', Icons.notes_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      'LO QUE LLEVA LA MALETA · ${cantidadConPalabra(_maleta.totalItems, 'HERRAMIENTA', 'HERRAMIENTAS')}',
                      style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino),
                    ),
                  ),
                  for (final categoria in _maleta.categorias) _NivelMaleta(maleta: _maleta, categoria: categoria),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: BotonInferiorFijo(
          texto: _guardando ? 'REGISTRANDO...' : 'REGISTRAR SALIDA DE LA MALETA',
          icono: Icons.work_outline_rounded,
          onPressed: _guardando ? () {} : _registrar,
        ),
      ),
    );
  }
}

/// Un nivel de la maleta: encabezado con su ícono y cuántas lleva, y cada
/// herramienta con su foto (tocarla la amplía).
class _NivelMaleta extends StatelessWidget {
  final Maleta maleta;
  final CategoriaMaleta categoria;

  const _NivelMaleta({required this.maleta, required this.categoria});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estilo = estiloDeCategoriaChecklist(categoria.nombre);
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
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: estilo.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(estilo.icono, color: estilo.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    categoria.nombre,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: BrandColors.azulMarino),
                  ),
                ),
                Text(
                  cantidadConPalabra(categoria.items.length, 'ítem', 'ítems'),
                  style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          for (final item in categoria.items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
              ),
              child: Row(
                children: [
                  FotoHerramienta(ruta: item.imagen, tamano: 52, titulo: item.nombre),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.nombre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
