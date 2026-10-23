import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_cliente.dart';
import '../services/db_helper.dart';

/// El formato de la imagen, mirando sus primeros bytes (en la web el nombre
/// del archivo no siempre trae la extensión).
String extensionDeImagen(Uint8List bytes) {
  if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47) return 'png';
  if (bytes.length > 4 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) return 'webp';
  return 'jpg';
}

/// Guarda la foto elegida y devuelve la ruta para guardar en la base: con
/// servidor la sube ("/uploads/….jpg", la ven todos); sin servidor la copia
/// a la carpeta propia de la app — la de la cámara o la galería puede
/// desaparecer en cualquier momento.
Future<String> guardarFotoElegida(XFile elegida, {required String carpeta, required String prefijo}) async {
  if (DbHelper.instance.esServidor) {
    final bytes = await elegida.readAsBytes();
    return ApiCliente.instancia.subirFoto(bytes, extensionDeImagen(bytes));
  }
  final dir = await getApplicationDocumentsDirectory();
  final carpetaFotos = Directory('${dir.path}/$carpeta');
  if (!await carpetaFotos.exists()) await carpetaFotos.create(recursive: true);
  final extension = elegida.path.contains('.') ? elegida.path.split('.').last : 'jpg';
  final destino = '${carpetaFotos.path}/${prefijo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
  await File(elegida.path).copy(destino);
  return destino;
}
