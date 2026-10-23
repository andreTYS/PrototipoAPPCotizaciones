import 'package:flutter/material.dart';

/// Para mostrar un aviso desde cualquier parte (por ejemplo, cuando el
/// servidor dice que otra persona cambió un documento), sin depender de la
/// pantalla que esté abierta.
final mensajeroKey = GlobalKey<ScaffoldMessengerState>();

void avisar(String mensaje) {
  mensajeroKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje), duration: const Duration(seconds: 5)));
}
