import 'package:flutter/material.dart';
import '../theme/brand_colors.dart';

/// Tarjeta redondeada con un ícono de cabecera — el mismo lenguaje visual
/// en Cotización y en el resumen del Checklist, para que las pantallas se
/// sientan parte de la misma app.
class SeccionCard extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final List<Widget> children;

  const SeccionCard({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: BrandColors.azulMarino,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
