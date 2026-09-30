import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../models/producto.dart';
import '../models/requerimiento.dart';
import '../state/cotizacion_state.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';

const _firmaAsset = 'assets/fonts/DancingScript-Bold.ttf';

const _logoAsset = 'assets/icon/icon.png';

/// Genera los PDFs con el formato oficial de Inversiones ICR. La cotización:
/// encabezado con logo/RUC/Nro, fila de cliente (+ RUC/DNI opcional) /
/// total/fecha, vendedor/email, tabla de productos, y el bloque de
/// Banco/Moneda/Cuenta/CCI + Subtotal/Impuestos/Total al final. Los
/// documentos de almacén (requerimiento, checklist de herramientas) usan el
/// mismo encabezado de marca, las secciones por categoría del checklist y
/// firmas al pie.
class PdfService {
  static const _empresa = 'INVERSIONES ICR S.R.L.';
  static const _direccion = 'Calle Pizarro 325 C, Arequipa';
  static const _ruc = '20605309489';
  static const _email = 'inversionesicr@hotmail.com';

  // Los precios del catálogo son con IGV incluido (18%, Perú); el Subtotal
  // del pie es ese total sin el IGV, igual que en las cotizaciones reales.
  static const _igv = 0.18;

  /// Se pide UNA vez, antes de generar, para que quien llama pueda usar el
  /// mismo número tanto en el PDF como al guardar el registro en el
  /// historial (mismo nombre de archivo, mismo "Nro").
  static Future<int> siguienteNumero() async {
    final prefs = await SharedPreferences.getInstance();
    final siguiente = (prefs.getInt('cotizacion_correlativo') ?? 0) + 1;
    await prefs.setInt('cotizacion_correlativo', siguiente);
    return siguiente;
  }

  static String formatearNumero(int numero) => 'S${numero.toString().padLeft(5, '0')}';

