import 'package:flutter/material.dart';

/// Número de porcentaje que, al cambiar de valor, cuenta animado desde el
/// anterior hasta el nuevo (1, 2, 3… hasta llegar) en vez de saltar directo
/// — lo usan tanto la pantalla por categoría del checklist (donde se nota
/// al pasar de un paso al siguiente) como su resumen final.
class PorcentajeAnimado extends StatelessWidget {
  final int valor;
  const PorcentajeAnimado({super.key, required this.valor});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: valor.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Text(
        '${value.round()}%',
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }
}
