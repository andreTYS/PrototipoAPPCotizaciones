import 'package:flutter/material.dart';
import '../theme/brand_colors.dart';
import 'categoria_estilo.dart';

/// Ícono + color por cada una de las categorías del checklist de obra
/// (Conduit, Fotovoltaico, Eléctrico, Techo y Herramientas). Se decide por
/// el nombre y no por la posición: requerimientos y herramientas usan
/// partes distintas del Excel, y se pueden agregar categorías nuevas.
CategoriaEstilo estiloDeCategoriaChecklist(String nombre) {
  final c = quitarNumeroCategoria(nombre).toUpperCase();
  if (c.contains('CONDUIT')) return const CategoriaEstilo(Icons.plumbing, Color(0xFF475569));
  if (c.contains('FOTOVOLTAIC')) return const CategoriaEstilo(Icons.solar_power, Color(0xFFF59E0B));
  if (c.contains('ELÉCTRIC') || c.contains('ELECTRIC')) {
    return const CategoriaEstilo(Icons.electrical_services, Color(0xFFCA8A04));
  }
  if (c.contains('TECHO')) return const CategoriaEstilo(Icons.roofing, Color(0xFFB45309));
  if (c.contains('HERRAMIENTA')) return const CategoriaEstilo(Icons.build_outlined, Color(0xFF57534E));
  return const CategoriaEstilo(Icons.checklist, BrandColors.azulMarino);
}

/// Quita el "N. " del inicio del nombre de categoría (que viene así del
/// Excel) para mostrarlo más limpio en pantalla — el número de categoría
/// ya se ve aparte, en la barra de progreso.
String quitarNumeroCategoria(String nombre) => nombre.replaceFirst(RegExp(r'^\d+\.\s*'), '');
