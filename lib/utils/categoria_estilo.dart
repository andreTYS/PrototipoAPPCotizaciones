import 'package:flutter/material.dart';
import '../theme/brand_colors.dart';

/// Ícono + color representativo de una categoría, para que se distingan de
/// un vistazo en la lista de Productos. Se decide por palabras clave sobre
/// el nombre real de la categoría (no hay un campo de "tipo" en la base),
/// con un ícono genérico de reserva para lo que no calce con nada.
class CategoriaEstilo {
  final IconData icono;
  final Color color;
  const CategoriaEstilo(this.icono, this.color);
}

CategoriaEstilo estiloDeCategoria(String categoria) {
  final c = categoria.toUpperCase();
  bool tiene(List<String> palabras) => palabras.any((p) => c.contains(p));

  if (tiene(['PANEL', 'INVERSOR', 'CONTROLADOR', 'MICROINVERSOR', 'SMART METER'])) {
    return const CategoriaEstilo(Icons.solar_power, Color(0xFFF59E0B));
  }
  if (tiene(['BATERIA'])) {
    return const CategoriaEstilo(Icons.battery_charging_full, Color(0xFF10B981));
  }
  if (tiene(['CAMARA', 'CAM INALAMBRICA', 'DVR', 'NVR'])) {
    return const CategoriaEstilo(Icons.videocam, BrandColors.azulOscuro);
  }
  if (tiene(['ALARMA', 'INCENDIO'])) {
    return const CategoriaEstilo(Icons.notifications_active, Color(0xFFEF4444));
  }
  if (tiene(['INTERCOMUNICADOR', 'VIDEO PORTERO'])) {
    return const CategoriaEstilo(Icons.doorbell, Color(0xFF8B5CF6));
  }
  if (tiene(['NETWORKING'])) {
    return const CategoriaEstilo(Icons.router, Color(0xFF6366F1));
  }
  if (tiene(['UPS'])) {
    return const CategoriaEstilo(Icons.power, Color(0xFF0EA5E9));
  }
  if (tiene(['BOMBA'])) {
    return const CategoriaEstilo(Icons.water_drop, Color(0xFF0891B2));
  }
  if (tiene(['HDD'])) {
    return const CategoriaEstilo(Icons.storage, Color(0xFF64748B));
  }
  if (tiene([
    'CABLE',
    'MATERIALES',
    'ELECTRICIDAD',
    'TABLERO',
    'ILUMINACION',
    'LUMINARIA',
    'GABINETE',
    'TRANSFORMADOR',
    'POZO TIERRA',
  ])) {
    return const CategoriaEstilo(Icons.cable, Color(0xFFCA8A04));
  }
  if (tiene(['MOVIL'])) {
    return const CategoriaEstilo(Icons.phone_android, Color(0xFF475569));
  }
  if (tiene(['SERVICIOS'])) {
    return const CategoriaEstilo(Icons.miscellaneous_services, Color(0xFF14B8A6));
  }
  if (tiene(['SERCO', 'ACC Y ASIST', 'ESTRUCTURA', 'REVISAR'])) {
    return const CategoriaEstilo(Icons.build, Color(0xFF57534E));
  }
  return const CategoriaEstilo(Icons.inventory_2, BrandColors.azulMarino);
}
