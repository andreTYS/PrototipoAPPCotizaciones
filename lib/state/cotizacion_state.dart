import 'package:flutter/foundation.dart';
import '../models/producto.dart';

class ItemCotizacion {
  final Producto producto;
  int cantidad;
  ItemCotizacion({required this.producto, this.cantidad = 1});

  double get subtotal => (producto.precioVenta ?? 0) * cantidad;
}

/// Carrito de la cotización, compartido entre la pantalla de categorías
/// (donde marcas productos) y la pantalla de cotización (donde revisas y
/// generas el PDF).
class CotizacionState extends ChangeNotifier {
  final Map<int, ItemCotizacion> _items = {};

  List<ItemCotizacion> get items => _items.values.toList();

  int get totalItems => _items.values.fold(0, (sum, i) => sum + i.cantidad);

  double get totalGeneral =>
      _items.values.fold(0.0, (sum, i) => sum + i.subtotal);

  bool estaEnCotizacion(Producto p) => _items.containsKey(_key(p));

  int cantidadDe(Producto p) => _items[_key(p)]?.cantidad ?? 0;

  int _key(Producto p) => p.id ?? p.nombre.hashCode;

  void toggle(Producto p) {
    final key = _key(p);
    if (_items.containsKey(key)) {
      _items.remove(key);
    } else {
      _items[key] = ItemCotizacion(producto: p);
    }
    notifyListeners();
  }

  /// A diferencia de [toggle], nunca quita: si ya estaba en la cotización le
  /// suma una unidad más. Lo usa el buscador de "Agregar producto" desde la
  /// pantalla de Cotización.
  void agregarUno(Producto p) {
    final key = _key(p);
    if (_items.containsKey(key)) {
      _items[key]!.cantidad += 1;
    } else {
      _items[key] = ItemCotizacion(producto: p);
    }
    notifyListeners();
  }

  void quitar(Producto p) {
    _items.remove(_key(p));
    notifyListeners();
  }

  void setCantidad(Producto p, int cantidad) {
    final key = _key(p);
    if (cantidad <= 0) {
      _items.remove(key);
    } else if (_items.containsKey(key)) {
      _items[key]!.cantidad = cantidad;
    } else {
      _items[key] = ItemCotizacion(producto: p, cantidad: cantidad);
    }
    notifyListeners();
  }

  void limpiar() {
    _items.clear();
    notifyListeners();
  }
}
