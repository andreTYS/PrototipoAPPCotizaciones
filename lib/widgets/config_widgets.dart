import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import 'animated_pressable.dart';

/// Fila de una opción del menú de Configuración (ícono, título, detalle).
class OpcionConfig extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final String? contador;
  final VoidCallback onTap;

  const OpcionConfig({
    super.key,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.color = BrandColors.azulMarino,
    this.contador,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icono, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: AppTextStyles.subtitulo.copyWith(color: BrandColors.azulMarino, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: AppTextStyles.apoyo.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              if (contador != null) ...[
                Text(contador!, style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(width: 4),
              ],
              Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// Título de grupo dentro de Configuración.
class GrupoConfig extends StatelessWidget {
  final String texto;

  const GrupoConfig(this.texto, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
      child: Text(texto, style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino)),
    );
  }
}

/// Pregunta de sí/no antes de borrar algo. Devuelve true si se confirmó.
Future<bool> confirmarBorrado(BuildContext context, {required String titulo, required String texto}) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return confirmar == true;
}

/// Pide una foto (cámara o galería) y la guarda en la carpeta propia de la
/// app — la de la cámara o la galería puede desaparecer en cualquier
/// momento. Devuelve la ruta guardada, o null si se canceló.
Future<String?> elegirFotoGuardada(BuildContext context, {String carpeta = 'fotos_herramientas'}) async {
  final origen = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: BrandColors.cian),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: BrandColors.cian),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (origen == null) return null;
  try {
    final elegida = await ImagePicker().pickImage(source: origen, maxWidth: 1200, imageQuality: 80);
    if (elegida == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final carpetaFotos = Directory('${dir.path}/$carpeta');
    if (!await carpetaFotos.exists()) await carpetaFotos.create(recursive: true);
    final extension = elegida.path.contains('.') ? elegida.path.split('.').last : 'jpg';
    final destino = '${carpetaFotos.path}/foto_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await File(elegida.path).copy(destino);
    return destino;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo obtener la foto: $e')));
    }
    return null;
  }
}

/// Borra una foto guardada por la app (no toca las que vienen empaquetadas).
Future<void> borrarFotoGuardada(String? ruta) async {
  if (ruta == null || !ruta.startsWith('/')) return;
  try {
    final archivo = File(ruta);
    if (await archivo.exists()) await archivo.delete();
  } catch (_) {
    // Si ya no estaba, no pasa nada.
  }
}

/// Pide un número (precio, cantidad) en un cuadro de diálogo. Devuelve el
/// valor, o null si se canceló o no era un número.
Future<double?> pedirNumero(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  double? valorInicial,
  String prefijo = '',
}) async {
  final controller = TextEditingController(text: valorInicial?.toStringAsFixed(2) ?? '');
  final texto = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(prefixText: prefijo, labelText: etiqueta),
        onSubmitted: (v) => Navigator.pop(dialogContext, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Guardar')),
      ],
    ),
  );
  return double.tryParse((texto ?? '').trim().replaceAll(',', '.'));
}
