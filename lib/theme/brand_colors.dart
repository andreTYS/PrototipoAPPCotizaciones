import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

/// Paleta de marca de Inversiones ICR — un solo lugar para los 5 tonos
/// oficiales, usados tanto en la UI (Material) como en la cotización en
/// PDF (paquete pdf, que tiene su propio tipo de color). Se mantienen los
/// mismos 4 nombres históricos (azulMarino/azulOscuro/cian/menta) para no
/// tener que tocar cada pantalla que ya los usa — lo que cambió es el
/// valor hex de cada uno, no su rol dentro del diseño.
class BrandColors {
  BrandColors._();

  static const Color azulMarino = Color(0xFF0D2233);
  static const Color azulOscuro = Color(0xFF124C8C);
  static const Color cian = Color(0xFF0E7490);
  static const Color menta = Color(0xFF12A3B8);
  static const Color celeste = Color(0xFFD8F3F4);
  static const Color grisApoyo = Color(0xFF64748B);

  static final PdfColor pdfAzulMarino = PdfColor.fromHex('0D2233');
  static final PdfColor pdfAzulOscuro = PdfColor.fromHex('124C8C');
  static final PdfColor pdfCian = PdfColor.fromHex('0E7490');
  static final PdfColor pdfMenta = PdfColor.fromHex('12A3B8');

  /// Mezcla [color] hacia blanco en la proporción [amount] (0 = sin cambio,
  /// 1 = blanco puro). Se usa para el sombreado alterno de filas de la tabla.
  static PdfColor pdfTint(PdfColor color, double amount) {
    return PdfColor(
      color.red + (1 - color.red) * amount,
      color.green + (1 - color.green) * amount,
      color.blue + (1 - color.blue) * amount,
    );
  }
}
