import 'package:flutter_test/flutter_test.dart';
import 'package:cotizador_icr/models/producto.dart';
import 'package:cotizador_icr/services/buscador_voz.dart';

void main() {
  final catalogo = [
    Producto(id: 1, nombre: 'Panel Solar 550W Trina', categoriaProducto: 'PANELES'),
    Producto(id: 2, nombre: 'Bateria Litio 12V 100AH', categoriaProducto: 'BATERIAS'),
  ];

  test('identifica varios productos separados por coma, con cantidad en número y en palabra', () {
    final items = BuscadorVoz.buscar(texto: 'dos paneles solares, una bateria de litio', catalogo: catalogo);

    expect(items, hasLength(2));
    expect(items[0].producto.id, 1);
    expect(items[0].cantidad, 2);
    expect(items[1].producto.id, 2);
    expect(items[1].cantidad, 1);
  });

  test('lee la cantidad como dígito al inicio de la frase', () {
    final items = BuscadorVoz.buscar(texto: '3 paneles solares', catalogo: catalogo);

    expect(items, hasLength(1));
    expect(items[0].producto.id, 1);
    expect(items[0].cantidad, 3);
  });

  test('sin cantidad explícita, asume 1', () {
    final items = BuscadorVoz.buscar(texto: 'bateria de litio', catalogo: catalogo);

    expect(items, hasLength(1));
    expect(items[0].cantidad, 1);
  });

  test('un número que no está al inicio de la frase es parte de la descripción, no la cantidad', () {
    // "sensor de 15 metros" no son 15 sensores — ver el comentario de
    // _extraerCantidadYTokens. Ninguno del catálogo de prueba calza con
    // esto, así que no debería generar ningún ítem (nunca inventa uno).
    final items = BuscadorVoz.buscar(texto: 'cable de 15 metros', catalogo: catalogo);

    expect(items, isEmpty);
  });

  test('una frase que no calza lo suficiente con nada del catálogo no genera ningún ítem', () {
    final items = BuscadorVoz.buscar(texto: 'necesito cable de red', catalogo: catalogo);

    expect(items, isEmpty);
  });

  test('ignora muletillas al inicio de la frase ("necesito", "quiero", etc.)', () {
    final items = BuscadorVoz.buscar(texto: 'necesito dos paneles solares', catalogo: catalogo);

    expect(items, hasLength(1));
    expect(items[0].cantidad, 2);
    expect(items[0].producto.id, 1);
  });

  test('es insensible a mayúsculas y acentos', () {
    final items = BuscadorVoz.buscar(texto: 'DOS PANELES SOLARES', catalogo: catalogo);

    expect(items, hasLength(1));
    expect(items[0].producto.id, 1);
  });

  test('con el catálogo vacío nunca inventa un producto', () {
    final items = BuscadorVoz.buscar(texto: 'dos paneles solares', catalogo: const []);

    expect(items, isEmpty);
  });
}
