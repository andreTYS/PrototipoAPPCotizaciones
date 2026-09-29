import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotizador_icr/main.dart';

void main() {
  testWidgets('CotizadorApp arranca sin lanzar excepciones', (WidgetTester tester) async {
    // sqflite no tiene implementación de plugin en el entorno de test (VM
    // puro, sin plataforma real) — el splash lo captura y muestra la
    // pantalla de error en vez de trabar la app, así que este smoke test
    // solo verifica que arranca y pinta un Scaffold, sin depender de mockear
    // el plugin nativo.
    await tester.pumpWidget(const CotizadorApp());
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
  });
}
