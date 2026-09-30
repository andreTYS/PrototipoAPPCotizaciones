import 'package:flutter/material.dart';
import '../theme/brand_colors.dart';
import 'animated_pressable.dart';
import 'pulsing_dot.dart';

/// Estado vacío de una lista (sin registros, o sin resultados para un
/// filtro): ícono con el punto que pulsa, título, explicación y un botón
/// opcional para salir de ahí.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final String? textoBoton;
  final VoidCallback? onBoton;

  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    this.textoBoton,
    this.onBoton,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icono, size: 44, color: BrandColors.azulMarino),
              ),
              const Positioned(
                right: -2,
                bottom: -2,
                child: PulsingDot(color: BrandColors.cian, size: 20),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BrandColors.azulMarino),
        ),
        const SizedBox(height: 8),
        Text(
          subtitulo,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        if (onBoton != null && textoBoton != null) ...[
          const SizedBox(height: 20),
          Center(
            child: AnimatedPressable(
              onTap: onBoton,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                decoration: BoxDecoration(
                  color: BrandColors.cian,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      textoBoton!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
