import 'package:flutter/foundation.dart';

/// Dirección de la API compartida cuando se arma la app con
/// `--dart-define=API_URL=https://api.midominio.com/api` (el APK). En la web
/// no hace falta: la API vive en la misma dirección, bajo `/api`.
const urlApiConfigurada = String.fromEnvironment('API_URL');

/// ¿La app trabaja contra el servidor compartido (varios usuarios, una sola
/// base de datos) o sola, con la base del propio celular?
final bool modoServidor = kIsWeb || urlApiConfigurada.isNotEmpty;
