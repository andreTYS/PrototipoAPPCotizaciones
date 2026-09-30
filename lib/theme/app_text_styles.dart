import 'package:flutter/material.dart';
import 'brand_colors.dart';

/// Escala de texto única de la app — todas las pantallas deberían tomar
/// sus tamaños/pesos de acá en vez de inventar uno nuevo cada vez, para
/// que no se vea distinto de una pestaña a otra.
class AppTextStyles {
  AppTextStyles._();

  static const titulo = TextStyle(fontSize: 24, fontWeight: FontWeight.w800);
  static const subtitulo = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
  static const cuerpo = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const apoyo = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: BrandColors.grisApoyo);
  static const etiqueta = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.6,
    color: BrandColors.grisApoyo,
  );
}
