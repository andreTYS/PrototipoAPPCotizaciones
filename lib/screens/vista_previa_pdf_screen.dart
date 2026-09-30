import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../theme/brand_colors.dart';

/// Previsualización de un PDF con el visor propio del paquete printing
/// (zoom, cambiar de página, e imprimir/compartir desde ahí mismo). Sirve
/// para cualquier documento: una cotización ya guardada (que se lee de su
/// archivo) o un requerimiento/checklist (que se arma en el momento con su
/// estado actual, para que el PDF nunca quede desactualizado).
class VistaPreviaPdfScreen extends StatelessWidget {
  final String titulo;
  final String nombreArchivo;
  final Future<Uint8List> Function() generar;

  const VistaPreviaPdfScreen({
    super.key,
    required this.titulo,
    required this.nombreArchivo,
    required this.generar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BrandColors.azulMarino,
        foregroundColor: Colors.white,
        title: Text(titulo),
      ),
      body: PdfPreview(
        build: (format) => generar(),
        pdfFileName: nombreArchivo,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}
