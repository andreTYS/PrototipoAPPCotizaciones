import 'dart:io';
import 'package:flutter/material.dart';
import '../models/producto.dart';

/// Miniatura de producto para las listas de categoría y de cotización.
/// Las fotos van empaquetadas dentro de la propia app (assets/productos/),
/// así que se ven siempre, sin depender de la red ni de haber sincronizado;
/// las de productos agregados desde el celular se leen de su archivo.
class ProductoThumbnail extends StatelessWidget {
  final String? archivoImagen;
  final double size;

  const ProductoThumbnail({super.key, required this.archivoImagen, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: size * 0.5,
        color: Theme.of(context).colorScheme.outline,
      ),
    );

    final archivo = archivoImagen;
    if (archivo == null || archivo.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: esRutaDeArchivo(archivo)
          ? Image.file(
              File(archivo),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => placeholder,
            )
          : Image.asset(
              'assets/productos/$archivo',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => placeholder,
            ),
    );
  }
}
