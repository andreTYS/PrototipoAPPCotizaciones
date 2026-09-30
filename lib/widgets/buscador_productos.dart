import 'dart:async';
import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../services/db_helper.dart';
import '../theme/brand_colors.dart';
import 'producto_thumbnail.dart';

/// Buscador en hoja modal para elegir un producto del catálogo local sin
/// salir de la pantalla actual — lo usan tanto Cotización (para agregarlo
/// al carrito) como Checklist (para agregar su nombre como ítem de una
/// categoría). Al tocar un resultado, se cierra la hoja devolviendo el
/// [Producto] elegido (o null si se cancela).
class BuscadorProductos extends StatefulWidget {
  final String titulo;

  const BuscadorProductos({super.key, this.titulo = 'Agregar producto'});

  @override
  State<BuscadorProductos> createState() => _BuscadorProductosState();
}

class _BuscadorProductosState extends State<BuscadorProductos> {
  final _controller = TextEditingController();
  List<Producto> _resultados = [];
  bool _buscando = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _buscar(query));
  }

  Future<void> _buscar(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    final resultados = await DbHelper.instance.buscar(query.trim());
    if (!mounted) return;
    setState(() {
      _resultados = resultados;
      _buscando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: BrandColors.azulMarino,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buscando
                  ? const Center(child: CircularProgressIndicator())
                  : _resultados.isEmpty
                      ? ListView(
                          controller: scrollController,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 60),
                              child: Center(
                                child: Text(
                                  _controller.text.trim().isEmpty
                                      ? 'Escribe para buscar en el catálogo.'
                                      : 'No se encontró nada para "${_controller.text}".',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: _resultados.length,
                          itemBuilder: (context, index) {
                            final p = _resultados[index];
                            return ListTile(
                              leading: ProductoThumbnail(archivoImagen: p.archivoImagen),
                              title: Text(
                                p.nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text('S/ ${(p.precioVenta ?? 0).toStringAsFixed(2)}'),
                              trailing: const Icon(Icons.add_circle, color: BrandColors.cian),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
