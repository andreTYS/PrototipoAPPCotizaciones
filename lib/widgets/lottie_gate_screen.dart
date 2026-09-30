import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme/brand_colors.dart';

/// Pantalla de una animación Lottie que corre en paralelo con [proceso] —
/// solo se llama a [alTerminar]/[alFallar] cuando TERMINAN LAS DOS COSAS
/// (lo que tarde más manda): la animación siempre se ve completa, de
/// principio a fin, nunca se corta a la mitad ni se salta aunque el
/// proceso real termine antes.
class LottieGateScreen<T> extends StatefulWidget {
  final String lottieAsset;
  final String mensaje;
  final Future<T> Function() proceso;
  final void Function(BuildContext context, T resultado) alTerminar;
  final void Function(BuildContext context, Object error)? alFallar;
  final bool bloquearAtras;

  const LottieGateScreen({
    super.key,
    required this.lottieAsset,
    required this.mensaje,
    required this.proceso,
    required this.alTerminar,
    this.alFallar,
    this.bloquearAtras = true,
  });

  @override
  State<LottieGateScreen<T>> createState() => _LottieGateScreenState<T>();
}

class _LottieGateScreenState<T> extends State<LottieGateScreen<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _animacionTerminada = false;
  bool _procesoTerminado = false;
  T? _resultado;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _correrProceso();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _correrProceso() async {
    try {
      _resultado = await widget.proceso();
    } catch (e) {
      _error = e;
    }
    _procesoTerminado = true;
    _revisarSiListo();
  }

  void _alCargarAnimacion(LottieComposition composicion) {
    _controller.duration = composicion.duration;
    _controller.forward().whenComplete(() {
      _animacionTerminada = true;
      _revisarSiListo();
    });
  }

  void _revisarSiListo() {
    if (!_animacionTerminada || !_procesoTerminado || !mounted) return;
    final error = _error;
    if (error != null) {
      if (widget.alFallar != null) {
        widget.alFallar!(context, error);
      } else {
        Navigator.of(context).pop();
      }
    } else {
      widget.alTerminar(context, _resultado as T);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.bloquearAtras,
      child: Scaffold(
        backgroundColor: BrandColors.azulMarino,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                widget.lottieAsset,
                controller: _controller,
                onLoaded: _alCargarAnimacion,
                width: 240,
                height: 240,
              ),
              const SizedBox(height: 20),
              Text(
                widget.mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
