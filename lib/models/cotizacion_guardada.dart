import 'dart:convert';

/// Una línea de producto dentro de una cotización ya guardada — se
/// necesita aparte del total, para poder mostrar el detalle completo
/// (nombre, cantidad, precio) en la pantalla de detalle del historial.
class ItemCotizacionGuardado {
  final String nombre;
  final double cantidad;
  final double precioUnitario;
  final String? archivoImagen;
  final String? unidadMedida;

  ItemCotizacionGuardado({
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
    this.archivoImagen,
    this.unidadMedida,
  });

  double get subtotal => cantidad * precioUnitario;

  factory ItemCotizacionGuardado.fromJson(Map<String, dynamic> json) {
    return ItemCotizacionGuardado(
      nombre: (json['nombre'] ?? '').toString(),
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      precioUnitario: (json['precio_unitario'] as num?)?.toDouble() ?? 0,
      archivoImagen: json['archivo_imagen'] as String?,
      unidadMedida: json['unidad_medida'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
        'archivo_imagen': archivoImagen,
        'unidad_medida': unidadMedida,
      };
}

/// Registro de una cotización ya generada — lo que se muestra en la
/// pestaña "Historial" y en su pantalla de detalle (cliente, vendedor,
/// datos bancarios y el detalle completo de productos).
class CotizacionGuardada {
  final int? id;
  final String numero;
  final String cliente;
  final String? rucDni;
  final String? telefono;
  final String? vendedor;
  final String? banco;
  final String? moneda;
  final String? nroCuenta;
  final String? cci;
  final DateTime fecha;
  final double total;
  final String archivoPdf;
  final List<ItemCotizacionGuardado> items;

  CotizacionGuardada({
    this.id,
    required this.numero,
    required this.cliente,
    this.rucDni,
    this.telefono,
    this.vendedor,
    this.banco,
    this.moneda,
    this.nroCuenta,
    this.cci,
    required this.fecha,
    required this.total,
    required this.archivoPdf,
    this.items = const [],
  });

  factory CotizacionGuardada.fromMap(Map<String, dynamic> map) {
    var items = <ItemCotizacionGuardado>[];
    final itemsRaw = map['items_json'] as String?;
    if (itemsRaw != null && itemsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(itemsRaw) as List<dynamic>;
        items = decoded
            .map((e) => ItemCotizacionGuardado.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        // Registro guardado antes de tener este detalle: se muestra sin él.
      }
    }
    return CotizacionGuardada(
      id: map['id'] as int?,
      numero: (map['numero'] ?? '').toString(),
      cliente: (map['cliente'] ?? '').toString(),
      rucDni: map['ruc_dni'] as String?,
      telefono: map['telefono'] as String?,
      vendedor: map['vendedor'] as String?,
      banco: map['banco'] as String?,
      moneda: map['moneda'] as String?,
      nroCuenta: map['nro_cuenta'] as String?,
      cci: map['cci'] as String?,
      fecha: DateTime.parse(map['fecha'] as String),
      total: (map['total'] as num).toDouble(),
      archivoPdf: (map['archivo_pdf'] ?? '').toString(),
      items: items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'numero': numero,
      'cliente': cliente,
      'ruc_dni': rucDni,
      'telefono': telefono,
      'vendedor': vendedor,
      'banco': banco,
      'moneda': moneda,
      'nro_cuenta': nroCuenta,
      'cci': cci,
      'fecha': fecha.toIso8601String(),
      'total': total,
      'archivo_pdf': archivoPdf,
      'items_json': jsonEncode(items.map((e) => e.toJson()).toList()),
    };
  }
}
