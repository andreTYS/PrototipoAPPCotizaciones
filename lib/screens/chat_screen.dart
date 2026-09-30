import 'package:flutter/material.dart';
import 'grabador_voz.dart';
import 'revision_voz_screen.dart';

/// Pestaña "Voz": arma una cotización dictando el pedido. El propio
/// celular transcribe la voz (sin mandar audio a ningún servicio) y ese
/// texto se busca contra el catálogo local para identificar qué productos
/// se pidieron y cuántos; antes de generar nada se pasa por
/// RevisionVozScreen para confirmar o corregir.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GrabadorVoz(
      onResultado: (resultado) {
        final (transcripcion, items) = resultado;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RevisionVozScreen(transcripcion: transcripcion, items: items)),
        );
      },
    );
  }
}
