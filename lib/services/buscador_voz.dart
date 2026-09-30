import '../models/producto.dart';

/// Un producto identificado a partir de lo dictado por voz, ya resuelto
/// contra el catálogo real (nunca un producto inventado: si ninguna frase
/// calza lo suficiente con algo del catálogo, esa frase simplemente no
/// genera ningún ítem).
class ItemDetectado {
  final Producto producto;
  int cantidad;
  ItemDetectado({required this.producto, required this.cantidad});
}

/// Identifica productos y cantidades a partir de un texto dictado,
/// comparándolo contra el catálogo local — sin ningún servicio externo,
/// así que no depende de internet ni puede fallar por saturación de un
/// servicio de IA. Separa el texto en una frase por producto, saca la
/// cantidad de cada frase si la tiene, y busca el producto del catálogo
/// cuyas palabras coincidan mejor con el resto de la frase.
class BuscadorVoz {
  BuscadorVoz._();

  static const Map<String, int> _numerosEnPalabras = {
    'un': 1, 'una': 1, 'uno': 1,
    'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5,
    'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10,
    'once': 11, 'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15,
    'dieciseis': 16, 'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19,
    'veinte': 20, 'treinta': 30, 'cuarenta': 40, 'cincuenta': 50, 'cien': 100,
  };

  // Muletillas al INICIO de una frase (antes de buscar la cantidad) — para
  // que "necesito dos paneles" reconozca "dos" como cantidad y no "necesito".
  static const Set<String> _rellenoInicial = {
    'necesito', 'necesitamos', 'quiero', 'quisiera', 'dame', 'requiero',
    'porfavor', 'favor', 'tambien', 'ademas', 'y', 'o',
  };

  // Palabras sin valor para buscar en el catálogo (artículos, preposiciones).
  static const Set<String> _relleno = {
    'de', 'del', 'la', 'el', 'los', 'las', 'para', 'con', 'que', 'mas', 'en',
    'por', 'se', 'al', 'un', 'una', 'unos', 'unas', 'o', 'y', 'como',
  };

  static const double _umbralMinimo = 0.6;

  static String _quitarAcentos(String texto) {
    var t = texto.toLowerCase();
    const acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u'};
    acentos.forEach((con, sin) => t = t.replaceAll(con, sin));
    return t;
  }

  static String _limpiarPuntuacion(String texto) {
    final t = texto.replaceAll(RegExp(r'[¿¡.,;:()"“”\-/_]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizarCompleto(String texto) => _limpiarPuntuacion(_quitarAcentos(texto));

  // Separa por coma/punto y coma/"y" ANTES de limpiar puntuación — si se
  // limpiara primero, la coma desaparecería y nunca se podría usar como
  // separador entre productos.
  static List<String> _dividirEnFrases(String texto) {
    return _quitarAcentos(texto)
        .split(RegExp(r'\s*,\s*|\s*;\s*|\s+y\s+'))
        .map(_limpiarPuntuacion)
        .where((f) => f.isNotEmpty)
        .toList();
  }

  /// Separa una frase en (cantidad, palabras de búsqueda). Solo cuenta como
  /// cantidad un número al inicio de la frase (dígito o palabra) — uno más
  /// adelante es parte de la descripción del producto (ej. "sensor de 15
  /// metros" no son 15 sensores).
  static (int, List<String>) _extraerCantidadYTokens(String frase) {
    final palabras = frase.split(' ').where((p) => p.isNotEmpty).toList();
    while (palabras.isNotEmpty && _rellenoInicial.contains(palabras.first)) {
      palabras.removeAt(0);
    }
    if (palabras.isEmpty) return (1, const []);

    var cantidad = 1;
    var inicio = 0;
    final primera = palabras.first;
    final comoDigito = int.tryParse(primera);
    if (comoDigito != null && comoDigito > 0) {
      cantidad = comoDigito;
      inicio = 1;
    } else if (_numerosEnPalabras.containsKey(primera)) {
      cantidad = _numerosEnPalabras[primera]!;
      inicio = 1;
    }

    final tokens = palabras.sublist(inicio).where((p) => !_relleno.contains(p) && p.length > 1).toList();
    return (cantidad, tokens);
  }

  /// Fracción de [tokens] que aparece (como palabra exacta o contenida) en
  /// [palabrasProducto] — así "paneles" calza con "panel" y "100" con "100w".
  static double _puntaje(List<String> tokens, Set<String> palabrasProducto) {
    if (tokens.isEmpty) return 0;
    var coincidencias = 0;
    for (final t in tokens) {
      if (palabrasProducto.any((p) => p == t || p.contains(t) || t.contains(p))) {
        coincidencias++;
      }
    }
    return coincidencias / tokens.length;
  }

  static List<ItemDetectado> buscar({required String texto, required List<Producto> catalogo}) {
    final catalogoNormalizado = [
      for (final p in catalogo)
        if (p.id != null) (p, _normalizarCompleto(p.nombre).split(' ').where((t) => t.length > 1).toSet()),
    ];

    final items = <ItemDetectado>[];
    for (final frase in _dividirEnFrases(texto)) {
      final (cantidad, tokens) = _extraerCantidadYTokens(frase);
      if (tokens.isEmpty) continue;

      Producto? mejor;
      var mejorPuntaje = 0.0;
      for (final (producto, palabras) in catalogoNormalizado) {
        final puntaje = _puntaje(tokens, palabras);
        if (puntaje > mejorPuntaje) {
          mejorPuntaje = puntaje;
          mejor = producto;
        }
      }

      if (mejor != null && mejorPuntaje >= _umbralMinimo) {
        items.add(ItemDetectado(producto: mejor, cantidad: cantidad));
      }
    }
    return items;
  }
}
