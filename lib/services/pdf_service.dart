import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../state/cotizacion_state.dart';
import '../theme/brand_colors.dart';

const _logoAsset = 'assets/icon/icon.png';

/// Genera la cotización en PDF con el formato oficial de Inversiones ICR:
/// encabezado con logo/RUC/Nro, fila de cliente (+ RUC/DNI opcional) /
/// total/fecha, vendedor/email, tabla de productos, y el bloque de
/// Banco/Moneda/Cuenta/CCI + Subtotal/Impuestos/Total al final.
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

  /// Guarda el PDF ya generado en el almacenamiento propio de la app, para
  /// poder volver a abrirlo/compartirlo después desde el Historial.
  static Future<String> guardarEnDisco(Uint8List bytes, int numero) async {
    final dir = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}/cotizaciones');
    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }
    final archivo = File('${carpeta.path}/cotizacion_${formatearNumero(numero)}.pdf');
    await archivo.writeAsBytes(bytes);
    return archivo.path;
  }

  /// Las fotos van empaquetadas en la propia app (assets/productos/), así
  /// que esto no depende de red ni de servidor: si un producto puntual no
  /// trae imagen, o el archivo no está en el bundle, esa celda simplemente
  /// queda en blanco — no debe impedir que se genere el resto del PDF.
  static Future<Map<String, Uint8List>> _cargarImagenes(
    List<ItemCotizacion> items,
  ) async {
    final resultado = <String, Uint8List>{};

    final archivos = items
        .map((i) => i.producto.archivoImagen)
        .whereType<String>()
        .where((a) => a.isNotEmpty)
        .toSet();

    await Future.wait(
      archivos.map((archivo) async {
        try {
          final data = await rootBundle.load('assets/productos/$archivo');
          resultado[archivo] = data.buffer.asUint8List();
        } catch (_) {
          // No está empaquetada esta foto en particular: se omite.
        }
      }),
    );
    return resultado;
  }

  // Solo 5 columnas (sin Impuestos ni Price): con menos columnas cada una
  // tiene más aire, y la imagen queda en un cuadro de tamaño fijo — así se
  // ve pareja fila con fila, en vez de estirarse según la foto de cada una.
  static const _flexItem = 1;
  static const _flexImagen = 3;
  static const _flexDescripcion = 8;
  static const _flexCantidad = 2;
  static const _flexPUnit = 2;
  static const _anchoImagen = 40.0;

  static pw.Widget _encabezado({
    required pw.Context context,
    required pw.MemoryImage logo,
    required String cliente,
    required String rucDni,
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
          _celdaHeader('Item.', _flexItem),
          _celdaHeader('Imagen', _flexImagen),
          _celdaHeader('Descripción del Artículo', _flexDescripcion),
          _celdaHeader('Cantidad', _flexCantidad),
          _celdaHeader('P. Unit.', _flexPUnit),
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
          pw.Expanded(
            flex: _flexItem,
            child: pw.Text('${index + 1}', style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Expanded(
            flex: _flexImagen,
            child: pw.SizedBox(
              width: _anchoImagen,
              height: _anchoImagen,
              child: imagen != null
                  ? pw.Image(pw.MemoryImage(imagen), fit: pw.BoxFit.contain)
                  : null,
            ),
          ),
          pw.Expanded(
            flex: _flexDescripcion,
            child: pw.Text('$ref${p.nombre}', style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Expanded(
            flex: _flexCantidad,
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
          pw.Expanded(
            flex: _flexPUnit,
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
