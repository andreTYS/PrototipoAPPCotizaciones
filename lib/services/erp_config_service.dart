import 'package:shared_preferences/shared_preferences.dart';

/// Dónde vive la configuración de conexión al ERP real (ICR-LOGISTICA):
/// URL base de su API + un token de servicio de larga duración emitido
/// desde *Administración → Tokens de servicio* en el ERP (mismo mecanismo
/// que ya usa la tienda pública ICR-TIENDA). Nunca hay IP/puerto local ni
/// servidor de demo de por medio — esta app habla directo con el ERP real.
class ErpConfigService {
  static const _keyBaseUrl = 'erp_base_url';
  static const _keyToken = 'erp_token';

  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<void> guardar({required String baseUrl, required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    // Sin barra final: api_service.dart arma cada ruta con su propio '/...'.
    await prefs.setString(_keyBaseUrl, baseUrl.trim().replaceAll(RegExp(r'/+$'), ''));
    await prefs.setString(_keyToken, token.trim());
  }

  static Future<bool> estaConfigurado() async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    return (baseUrl != null && baseUrl.isNotEmpty) && (token != null && token.isNotEmpty);
  }
}