  static Future<Uint8List> generar({
    required int numero,
    required List<ItemCotizacion> items,
    String cliente = '',
    String rucDni = '',
    String telefono = '',
    String vendedor = '',
    String banco = '',
    String moneda = '',
    String nroCuenta = '',
    String cci = '',
  }) async {
    final imagenes = await _cargarImagenes(items);
    final logo = pw.MemoryImage(
      (await rootBundle.load(_logoAsset)).buffer.asUint8List(),
    );

    // locale 'en_US' solo para el agrupado de miles/decimales (1,234.56);
    // el símbolo "S/ " es el de la cotización real de Inversiones ICR.
    final formatoMoneda = NumberFormat.currency(locale: 'en_US', symbol: 'S/ ');
    final fecha = DateFormat('dd/MM/yyyy').format(DateTime.now());

    final totalBruto = items.fold<double>(0, (s, i) => s + i.subtotal);
    final subtotalNeto = totalBruto / (1 + _igv);
    final impuestos = totalBruto - subtotalNeto;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _encabezado(
          context: context,
          logo: logo,
          cliente: cliente,
          rucDni: rucDni,
          telefono: telefono,
          vendedor: vendedor,
          fecha: fecha,
          numero: numero,
          totalBruto: totalBruto,
          moneda: formatoMoneda,
        ),
        build: (context) => [
          ...items.asMap().entries.map(
                (e) => _filaProducto(
                  index: e.key,
                  item: e.value,
                  imagen: imagenes[e.value.producto.archivoImagen],
                ),
              ),
          pw.SizedBox(height: 16),
          _bancoYTotales(
            banco: banco,
            moneda: moneda,
            nroCuenta: nroCuenta,
            cci: cci,
            formatoMoneda: formatoMoneda,
            subtotal: subtotalNeto,
            impuestos: impuestos,
            total: totalBruto,
          ),
        ],
      ),
    );

    return doc.save();
  }

  // Prefijo que marca que "la ruta" guardada en el historial no es un path
  // de archivo sino el PDF entero embebido en base64 — así se distingue de
  // un path real sin tener que tocar el esquema de la tabla
  // cotizaciones_guardadas (columna archivo_pdf, ya en uso en el celular).
  static const _prefijoB64 = 'b64:';

  /// Guarda el PDF ya generado para poder volver a abrirlo/compartirlo
  /// después desde el Historial. En Android/iOS queda en un archivo real
  /// (como siempre); en la build web/PWA no existe tal cosa como una
  /// carpeta propia de la app (path_provider no tiene con qué implementar
  /// getApplicationDocumentsDirectory ahí), así que el PDF se guarda
  /// embebido en el propio registro del historial.
  static Future<String> guardarEnDisco(Uint8List bytes, int numero) async {
    if (kIsWeb) {
      return '$_prefijoB64${base64Encode(bytes)}';
    }
    final dir = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}/cotizaciones');
    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }
    final archivo = File('${carpeta.path}/cotizacion_${formatearNumero(numero)}.pdf');
    await archivo.writeAsBytes(bytes);
    return archivo.path;
  }

  /// Lee de vuelta un PDF guardado con [guardarEnDisco], sin que el
  /// llamador necesite saber si es un path real o el contenido embebido.
  static Future<Uint8List> leerArchivo(String ruta) async {
    if (ruta.startsWith(_prefijoB64)) {
      return base64Decode(ruta.substring(_prefijoB64.length));
    }
    return File(ruta).readAsBytes();
  }

  /// El contenido embebido siempre "existe" (va dentro del propio registro);
  /// solo un path real puede haberse perdido (celular restaurado, etc.).
  static Future<bool> existeArchivo(String ruta) async {
    if (ruta.startsWith(_prefijoB64)) return true;
    return File(ruta).exists();
  }

  /// Nada que borrar del disco cuando el PDF está embebido — desaparece
  /// solo con el registro del historial.
  static Future<void> eliminarArchivo(String ruta) async {
    if (ruta.startsWith(_prefijoB64)) return;
    try {
      final archivo = File(ruta);
      if (await archivo.exists()) await archivo.delete();
    } catch (_) {
      // No pasa nada si el archivo ya no está o no se puede borrar.
    }
  }

  /// PDF formal de un requerimiento de materiales: el mismo encabezado de
  /// marca que la cotización (con su recuadro de RUC / tipo de documento /
  /// Nro), los datos del pedido, una sección por categoría con lo pedido
  /// —el casillero se marca recién cuando se entregó— y las firmas de quien
  /// pide, quien aprueba (jefe de obra) y quien recibe.
  static Future<Uint8List> generarRequerimiento(Requerimiento r) async {
    final logo = await _cargarLogo();
    final firmaFont = await _cargarFuenteFirma();
    final fecha = DateFormat('dd/MM/yyyy HH:mm');

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _encabezadoDocumento(
          context: context,
          logo: logo,
          tipoDocumento: 'REQUERIMIENTO',
          numero: r.numero,
          datos: [
            ('Obra / proyecto', r.obra),
            ('Fecha de solicitud', fecha.format(r.fechaCreacion)),
            ('Solicitante', r.solicitante),
            ('Estado', r.estado.etiqueta),
          ],
          destacado: r.urgente ? 'PRIORIDAD: URGENTE' : null,
        ),
        build: (context) => [
          _resumenCantidades('Materiales solicitados', r.totalItems, r.totalUnidades),
          _leyendaCasillas(marcada: 'Entregado', vacia: 'Pendiente de entrega'),
          for (final cat in r.categorias) ..._seccionCategoriaDocumento(cat, marcado: r.entregado),
          ..._bloqueObservaciones('Observaciones', r.observaciones),
          pw.SizedBox(height: 30),
          _firmas(
            [
              _Firma(
                nombre: r.solicitante,
                cargo: 'Solicitante',
                detalle: fecha.format(r.fechaCreacion),
                completada: true,
              ),
              _Firma(
                nombre: r.aprobadoPor,
                cargo: 'Aprobado por jefe de obra',
                detalle: r.fechaAprobacion == null ? 'Pendiente de aprobación' : fecha.format(r.fechaAprobacion!),
                completada: r.fechaAprobacion != null,
                textoSinNombre: 'Aprobado',
              ),
              _Firma(
                nombre: r.recibidoPor,
                cargo: 'Recibido por',
                detalle: r.fechaEntrega == null ? 'Pendiente de entrega' : fecha.format(r.fechaEntrega!),
                completada: r.fechaEntrega != null,
                textoSinNombre: 'Entregado',
              ),
            ],
            firmaFont,
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// PDF formal de un checklist de herramientas: mismo formato que el
  /// requerimiento; el casillero de cada herramienta se marca cuando el
  /// encargado confirmó que volvió (estado Conforme).
  static Future<Uint8List> generarChecklistHerramientas(ChecklistHerramientas h) async {
    final logo = await _cargarLogo();
    final firmaFont = await _cargarFuenteFirma();
    final fecha = DateFormat('dd/MM/yyyy HH:mm');

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _encabezadoDocumento(
          context: context,
          logo: logo,
          tipoDocumento: 'CHECKLIST DE HERRAMIENTAS',
          numero: h.numero,
          datos: [
            ('Obra / proyecto', h.obra),
            ('Fecha de salida', fecha.format(h.fechaSalida)),
            ('Responsable', h.responsable),
            ('Estado', h.estado.etiqueta),
          ],
        ),
        build: (context) => [
          _resumenCantidades('Herramientas registradas', h.totalItems, h.totalUnidades),
          _leyendaCasillas(marcada: 'Devuelta', vacia: 'Pendiente de devolución'),
          for (final cat in h.categorias) ..._seccionCategoriaDocumento(cat, marcado: h.conforme),
          ..._bloqueObservaciones('Observaciones de la salida', h.observaciones),
          ..._bloqueObservaciones('Observaciones de la devolución', h.observacionesDevolucion),
          pw.SizedBox(height: 30),
          _firmas(
            [
              _Firma(
                nombre: h.responsable,
                cargo: 'Responsable (retira)',
                detalle: fecha.format(h.fechaSalida),
                completada: true,
              ),
              _Firma(
                nombre: h.encargado,
                cargo: 'Encargado (recibe la devolución)',
                detalle: h.fechaDevolucion == null ? 'Pendiente de devolución' : fecha.format(h.fechaDevolucion!),
                completada: h.fechaDevolucion != null,
                textoSinNombre: 'Conforme',
              ),
            ],
            firmaFont,
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<pw.MemoryImage> _cargarLogo() async =>
      pw.MemoryImage((await rootBundle.load(_logoAsset)).buffer.asUint8List());

  /// La firma se escribe en la tipografía cursiva, simulando una firma; si
  /// no se pudiera cargar, sale con la tipografía normal.
  static Future<pw.Font?> _cargarFuenteFirma() async {
    try {
      return pw.Font.ttf(await rootBundle.load(_firmaAsset));
    } catch (_) {
      return null;
    }
  }

  /// Fila de marca de la empresa (logo + razón social + dirección), igual en
  /// todos los documentos, más el recuadro de la derecha con el RUC y el
  /// tipo/número del documento.
  static pw.Widget _tarjetaEmpresa(pw.MemoryImage logo, String tipoDocumento, String numero) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(logo, height: 34, fit: pw.BoxFit.contain),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _empresa,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: BrandColors.pdfAzulMarino,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _direccion,
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'RUC: $_ruc',
                style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                tipoDocumento,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: BrandColors.pdfCian,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Nro $numero',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Encabezado de requerimientos y checklists de herramientas: en la
  /// primera página, la tarjeta de la empresa más el recuadro con los datos
  /// del documento (y el aviso de urgente si corresponde); en las demás,
  /// solo la tarjeta, igual que en la cotización.
  static pw.Widget _encabezadoDocumento({
    required pw.Context context,
    required pw.MemoryImage logo,
    required String tipoDocumento,
    required String numero,
    required List<(String, String)> datos,
    String? destacado,
  }) {
    final tarjeta = _tarjetaEmpresa(logo, tipoDocumento, numero);
    if (context.pageNumber != 1) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [tarjeta, pw.SizedBox(height: 10)],
      );
    }

    pw.Widget par((String, String) dato) {
      final (etiqueta, valor) = dato;
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text(
            valor.trim().isEmpty ? '-' : valor.trim(),
            style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ],
      );
    }

    final filas = <pw.Widget>[];
    for (var i = 0; i < datos.length; i += 2) {
      if (filas.isNotEmpty) filas.add(pw.SizedBox(height: 8));
      filas.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: par(datos[i])),
            pw.SizedBox(width: 12),
            pw.Expanded(child: i + 1 < datos.length ? par(datos[i + 1]) : pw.SizedBox()),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        tarjeta,
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(children: filas),
        ),
        if (destacado != null) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: pw.BoxDecoration(
              color: PdfColors.red50,
              border: pw.Border.all(color: PdfColors.red300),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              destacado,
              style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
            ),
          ),
        ],
        pw.SizedBox(height: 10),
      ],
    );
  }

  static pw.Widget _resumenCantidades(String titulo, int items, int unidades) {
    final textoItems = items == 1 ? '1 ítem' : '$items ítems';
    final textoUnidades = unidades == 1 ? '1 unidad' : '$unidades unidades';
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        '$titulo: $textoItems · $textoUnidades',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: BrandColors.pdfAzulMarino),
      ),
    );
  }

  static pw.Widget _leyendaCasillas({required String marcada, required String vacia}) {
    pw.Widget muestra(bool marcado, String texto) => pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            _casilla(marcado, tamano: 9),
            pw.SizedBox(width: 4),
            pw.Text(texto, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        );
    return pw.Row(
      children: [muestra(true, marcada), pw.SizedBox(width: 14), muestra(false, vacia)],
    );
  }

  static pw.Widget _casilla(bool marcado, {double tamano = 12}) {
    return pw.Container(
      width: tamano,
      height: tamano,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: marcado ? BrandColors.pdfCian : PdfColors.white,
        border: pw.Border.all(color: marcado ? BrandColors.pdfCian : PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: marcado
          ? pw.Text(
              'X',
              style: pw.TextStyle(
                fontSize: tamano * 0.66,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            )
          : null,
    );
  }

  /// Misma sección por categoría que tenía el checklist de obra: franja
  /// cian con el nombre y filas alternadas con casillero, ítem y cantidad.
  static List<pw.Widget> _seccionCategoriaDocumento(ChecklistCategoriaState cat, {required bool marcado}) {
    final cantidad = cat.items.length == 1 ? '1 ítem' : '${cat.items.length} ítems';
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
        color: BrandColors.pdfCian,
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                quitarNumeroCategoria(cat.nombre),
                style: const pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Text(cantidad, style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
          ],
        ),
      ),
      ...cat.items.asMap().entries.map((e) {
        final item = e.value;
        return pw.Container(
          color: e.key.isEven ? PdfColors.white : BrandColors.pdfTint(BrandColors.pdfCian, 0.94),
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          child: pw.Row(
            children: [
              _casilla(marcado),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  item.esExtra ? '${item.texto} (agregado${item.esProducto ? ' · catálogo' : ''})' : item.texto,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                item.cantidadTexto,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: BrandColors.pdfCian),
              ),
            ],
          ),
        );
      }),
    ];
  }

  static List<pw.Widget> _bloqueObservaciones(String titulo, String? texto) {
    final limpio = (texto ?? '').trim();
    if (limpio.isEmpty) return const [];
    return [
      pw.SizedBox(height: 14),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(titulo, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.SizedBox(height: 2),
            pw.Text(limpio, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    ];
  }

  /// Fila de firmas al pie: cada una con el nombre en cursiva (o, si ese paso
  /// ya se hizo sin anotar nombre, el texto del estado), la línea, el cargo y
  /// la fecha — o en blanco con "Pendiente..." mientras no se haya hecho.
  static pw.Widget _firmas(List<_Firma> firmas, pw.Font? firmaFont) {
    pw.Widget firma(_Firma f) {
      final nombre = (f.nombre ?? '').trim();
      final pw.Widget trazo;
      if (!f.completada) {
        trazo = pw.SizedBox(height: 30);
      } else if (nombre.isNotEmpty) {
        trazo = pw.SizedBox(
          height: 30,
          child: pw.Align(
            alignment: pw.Alignment.bottomLeft,
            child: pw.Text(
              nombre,
              maxLines: 1,
              style: pw.TextStyle(font: firmaFont, fontSize: 20, color: BrandColors.pdfAzulMarino),
            ),
          ),
        );
      } else {
        trazo = pw.SizedBox(
          height: 30,
          child: pw.Align(
            alignment: pw.Alignment.bottomLeft,
            child: pw.Text(
              f.textoSinNombre,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: BrandColors.pdfCian),
            ),
          ),
        );
      }
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          trazo,
          pw.Container(
            height: 0.8,
            color: PdfColors.grey400,
            margin: const pw.EdgeInsets.only(top: 2, bottom: 4),
          ),
          pw.Text(f.cargo, style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            f.detalle,
            style: pw.TextStyle(fontSize: 8, color: f.completada ? PdfColors.grey600 : PdfColors.orange800),
          ),
        ],
      );
    }

    final hijos = <pw.Widget>[];
    for (final f in firmas) {
      if (hijos.isNotEmpty) hijos.add(pw.SizedBox(width: 18));
      hijos.add(pw.Expanded(child: firma(f)));
    }
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: hijos);
  }

  /// Las fotos van empaquetadas en la propia app (assets/productos/), así
  /// que esto no depende de red ni de servidor; las de productos agregados
  /// desde el celular se leen de su archivo. Si un producto puntual no trae
  /// imagen, o el archivo ya no está, esa celda simplemente queda en blanco
  /// — no debe impedir que se genere el resto del PDF.
  static Future<Map<String, Uint8List>> _cargarImagenes(
    List<ItemCotizacion> items,
  ) async {
    final resultado = <String, Uint8List>{};

    final archivos = items.map((i) => i.producto.archivoImagen).whereType<String>().where((a) => a.isNotEmpty).toSet();

    await Future.wait(
      archivos.map((archivo) async {
        try {
          if (esRutaDeArchivo(archivo)) {
            resultado[archivo] = await File(archivo).readAsBytes();
          } else {
            final data = await rootBundle.load('assets/productos/$archivo');
            resultado[archivo] = data.buffer.asUint8List();
          }
        } catch (_) {
          // No está disponible esta foto en particular: se omite.
        }
      }),
    );
    return resultado;
  }

  // Solo 5 columnas (sin Impuestos ni Price): con menos columnas cada una
  // tiene más aire. Cada columna (salvo Descripción) tiene un ANCHO FIJO en
  // puntos, puesto directo en el Row sin Expanded — con Expanded, el propio
  // paquete pdf le impone al hijo un ancho "tight" igual al de su fracción
  // de flex e ignora el width que pida su SizedBox, así que el cuadro de la
  // imagen terminaba siendo angosto o ancho según el flex, no 40x40 real;
  // con fotos de distinto aspecto (retrato/paisaje) cada una se veía a una
  // escala distinta y la tabla se notaba descuadrada. Con ancho fijo real
  // el cuadro de imagen (y el resto de columnas) miden siempre lo mismo,
  // fila tras fila; Descripción es la única columna flexible, para que
  // absorba el espacio que sobra sin desarmar a las demás.
  static const _anchoItem = 26.0;
  static const _anchoImagen = 42.0;
  static const _anchoCantidad = 46.0;
  static const _anchoPUnit = 56.0;
  static const _espacioColumna = 6.0;

  static pw.Widget _espacio() => pw.SizedBox(width: _espacioColumna);

  static pw.Widget _encabezado({
    required pw.Context context,
    required pw.MemoryImage logo,
    required String cliente,
    required String rucDni,
    required String telefono,
    required String vendedor,
    required String fecha,
    required int numero,
    required double totalBruto,
    required NumberFormat moneda,
  }) {
    final numeroFmt = formatearNumero(numero);

    final tarjetaEmpresa = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(logo, height: 34, fit: pw.BoxFit.contain),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _empresa,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: BrandColors.pdfAzulMarino,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _direccion,
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'RUC: $_ruc',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'COTIZACIÓN',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: BrandColors.pdfCian,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Nro $numeroFmt',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
      ],
    );

    final filaTablaHeader = pw.Container(
      color: BrandColors.pdfCian,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: pw.Row(
        children: [
          _celdaHeaderCol('Item.', ancho: _anchoItem),
          _espacio(),
          _celdaHeaderCol('Imagen', ancho: _anchoImagen),
          _espacio(),
          _celdaHeaderCol('Descripción del Artículo'),
          _espacio(),
          _celdaHeaderCol('Cantidad', ancho: _anchoCantidad),
          _espacio(),
          _celdaHeaderCol('P. Unit.', ancho: _anchoPUnit),
        ],
      ),
    );

    if (context.pageNumber == 1) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          tarjetaEmpresa,
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    cliente.isEmpty ? 'Cliente sin nombre' : cliente,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                  if (rucDni.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'RUC/DNI: $rucDni',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                  if (telefono.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Tel: $telefono',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Total',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    moneda.format(totalBruto),
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: BrandColors.pdfCian,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Fecha de cotización',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    fecha,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Vendedor(a):',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                      ),
                      pw.Text(
                        vendedor.isEmpty ? '-' : vendedor,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Email:',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                      ),
                      pw.Text(
                        _email,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          filaTablaHeader,
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [tarjetaEmpresa, pw.SizedBox(height: 10), filaTablaHeader],
    );
  }

  static pw.Widget _celdaHeader(String texto, int flex) {
    return pw.Expanded(
      flex: flex,
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  // Igual que _celdaHeader, pero para la tabla de productos: ancho fijo por
  // columna (mismos anchos que usa _filaProducto) en vez de flex, salvo
  // Descripción, que no lleva [ancho] y queda como la única columna
  // flexible — así el header queda pixel a pixel alineado con las filas.
  static pw.Widget _celdaHeaderCol(String texto, {double? ancho}) {
    final contenido = pw.Text(
      texto,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    );
    return ancho != null ? pw.SizedBox(width: ancho, child: contenido) : pw.Expanded(child: contenido);
  }

  static pw.Widget _filaProducto({
    required int index,
    required ItemCotizacion item,
    Uint8List? imagen,
  }) {
    final p = item.producto;
    final ref = (p.referenciaInterna ?? '').isNotEmpty ? '[${p.referenciaInterna}] ' : '';

    return pw.Container(
      color: index.isEven ? PdfColors.white : BrandColors.pdfTint(BrandColors.pdfCian, 0.92),
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: _anchoItem,
            child: pw.Text('${index + 1}', style: const pw.TextStyle(fontSize: 9)),
          ),
          _espacio(),
          pw.SizedBox(
            width: _anchoImagen,
            height: _anchoImagen,
            child: imagen != null ? pw.Image(pw.MemoryImage(imagen), fit: pw.BoxFit.contain) : null,
          ),
          _espacio(),
          pw.Expanded(
            child: pw.Text(
              '$ref${p.nombre}',
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          _espacio(),
          pw.SizedBox(
            width: _anchoCantidad,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(item.cantidad.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 9)),
                pw.Text(
                  p.unidadMedida ?? '',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          _espacio(),
          pw.SizedBox(
            width: _anchoPUnit,
            child: pw.Text(
              (p.precioVenta ?? 0).toStringAsFixed(2),
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _bancoYTotales({
    required String banco,
    required String moneda,
    required String nroCuenta,
    required String cci,
    required NumberFormat formatoMoneda,
    required double subtotal,
    required double impuestos,
    required double total,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          color: BrandColors.pdfCian,
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          child: pw.Row(
            children: [
              _celdaHeader('Banco', 1),
              _celdaHeader('Moneda', 1),
              _celdaHeader('Nro Cuenta', 1),
              _celdaHeader('CCI', 1),
            ],
          ),
        ),
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: pw.Row(
            children: [
              _celdaDato(banco),
              _celdaDato(moneda),
              _celdaDato(nroCuenta),
              _celdaDato(cci),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                _filaTotal('Subtotal', formatoMoneda.format(subtotal)),
                _filaTotal('Impuestos', formatoMoneda.format(impuestos)),
                _filaTotal('Total', formatoMoneda.format(total), destacado: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _celdaDato(String valor) {
    return pw.Expanded(
      child: pw.Text(
        valor.isEmpty ? '-' : valor,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  static pw.Widget _filaTotal(String etiqueta, String valor, {bool destacado = false}) {
    return pw.Container(
      color: destacado ? BrandColors.pdfTint(BrandColors.pdfCian, 0.85) : null,
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            etiqueta,
            style: pw.TextStyle(
              fontSize: destacado ? 11 : 9,
              fontWeight: pw.FontWeight.bold,
              color: destacado ? BrandColors.pdfCian : PdfColors.black,
            ),
          ),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: destacado ? 13 : 10,
              fontWeight: pw.FontWeight.bold,
              color: destacado ? BrandColors.pdfCian : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una firma del pie de un documento de almacén (ver PdfService._firmas).
class _Firma {
  final String? nombre;
  final String cargo;
  final String detalle;
  final bool completada;

  /// Lo que se escribe sobre la línea si ese paso ya se hizo pero sin anotar
  /// un nombre (ej. "Aprobado").
  final String textoSinNombre;

  const _Firma({
    required this.nombre,
    required this.cargo,
    required this.detalle,
    required this.completada,
    this.textoSinNombre = '',
  });
}
