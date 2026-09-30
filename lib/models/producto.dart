class Producto {
  final int? id;
  final double? costo;
  final String nombre;
  final double? precioVenta;
  final String? referenciaInterna;
  final String? unidadMedida;
  final String categoriaProducto;

  /// Nombre de la foto empaquetada en assets/productos/ — o, para un
  /// producto agregado desde el celular, la ruta absoluta de la foto que se
  /// le tomó (ver [tieneFotoPropia]).
  final String? archivoImagen;
  final String? imagenUrl;

  /// "catalogo" (del catálogo empaquetado o sincronizado) o "local"
  /// (agregado a mano desde la app — solo esos se pueden editar/eliminar).
  final String origen;

  Producto({
    this.id,
    this.costo,
    required this.nombre,
    this.precioVenta,
    this.referenciaInterna,
    this.unidadMedida,
    required this.categoriaProducto,
    this.archivoImagen,
    this.imagenUrl,
    this.origen = 'catalogo',
  });

  bool get esLocal => origen == 'local';

  bool get tieneFotoPropia => esRutaDeArchivo(archivoImagen);

  factory Producto.fromMap(Map<String, dynamic> map) {
    return Producto(
      id: map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}'),
      costo: _toDouble(map['costo']),
      nombre: (map['nombre'] ?? '').toString(),
      precioVenta: _toDouble(map['precio_venta']),
      referenciaInterna: map['referencia_interna'],
      unidadMedida: map['unidad_medida'],
      categoriaProducto: (map['categoria_producto'] ?? 'SIN CATEGORIA').toString(),
      archivoImagen: map['archivo_imagen'],
      imagenUrl: map['imagen_url'],
      origen: (map['origen'] ?? 'catalogo').toString(),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'costo': costo,
      'nombre': nombre,
      'precio_venta': precioVenta,
      'referencia_interna': referenciaInterna,
      'unidad_medida': unidadMedida,
      'categoria_producto': categoriaProducto,
      'archivo_imagen': archivoImagen,
      'imagen_url': imagenUrl,
    };
  }
}

/// Las fotos del catálogo son nombres de archivo dentro de los assets; las
/// que se toman desde el celular se guardan con su ruta absoluta.
bool esRutaDeArchivo(String? archivo) => archivo != null && archivo.startsWith('/');
