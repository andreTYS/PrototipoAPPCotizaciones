import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/producto.dart';

/// Única puerta de entrada al ERP real (ICR-LOGISTICA) en toda la app. Se
/// usa para el botón de sincronizar el catálogo y para enviar una
/// cotización armada como Lead al CRM — el resto de pantallas trabajan
/// 100% con la base de datos local (DbHelper).
///
/// Antes esto apuntaba a un servidor Node de demo en la red local
/// (`http://<ip-de-tu-pc>:3000/api/productos/sync`, sin autenticación).
/// Ahora habla directo con la API del ERP en producción, igual que la
/// tienda pública ICR-TIENDA: `baseUrl` es la misma URL de API del ERP
/// (ej. `https://erp.inversionesicr.com/api`) y `token` un token de
/// servicio de larga duración (*Administración → Tokens de servicio*).
class ApiService {
  // El ERP limita cada página a 500 filas como máximo sin importar el
  // page_size pedido (mismo tope que descubrimos en ICR-TIENDA) — con
  // ~830 productos reales hay que pedir varias páginas y juntarlas.
  static Future<List<Producto>> obtenerTodos(String baseUrl, String token) async {
    final crudos = await _paginarTodo(baseUrl, token, '/inventory/products');
    final origen = _origenDe(baseUrl);
    return crudos.map((p) => Producto.fromMap(_adaptarProducto(p, origen))).toList();
  }

  static Future<List<Map<String, dynamic>>> _paginarTodo(
    String baseUrl,
    String token,
    String ruta,
  ) async {
    final items = <Map<String, dynamic>>[];
    const maxPaginas = 50; // ~25.000 filas a 500/página — muy por encima de lo real
    for (var pagina = 1; pagina <= maxPaginas; pagina++) {
      final uri = Uri.parse('$baseUrl$ruta?page=$pagina&page_size=500');
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('Token de servicio inválido o sin permiso (${res.statusCode}).');
      }
      if (res.statusCode != 200) {
        throw Exception('El ERP respondió ${res.statusCode} en $ruta');
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? {};
      final pageItems = (data['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      items.addAll(pageItems);
      final total = (data['total'] as num?)?.toInt() ?? 0;
      if (pageItems.isEmpty || items.length >= total) break;
    }
    return items;
  }

  /// El ERP devuelve imagen_url como ruta relativa ("/uploads/xxx.jpg"),
  /// pensada para servirse desde su propio dominio — se arma la URL
  /// absoluta contra el origen real del ERP (mismo host de baseUrl, sin
  /// el sufijo /api). Mismo criterio que erpImageUrl() en ICR-TIENDA.
  static String _origenDe(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    return '${uri.scheme}://${uri.authority}';
  }

  /// Adapta el producto real del ERP (campos: sku, nombre, marca, modelo,
  /// categoria, precio_venta, costo_unitario, imagen_url) a las claves que
  /// ya espera Producto.fromMap en el resto de la app — así no hay que
  /// tocar el modelo, la base local ni ninguna pantalla.
  static Map<String, dynamic> _adaptarProducto(Map<String, dynamic> p, String origen) {
    final imagenUrl = p['imagen_url'] as String?;
    final imagenAbsoluta = (imagenUrl == null || imagenUrl.isEmpty)
        ? null
        : (imagenUrl.startsWith('http') ? imagenUrl : '$origen$imagenUrl');
    return {
      'id': null, // sin id numérico en el ERP real — SQLite le asigna uno local
      'costo': p['costo_unitario'],
      'nombre': p['nombre'],
      'precio_venta': p['precio_venta'],
      'referencia_interna': p['sku'],
      'unidad_medida': p['unidad_medida'],
      'categoria_producto': p['categoria'] ?? 'SIN CATEGORIA',
      'archivo_imagen': null,
      'imagen_url': imagenAbsoluta,
    };
  }

  /// Envía la cotización que el vendedor acaba de armar como un Lead real
  /// del CRM del ERP (mismo POST /crm/leads que usa ICR-TIENDA) — el
  /// equipo de ventas ve la cotización de campo sin que nadie la
  /// re-escriba a mano. Best-effort: si falla (sin señal, token vencido),
  /// el PDF ya se generó y compartió igual, así que nunca debe bloquear
  /// ese flujo — el llamador decide qué hacer con el error.
  static Future<void> enviarLeadCotizacion({
    required String baseUrl,
    required String token,
    required String cliente,
    required String rucDni,
    required String notas,
  }) async {
    final uri = Uri.parse('$baseUrl/crm/leads');
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'channel': 'api',
            'nombre_contacto': cliente.isEmpty ? 'Cliente de cotización de campo' : cliente,
            'dni': rucDni.isEmpty ? null : rucDni,
            'origen': 'OTRO',
            'notas': notas,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?;
    if (res.statusCode < 200 || res.statusCode >= 300 || body?['status'] != 'success') {
      final mensaje = (body?['error'] as Map<String, dynamic>?)?['message'] as String?;
      throw Exception(mensaje ?? 'El ERP respondió ${res.statusCode}');
    }
  }
}
