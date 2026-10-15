import 'package:shared_preferences/shared_preferences.dart';

/// Sesión del usuario contra el backend compartido del Cotizador (PHP +
/// MySQL en Hostinger) — distinto de ErpConfigService, que es el token de
/// servicio fijo con el que la app habla con el ERP para reservar/despachar
/// stock. Acá se guarda la sesión *personal* de quien está usando el
/// celular ahora mismo: su token, su nombre y su rol, para saber qué
/// botones mostrarle sin tener que volver a preguntarle al servidor cada
/// vez (el servidor igual revalida el rol en cada acción, esto es solo
/// para la UI).
class SesionService {
  static const _keyApiUrl = 'cotizador_api_url';
  static const _keyToken = 'cotizador_token';
  static const _keyUsuarioId = 'cotizador_usuario_id';
  static const _keyUsuarioNombre = 'cotizador_usuario_nombre';
  static const _keyUsuarioRol = 'cotizador_usuario_rol';

  static Future<String?> getApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiUrl);
  }

  /// La URL base de la API (ej. https://tudominio.com/cotizador-api) se fija
  /// una sola vez por despliegue — no cambia por usuario, así que se guarda
  /// aparte y sobrevive a un cierre de sesión.
  static Future<void> guardarApiUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiUrl, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<Map<String, dynamic>?> getUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_keyUsuarioId);
    final nombre = prefs.getString(_keyUsuarioNombre);
    final rol = prefs.getString(_keyUsuarioRol);
    if (id == null || nombre == null || rol == null) return null;
    return {'id': id, 'nombre': nombre, 'rol': rol};
  }

  static Future<void> guardarSesion({
    required String token,
    required int usuarioId,
    required String nombre,
    required String rol,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setInt(_keyUsuarioId, usuarioId);
    await prefs.setString(_keyUsuarioNombre, nombre);
    await prefs.setString(_keyUsuarioRol, rol);
  }

  /// Cierra la sesión personal — la URL de la API queda igual, para no
  /// tener que volver a configurarla cada vez que alguien cambia de turno
  /// en el mismo celular.
  static Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUsuarioId);
    await prefs.remove(_keyUsuarioNombre);
    await prefs.remove(_keyUsuarioRol);
  }

  static Future<bool> haySesion() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
