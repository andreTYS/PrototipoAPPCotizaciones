import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../state/navegacion_state.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';

/// Pantalla de confirmación al crear un documento de almacén (requerimiento
/// o salida de herramientas): banner de éxito, vista previa embebida del
/// PDF ya creado, y las salidas naturales — compartir el PDF, copiarlo como
/// mensaje, ver su detalle, o volver al inicio.
class DocumentoCreadoScreen extends StatelessWidget {
  final String titulo;
  final String detalle;
  final Uint8List bytes;
  final String nombreArchivo;
  final String textoBotonCompartir;
  final String textoMensaje;
  final String? textoVerDetalle;
  final void Function(BuildContext context)? alVerDetalle;

  const DocumentoCreadoScreen({
    super.key,
    required this.titulo,
    required this.detalle,
    required this.bytes,
    required this.nombreArchivo,
    required this.textoBotonCompartir,
    required this.textoMensaje,
    this.textoVerDetalle,
    this.alVerDetalle,
  });

  Future<void> _compartir() {
    return Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
  }

  Future<void> _copiarMensaje(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: textoMensaje));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado — pégalo donde quieras enviarlo.')),
    );
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
                    Text(titulo, style: AppTextStyles.subtitulo.copyWith(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(
                      detalle,
                      textAlign: TextAlign.center,
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
                        child: Text(textoBotonCompartir,
                            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _copiarMensaje(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          foregroundColor: BrandColors.azulMarino,
                          side: const BorderSide(color: BrandColors.azulMarino),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Copiar como mensaje'),
                      ),
                    ),
                    if (alVerDetalle != null && textoVerDetalle != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => alVerDetalle!(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            foregroundColor: BrandColors.azulMarino,
                            side: const BorderSide(color: BrandColors.azulMarino),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(textoVerDetalle!),
                        ),
                      ),
                    ],
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
