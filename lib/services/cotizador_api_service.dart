import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/checklist_categoria.dart';
import '../models/requerimiento.dart';

/// Aplana las categorías armadas en pantalla (agrupadas, como las guarda
/// categoriasAJson) al arreglo plano de items que espera
/// POST /requerimientos.php — cada material lleva su propia 'categoria'.
List<Map<String, dynamic>> itemsRequerimientoParaApi(List<ChecklistCategoriaState> categorias) {
  return [
    for (final c in categorias)
      for (final i in c.items)
        {
          'categoria': c.nombre,
          'nombre': i.texto,
          'cantidad': i.cantidad,
          'unidad': i.unidad,
          'precio_unitario': i.precio,
          'es_extra': i.esExtra,
          'es_producto': i.esProducto,
        },
  ];
}

/// Habla con el backend PHP+MySQL compartido del Cotizador (Hostinger) —
/// una sola base central para requerimientos/checklists, distinta del ERP
/// (ese sigue siendo ApiService, para reservar/despachar stock). Sobre
/// estándar `{status: 'ok'|'error', data, error}`, igual estructura que ya
/// usa el ERP pero con su propio valor de 'ok' en vez de 'success'.
class CotizadorApiService {
  /// POST /login.php — valida contra el ERP real y, si el ERP dice que sí,
  /// devuelve la sesión del backend compartido (token + usuario + rol).
  static Future<Map<String, dynamic>> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    return _postJson(
      baseUrl: baseUrl,
      token: null,
      ruta: '/login.php',
      body: {'email': email, 'password': password},
    );
  }

  static Future<List<Requerimiento>> listarRequerimientos({
    required String baseUrl,
    required String token,
    String? estado,
  }) async {
    final ruta = estado == null ? '/requerimientos.php' : '/requerimientos.php?estado=$estado';
    final data = await _getJson(baseUrl: baseUrl, token: token, ruta: ruta);
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((e) => Requerimiento.fromApiMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return items;
  }

  static Future<Requerimiento> detalleRequerimiento({
    required String baseUrl,
    required String token,
    required String codigo,
  }) async {
    final data = await _getJson(baseUrl: baseUrl, token: token, ruta: '/requerimientos.php?codigo=$codigo');
    return Requerimiento.fromApiMap(data);
  }

  /// Crea el requerimiento (cualquier empleado). [items] va plano, uno por
  /// material marcado — cada uno con su categoría — tal como lo arma
  /// categoriasAJson aplanado, nunca el JSON agrupado que usa la pantalla.
  static Future<Requerimiento> crearRequerimiento({
    required String baseUrl,
    required String token,
    required String obra,
    required String solicitante,
    required bool urgente,
    String? observaciones,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/requerimientos.php',
      body: {
        'obra': obra,
        'solicitante': solicitante,
        'urgente': urgente,
        'observaciones': observaciones,
        'items': items,
      },
    );
    return Requerimiento.fromApiMap(data);
  }

  static Future<Requerimiento> aprobarRequerimiento({
    required String baseUrl,
    required String token,
    required String codigo,
    required int version,
  }) async {
    final data = await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/requerimientos.php?accion=aprobar&codigo=$codigo',
      body: {'version': version},
    );
    return Requerimiento.fromApiMap(data);
  }

  /// Marca un material individual como alistado — se puede ir llamando de
  /// a uno, para que varios almaceneros avancen el mismo requerimiento a la
  /// vez sin pisarse (no lleva "version": cada ítem se actualiza aparte).
  static Future<Requerimiento> alistarItem({
    required String baseUrl,
    required String token,
    required String codigo,
    required int itemId,
  }) async {
    final data = await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/requerimientos.php?accion=alistar_item&codigo=$codigo&item_id=$itemId',
      body: const {},
    );
    return Requerimiento.fromApiMap(data);
  }

  static Future<Requerimiento> marcarListo({
    required String baseUrl,
    required String token,
    required String codigo,
    required int version,
  }) async {
    final data = await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/requerimientos.php?accion=listo&codigo=$codigo',
      body: {'version': version},
    );
    return Requerimiento.fromApiMap(data);
  }

  static Future<Requerimiento> entregarRequerimiento({
    required String baseUrl,
    required String token,
    required String codigo,
    required int version,
  }) async {
    final data = await _postJson(
      baseUrl: baseUrl,
      token: token,
      ruta: '/requerimientos.php?accion=entregar&codigo=$codigo',
      body: {'version': version},
    );
    return Requerimiento.fromApiMap(data);
  }

  /// GET/POST genérico contra el backend compartido: arma el body, valida
  /// el sobre `{status, data, error}` y devuelve `data`, o tira una
  /// excepción con el mensaje real del backend (código incluido para que
  /// el llamador pueda distinguir, por ejemplo, un 409 CONFLICTO_VERSION).
  static Future<Map<String, dynamic>> _getJson({
    required String baseUrl,
    required String token,
    required String ruta,
  }) async {
    final uri = Uri.parse('$baseUrl$ruta');
    final res = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20));
    return _procesar(res, ruta);
  }

  static Future<Map<String, dynamic>> _postJson({
    required String baseUrl,
    required String ruta,
    required Map<String, dynamic> body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$ruta');
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _procesar(res, ruta);
  }

  static Map<String, dynamic> _procesar(http.Response res, String ruta) {
    final parsed = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?;
    if (res.statusCode < 200 || res.statusCode >= 300 || parsed?['status'] != 'ok') {
      final error = parsed?['error'] as Map<String, dynamic>?;
      final mensaje = error?['message'] as String?;
      final codigo = error?['code'] as String?;
      throw CotizadorApiException(
        codigo ?? 'ERROR',
        mensaje ?? 'El servidor respondió ${res.statusCode} en $ruta',
      );
    }
    return Map<String, dynamic>.from(parsed?['data'] as Map? ?? {});
  }
}

/// Error del backend compartido con su código real (ej. CONFLICTO_VERSION,
/// ITEMS_PENDIENTES, AUTH_INVALID) — para que la pantalla pueda reaccionar
/// distinto a un conflicto de versión (recargar y avisar) que a cualquier
/// otro error (solo mostrarlo).
class CotizadorApiException implements Exception {
  final String codigo;
  final String mensaje;
  CotizadorApiException(this.codigo, this.mensaje);

  @override
  String toString() => mensaje;
}
