import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/buscador_voz.dart';
import '../services/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../widgets/animated_pressable.dart';

enum _FaseVoz { grabando, buscando }

/// Hoja modal para agregar más productos por voz SIN salir de la pantalla
/// de revisión: graba y busca todo acá mismo (nunca navega a otra
/// pantalla), mostrando la animación de búsqueda al terminar de grabar.
/// Devuelve (transcripción, items) por Navigator.pop, o null si se cerró
/// sin grabar nada.
class AgregarPorVozModal extends StatefulWidget {
  const AgregarPorVozModal({super.key});

  @override
  State<AgregarPorVozModal> createState() => _AgregarPorVozModalState();
}

class _AgregarPorVozModalState extends State<AgregarPorVozModal> with SingleTickerProviderStateMixin {
  final _speech = SpeechToText();
  _FaseVoz _fase = _FaseVoz.grabando;
  bool _escuchando = false;

  // Ver grabador_voz.dart: el reconocedor corta la dictada en segmentos al
  // detectar una pausa, así que se acumulan los resultados confirmados
  // aparte del resultado parcial del segmento actual.
  String _textoConfirmado = '';
  String _textoParcial = '';
  Duration _duracion = Duration.zero;
  Timer? _cronometro;
  String? _localeId;

  late final AnimationController _controladorLottie = AnimationController(vsync: this);
  bool _animacionLista = false;
  bool _busquedaLista = false;
  (String, List<ItemDetectado>)? _resultado;

  String get _textoCompleto => [_textoConfirmado, _textoParcial].where((s) => s.isNotEmpty).join(' ');

  @override
  void dispose() {
    _cronometro?.cancel();
    _speech.stop();
    _controladorLottie.dispose();
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
    if (_escuchando) {
      await _speech.stop();
      _cronometro?.cancel();
      if (!mounted) return;
      final texto = _textoCompleto.trim();
      if (texto.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _escuchando = false;
        _fase = _FaseVoz.buscando;
      });
      _buscar(texto);
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
      _escuchando = true;
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

  Future<void> _buscar(String texto) async {
    try {
      final agrupado = await DbHelper.instance.getTodosAgrupados();
      final catalogo = agrupado.values.expand((lista) => lista).toList();
      _resultado = (texto, BuscadorVoz.buscar(texto: texto, catalogo: catalogo));
    } catch (_) {
      _resultado = (texto, const <ItemDetectado>[]);
    }
    _busquedaLista = true;
    _revisarSiListo();
  }

  void _alCargarAnimacion(LottieComposition composicion) {
    _controladorLottie.duration = composicion.duration;
    _controladorLottie.forward().whenComplete(() {
      _animacionLista = true;
      _revisarSiListo();
    });
  }

  void _revisarSiListo() {
    if (!_animacionLista || !_busquedaLista || !mounted) return;
    Navigator.of(context).pop(_resultado);
  }

  String _formatoDuracion(Duration d) {
    final minutos = d.inMinutes.toString().padLeft(2, '0');
    final segundos = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _fase == _FaseVoz.grabando,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          child: _fase == _FaseVoz.grabando ? _contenidoGrabando() : _contenidoBuscando(),
        ),
      ),
    );
  }

  Widget _contenidoGrabando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        Text('Agrega más productos', style: AppTextStyles.subtitulo.copyWith(color: BrandColors.azulMarino)),
        const SizedBox(height: 20),
        AnimatedPressable(
          onTap: _alternarGrabacion,
          borderRadius: BorderRadius.circular(50),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: _escuchando ? const Color(0xFFDC2626) : BrandColors.cian,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_escuchando ? const Color(0xFFDC2626) : BrandColors.cian).withValues(alpha: 0.3),
                  blurRadius: 18,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Icon(_escuchando ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 38),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _escuchando ? _formatoDuracion(_duracion) : 'Toca para grabar',
          style: _escuchando
              ? const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BrandColors.azulMarino)
              : AppTextStyles.cuerpo.copyWith(fontWeight: FontWeight.w600, color: BrandColors.azulMarino),
        ),
        const SizedBox(height: 6),
        Text(
          _escuchando ? (_textoCompleto.isEmpty ? 'Escuchando...' : _textoCompleto) : 'Dicta los productos que faltan',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.apoyo,
        ),
      ],
    );
  }

  Widget _contenidoBuscando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Lottie.asset(
          'assets/animations/buscando.lottie',
          controller: _controladorLottie,
          onLoaded: _alCargarAnimacion,
          width: 140,
          height: 140,
        ),
        const SizedBox(height: 12),
        Text('Buscando en el catálogo...', style: AppTextStyles.cuerpo.copyWith(fontWeight: FontWeight.bold, color: BrandColors.azulMarino)),
      ],
    );
  }
}
