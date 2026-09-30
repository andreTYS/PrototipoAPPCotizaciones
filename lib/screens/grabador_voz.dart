import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/buscador_voz.dart';
import '../services/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/animated_pressable.dart';
import '../widgets/lottie_gate_screen.dart';

/// Graba un pedido dictado, lo transcribe en el propio celular y busca los
/// productos contra el catálogo local. No decide qué hacer con el
/// resultado — se lo entrega a [onResultado] para que quien la use decida
/// (mostrar la revisión por primera vez, o sumarlo a una que ya estaba en
/// curso). Se usa tanto como la pestaña "Voz" como, empujada encima de
/// RevisionVozScreen, para agregar más productos con el micrófono.
class GrabadorVoz extends StatefulWidget {
  final String subtitulo;
  final ValueChanged<(String, List<ItemDetectado>)> onResultado;

  const GrabadorVoz({super.key, this.subtitulo = 'Dicta tu pedido', required this.onResultado});

  @override
  State<GrabadorVoz> createState() => _GrabadorVozState();
}

class _GrabadorVozState extends State<GrabadorVoz> {
  final _speech = SpeechToText();
  bool _grabando = false;

  // El reconocedor corta la dictada en segmentos cada vez que detecta una
  // pausa, y cada segmento nuevo llega SOLO (no junto con lo ya dicho antes).
  // Por eso se acumulan los resultados ya confirmados aparte del resultado
  // parcial del segmento actual — sin esto, dictar varias frases largas con
  // alguna pausa en el medio terminaba mostrando solo lo último dicho.
  String _textoConfirmado = '';
  String _textoParcial = '';
  Duration _duracion = Duration.zero;
  Timer? _cronometro;
  String? _localeId;

  String get _textoCompleto => [_textoConfirmado, _textoParcial].where((s) => s.isNotEmpty).join(' ');

  @override
  void dispose() {
    _cronometro?.cancel();
    _speech.stop();
    super.dispose();
  }

  Future<String?> _elegirLocaleEspanol() async {
    final locales = await _speech.locales();
    final espanol = locales.where((l) => l.localeId.toLowerCase().startsWith('es')).toList();
    if (espanol.isEmpty) return null;
    final pe = espanol.where((l) => l.localeId.toLowerCase().contains('pe'));
    return (pe.isNotEmpty ? pe.first : espanol.first).localeId;
  }

  Future<void> _alternarGrabacion() async {
    if (_grabando) {
      await _speech.stop();
      _cronometro?.cancel();
      if (!mounted) return;
      setState(() => _grabando = false);
      final texto = _textoCompleto.trim();
      if (texto.isNotEmpty) _procesar(texto);
      return;
    }

    final disponible = await _speech.initialize();
    if (!disponible) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo activar el reconocimiento de voz en este celular (revisa el permiso de micrófono).')),
      );
      return;
    }

    _localeId ??= await _elegirLocaleEspanol();
    if (!mounted) return;

    setState(() {
      _grabando = true;
      _duracion = Duration.zero;
      _textoConfirmado = '';
      _textoParcial = '';
    });
    _cronometro = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duracion += const Duration(seconds: 1));
    });

    await _speech.listen(
      onResult: (resultado) {
        if (!mounted) return;
        setState(() {
          if (resultado.finalResult) {
            if (resultado.recognizedWords.isNotEmpty) {
              _textoConfirmado = [_textoConfirmado, resultado.recognizedWords].where((s) => s.isNotEmpty).join(' ');
            }
            _textoParcial = '';
          } else {
            _textoParcial = resultado.recognizedWords;
          }
        });
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 8),
      ),
    );
  }

  Future<(String, List<ItemDetectado>)> _proceso(String texto) async {
    final agrupado = await DbHelper.instance.getTodosAgrupados();
    final catalogo = agrupado.values.expand((lista) => lista).toList();
    final items = BuscadorVoz.buscar(texto: texto, catalogo: catalogo);
    return (texto, items);
  }

  Future<void> _procesar(String texto) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LottieGateScreen<(String, List<ItemDetectado>)>(
          lottieAsset: 'assets/animations/buscando.lottie',
          mensaje: 'Buscando en el catálogo...',
          proceso: () => _proceso(texto),
          alTerminar: (context, resultado) {
            Navigator.of(context).pop();
            widget.onResultado(resultado);
          },
          alFallar: (context, error) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo procesar el pedido: $error')),
            );
          },
        ),
      ),
    );
  }

  String _formatoDuracion(Duration d) {
    final minutos = d.inMinutes.toString().padLeft(2, '0');
    final segundos = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  @override
  Widget build(BuildContext context) {
    final sePuedeVolver = Navigator.canPop(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: BrandColors.cian,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(sePuedeVolver ? 4 : 20, 12, 20, 24),
                  child: Row(
                    children: [
                      if (sePuedeVolver) ...[
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('COTIZAR POR VOZ', style: AppTextStyles.etiqueta.copyWith(color: Colors.white70)),
                            const SizedBox(height: 4),
                            Text(widget.subtitulo, style: AppTextStyles.titulo.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedPressable(
                        onTap: _alternarGrabacion,
                        borderRadius: BorderRadius.circular(60),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: _grabando ? const Color(0xFFDC2626) : BrandColors.cian,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_grabando ? const Color(0xFFDC2626) : BrandColors.cian).withValues(alpha: 0.3),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            _grabando ? Icons.stop_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _grabando ? _formatoDuracion(_duracion) : 'Toca para grabar',
                        style: _grabando
                            ? const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: BrandColors.azulMarino)
                            : AppTextStyles.subtitulo.copyWith(color: BrandColors.azulMarino),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _grabando
                            ? (_textoCompleto.isEmpty ? 'Escuchando...' : _textoCompleto)
                            : 'Menciona los productos y cantidades que necesitas — luego revisas antes de generar la cotización.',
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.apoyo,
                      ),
                    ],
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
