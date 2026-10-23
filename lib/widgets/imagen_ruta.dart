import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../services/api_cliente.dart';

/// Una foto puede estar empaquetada en la app (assets), guardada en el
/// celular (ruta de archivo) o subida al servidor compartido ("/uploads/…",
/// se pide por internet). Estas funciones eligen cómo mostrarla.
Widget imagenDeRuta(
  String ruta, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  String prefijoAsset = '',
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  if (esFotoDeServidor(ruta)) {
    return Image.network(
      ApiCliente.instancia.urlArchivo(ruta),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  if (!kIsWeb && ruta.startsWith('/')) {
    return Image.file(File(ruta), width: width, height: height, fit: fit, errorBuilder: errorBuilder);
  }
  return Image.asset('$prefijoAsset$ruta', width: width, height: height, fit: fit, errorBuilder: errorBuilder);
}
