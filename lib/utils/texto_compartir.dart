import 'package:intl/intl.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../models/requerimiento.dart';
import 'checklist_estilo.dart';

/// Texto plano listo para copiar y pegar en WhatsApp ("Copiar como
/// mensaje"): los mismos datos del PDF, sin necesidad de adjuntar archivo.

final _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

String textoRequerimiento(Requerimiento r) {
  final buffer = StringBuffer()
    ..writeln('📋 REQUERIMIENTO ${r.numero} — Inversiones ICR')
    ..writeln('Obra: ${r.obra}')
    ..writeln('Solicitante: ${r.solicitante}')
    ..writeln('Fecha: ${_formatoFecha.format(r.fechaCreacion)}')
    ..writeln('Estado: ${r.estado.etiqueta}');
  if (r.urgente) buffer.writeln('⚠️ URGENTE');
  if (r.fechaAprobacion != null) {
    final quien = (r.aprobadoPor ?? '').trim();
    buffer.writeln('Aprobado: ${_formatoFecha.format(r.fechaAprobacion!)}${quien.isEmpty ? '' : ' por $quien'}');
  }
  if (r.fechaEntrega != null) {
    final quien = (r.recibidoPor ?? '').trim();
    buffer.writeln('Entregado: ${_formatoFecha.format(r.fechaEntrega!)}${quien.isEmpty ? '' : ' a $quien'}');
  }
  _escribirCategorias(buffer, r.categorias);
  _escribirObservaciones(buffer, 'Observaciones', r.observaciones);
  return buffer.toString().trim();
}

String textoHerramientas(ChecklistHerramientas h) {
  final buffer = StringBuffer()
    ..writeln('🧰 SALIDA DE HERRAMIENTAS ${h.numero} — Inversiones ICR')
    ..writeln('Obra: ${h.obra}')
    ..writeln('Responsable: ${h.responsable}')
    ..writeln('Salida: ${_formatoFecha.format(h.fechaSalida)}')
    ..writeln('Estado: ${h.estado.etiqueta}');
  if (h.fechaDevolucion != null) {
    final quien = (h.encargado ?? '').trim();
    buffer.writeln('Devuelto: ${_formatoFecha.format(h.fechaDevolucion!)}${quien.isEmpty ? '' : ' · recibió $quien'}');
  }
  _escribirCategorias(buffer, h.categorias);
  _escribirObservaciones(buffer, 'Observaciones', h.observaciones);
  _escribirObservaciones(buffer, 'Observaciones de la devolución', h.observacionesDevolucion);
  return buffer.toString().trim();
}

void _escribirCategorias(StringBuffer buffer, List<ChecklistCategoriaState> categorias) {
  for (final cat in categorias) {
    buffer
      ..writeln()
      ..writeln('${quitarNumeroCategoria(cat.nombre)} (${cat.items.length})');
    for (final item in cat.items) {
      buffer.writeln('• ${item.texto} ${item.cantidadTexto}');
    }
  }
}

void _escribirObservaciones(StringBuffer buffer, String titulo, String? texto) {
  final limpio = (texto ?? '').trim();
  if (limpio.isEmpty) return;
  buffer
    ..writeln()
    ..writeln('$titulo: $limpio');
}
