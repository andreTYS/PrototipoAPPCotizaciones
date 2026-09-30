import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import 'animated_pressable.dart';

/// Encabezado de color con la parte de abajo redondeada — el mismo de
/// Cotizar, Historial o Checklist: etiqueta chica arriba, título grande,
/// acciones a la derecha y, opcionalmente, algo debajo (buscador, filtros).
class EncabezadoCurvo extends StatelessWidget {
  final String etiqueta;
  final String titulo;
  final Color color;
  final bool conVolver;
  final List<Widget> acciones;
  final Widget? abajo;

  const EncabezadoCurvo({
    super.key,
    required this.etiqueta,
    required this.titulo,
    this.color = BrandColors.azulMarino,
    this.conVolver = false,
    this.acciones = const [],
    this.abajo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(conVolver ? 4 : 20, conVolver ? 4 : 12, acciones.isEmpty ? 20 : 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (conVolver) ...[
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(etiqueta, style: AppTextStyles.etiqueta.copyWith(color: Colors.white70)),
                        const SizedBox(height: 4),
                        Text(titulo, style: AppTextStyles.titulo.copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                  ...acciones,
                ],
              ),
              if (abajo != null) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: EdgeInsets.only(left: conVolver ? 16 : 0, right: acciones.isEmpty ? 0 : 12),
                  child: abajo,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Buscador translúcido sobre el encabezado de color.
class BuscadorEncabezado extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const BuscadorEncabezado({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white54),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Colors.white54),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Píldora de filtro sobre el encabezado de color: la activa se rellena de
/// cian; con [onClear] muestra una "x" para quitar ese filtro.
class PildoraFiltro extends StatelessWidget {
  final String texto;
  final bool activo;
  final IconData? icono;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const PildoraFiltro({
    super.key,
    required this.texto,
    required this.activo,
    required this.onTap,
    this.icono,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: activo ? BrandColors.cian : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 14, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              texto,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
