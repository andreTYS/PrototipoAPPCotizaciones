import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'modo.dart';

/// Error que devuelve el servidor, con el mensaje ya escrito para la persona
/// ("Clave incorrecta", "Otra persona modificó esto...").
class ApiError implements Exception {
  final String mensaje;
  final int codigo;

  const ApiError(this.mensaje, [this.codigo = 0]);

  bool get sesionVencida => codigo == 401;
  bool get conflicto => codigo == 409;

  @override
  String toString() => mensaje;
}

/// Única puerta de la app hacia el servidor: guarda la sesión (token) y el
/// permiso temporal de edición, y habla JSON con la API.
class ApiCliente {
  ApiCliente._();
  static final ApiCliente instancia = ApiCliente._();

  static const _claveToken = 'sesion_token';

  String? _token;

  /// Permiso corto para editar documentos, que da el servidor al escribir
  /// bien la clave de edición.
  String? tokenEdicion;

  /// Se llama cuando el servidor rechaza la sesión (venció o se desactivó el
  /// usuario): la app vuelve a la pantalla de ingreso.
  VoidCallback? alVencerSesion;

  /// Solo para pruebas: la API contra la que se prueba.
  @visibleForTesting
  String? urlParaPruebas;

  /// Dirección de la API: la configurada al armar la app, o (en la web) la
  /// misma dirección de la página, bajo `/api`.
  String get url {
    if (urlParaPruebas != null) return urlParaPruebas!;
    if (urlApiConfigurada.isNotEmpty) return urlApiConfigurada.replaceAll(RegExp(r'/+$'), '');
    return Uri.base.resolve('/api').toString();
  }

  /// La dirección completa de un archivo guardado en el servidor ("/uploads/x.jpg").
  String urlArchivo(String ruta) {
    if (ruta.startsWith('http://') || ruta.startsWith('https://')) return ruta;
    final api = Uri.parse(url);
    return api.replace(path: ruta.startsWith('/') ? ruta : '/$ruta', query: '').toString();
  }

  bool get tieneSesion => _token != null;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_claveToken);
  }

  Future<void> guardarToken(String? token) async {
    _token = token;
    tokenEdicion = null;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_claveToken);
    } else {
      await prefs.setString(_claveToken, token);
    }
  }

  Uri _uri(String ruta, [Map<String, String>? query]) => Uri.parse('$url/$ruta').replace(queryParameters: query);

  Map<String, String> get _cabeceras => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
        if (tokenEdicion != null) 'X-Edicion': tokenEdicion!,
      };

  Future<dynamic> get(String ruta, {Map<String, String>? query}) =>
      _enviar(() => http.get(_uri(ruta, query), headers: _cabeceras));

  Future<dynamic> post(String ruta, [Object? cuerpo]) =>
      _enviar(() => http.post(_uri(ruta), headers: _cabeceras, body: jsonEncode(cuerpo ?? {})));

  Future<dynamic> put(String ruta, Object cuerpo) =>
      _enviar(() => http.put(_uri(ruta), headers: _cabeceras, body: jsonEncode(cuerpo)));

  Future<dynamic> delete(String ruta) => _enviar(() => http.delete(_uri(ruta), headers: _cabeceras));

  /// Sube una foto y devuelve su ruta en el servidor ("/uploads/….jpg").
  Future<String> subirFoto(Uint8List bytes, String extension) async {
    final datos = await _enviar(
      () => http.post(
        _uri('subidas', {'ext': extension}),
        headers: {..._cabeceras, 'Content-Type': 'application/octet-stream'},
        body: bytes,
      ),
    );
    return (datos as Map)['ruta'] as String;
  }

  Future<dynamic> _enviar(Future<http.Response> Function() llamada) async {
    final http.Response respuesta;
    try {
      respuesta = await llamada().timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiError('No hay conexión con el servidor. Revisa tu internet e intenta de nuevo.');
    }

    dynamic datos;
    try {
      datos = respuesta.body.isEmpty ? null : jsonDecode(utf8.decode(respuesta.bodyBytes));
    } catch (_) {
      datos = null;
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) return datos;

    final mensaje = (datos is Map && datos['error'] is String)
        ? datos['error'] as String
        : 'El servidor respondió con un error (${respuesta.statusCode}).';
    if (respuesta.statusCode == 401 && _token != null) {
      await guardarToken(null);
      alVencerSesion?.call();
    }
    throw ApiError(mensaje, respuesta.statusCode);
  }
}
