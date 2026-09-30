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
    String? telefono,
  }) async {
    await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/crm/leads',
      body: {
        'channel': 'api',
        'nombre_contacto': cliente.isEmpty ? 'Cliente de cotización de campo' : cliente,
        'dni': rucDni.isEmpty ? null : rucDni,
        'telefono': (telefono == null || telefono.isEmpty) ? null : telefono,
        'origen': 'OTRO',
        'notas': notas,
      },
    );
  }

  // -------------------- Almacén: reservas y préstamos --------------------
  //
  // Conecta Requerimientos/Checklist de herramientas al inventario real del
  // ERP, solo para los ítems que se agregaron "Del catálogo" (con SKU real
  // — ver ChecklistItemEntry.sku). Mismo criterio best-effort que el resto
  // de esta clase: AlmacenState decide qué hacer si alguna llamada falla,
  // nunca se bloquea el registro local por un problema de red.

  /// Almacenes reales del ERP, para elegir contra cuál se reserva/despacha
  /// (se pide una vez en Conexión con el ERP, ver ErpConfigService).
  static Future<List<Map<String, dynamic>>> listarAlmacenes(String baseUrl, String token) async {
    final uri = Uri.parse('$baseUrl/inventory/warehouses');
    final res = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('El ERP respondió ${res.statusCode} en /inventory/warehouses');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Aparta stock real para un ítem (al aprobar un requerimiento, o al
  /// registrar la salida de una herramienta) — devuelve el id de la reserva.
  static Future<int> reservarStock({
    required String baseUrl,
    required String token,
    required String sku,
    required int cantidad,
    required String warehouseCode,
  }) async {
    final data = await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/inventory/reserve',
      body: {
        'product': {'sku': sku},
        'quantity': cantidad,
        'warehouse_code': warehouseCode,
        'channel': 'api',
      },
    );
    return (data['reserva_id'] as num).toInt();
  }

  /// Libera una reserva sin despacharla — se usa al eliminar un
  /// requerimiento ya aprobado (con stock apartado) antes de entregarse.
  static Future<void> liberarReserva({
    required String baseUrl,
    required String token,
    required int reservaId,
  }) async {
    await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/inventory/release_reservation',
      body: {'reserva_id': reservaId, 'channel': 'api'},
    );
  }

  /// Convierte la reserva en salida real (descuenta stock físico). Si el
  /// producto es retornable, el ERP crea también el préstamo y devuelve su
  /// id; si no, devuelve null (quedó como consumo normal).
  static Future<int?> despacharReserva({
    required String baseUrl,
    required String token,
    required int reservaId,
    required int cantidad,
  }) async {
    final data = await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/inventory/dispatch_reservation',
      body: {'reserva_id': reservaId, 'cantidad': cantidad, 'channel': 'api'},
    );
    return (data['prestamo_id'] as num?)?.toInt();
  }

  /// Cierra un préstamo de herramienta y repone el stock físico — al
  /// confirmar la devolución en el checklist de herramientas.
  static Future<void> devolverPrestamo({
    required String baseUrl,
    required String token,
    required int prestamoId,
  }) async {
    await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/inventory/return_loan',
      body: {'prestamo_id': prestamoId, 'channel': 'api'},
    );
  }

  /// POST genérico contra el ERP: arma el body, valida el sobre estándar
  /// `{status, data, error}` y devuelve `data`, o tira una excepción con el
  /// mensaje real del ERP si algo salió mal.
  static Future<Map<String, dynamic>> _postJson({
    required String baseUrl,
    required String token,
    required String ruta,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$baseUrl$ruta');
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    final parsed = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?;
    if (res.statusCode < 200 || res.statusCode >= 300 || parsed?['status'] != 'success') {
      final mensaje = (parsed?['error'] as Map<String, dynamic>?)?['message'] as String?;
      throw Exception(mensaje ?? 'El ERP respondió ${res.statusCode} en $ruta');
    }
    return Map<String, dynamic>.from(parsed?['data'] as Map? ?? {});
  }
}
