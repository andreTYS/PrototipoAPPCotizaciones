import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../state/navegacion_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';

/// Pantalla de confirmación al terminar de generar una cotización: banner
/// de éxito, vista previa embebida del PDF ya creado, y las dos salidas
/// naturales — compartirla o volver al inicio.
class CotizacionCreadaScreen extends StatelessWidget {
  final String numero;
  final double total;
  final Uint8List bytes;

  const CotizacionCreadaScreen({
    super.key,
    required this.numero,
    required this.total,
    required this.bytes,
  });

  Future<void> _compartir() {
    return Printing.sharePdf(bytes: bytes, filename: 'cotizacion_$numero.pdf');
  }

  void _volverAlInicio(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    context.read<NavegacionState>().irA(TabsApp.inicio);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: const BoxDecoration(
                  color: BrandColors.cian,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text('Cotización creada', style: AppTextStyles.subtitulo.copyWith(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(
                      '$numero · S/ ${total.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vista previa del PDF',
                        style: TextStyle(fontWeight: FontWeight.bold, color: BrandColors.azulMarino, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: PdfPreview(
                              build: (format) async => bytes,
                              canChangeOrientation: false,
                              canChangePageFormat: false,
                              canDebug: false,
                              useActions: false,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL', style: AppTextStyles.etiqueta),
                          Text(
                            'S/ ${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BrandColors.azulMarino),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _compartir,
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.azulMarino,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'COMPARTIR COTIZACIÓN',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _volverAlInicio(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          foregroundColor: BrandColors.azulMarino,
                          side: const BorderSide(color: BrandColors.azulMarino),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Volver al inicio'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
