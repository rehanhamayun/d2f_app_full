import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';

class ParcelLabel {
  static const format = PdfPageFormat(
    4 * PdfPageFormat.inch,
    6 * PdfPageFormat.inch,
    marginAll: 14,
  );
  static const _channel = MethodChannel('d2f/labels');
  static String filename(Parcel parcel) => '${parcel.trackingId}-label.pdf';

  static Future<Uint8List> generate(Parcel parcel) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/PlusJakartaSans.ttf'),
    );
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/d2f_2.png')).buffer.asUint8List(),
    );
    final doc = pw.Document(
      title: '${parcel.trackingId} shipping label',
      author: 'D2F Shipping LLC',
    );
    pw.Widget text(
      String value,
      double size, {
      PdfColor color = PdfColors.black,
    }) => pw.Text(
      value,
      style: pw.TextStyle(fontSize: size, color: color),
    );
    pw.Widget field(String label, String value, {double size = 9}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        text(label, 6.5, color: PdfColors.grey700),
        pw.SizedBox(height: 3),
        text(value, size),
      ],
    );
    doc.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              children: [
                pw.Image(logo, width: 29, height: 29),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      text('D2F GLOBAL', 14),
                      text('SHIPPING LABEL', 6.5),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: .7),
                  ),
                  child: text(parcel.method.name, 10),
                ),
              ],
            ),
            pw.Divider(height: 17, thickness: .7),
            text('TRACKING NUMBER', 6.5, color: PdfColors.grey700),
            pw.SizedBox(height: 4),
            text(parcel.trackingId, 18),
            pw.SizedBox(height: 7),
            pw.Container(
              color: PdfColors.white,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 5,
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: parcel.trackingId,
                drawText: false,
                height: 40,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 91,
                  height: 91,
                  padding: const pw.EdgeInsets.all(6),
                  color: PdfColors.white,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: parcel.trackingId,
                    drawText: false,
                  ),
                ),
                pw.SizedBox(width: 13),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      field('FROM', parcel.origin, size: 8),
                      pw.SizedBox(height: 9),
                      field('TO', parcel.destination, size: 10),
                      pw.SizedBox(height: 9),
                      text(
                        '${parcel.packageTypeLabel.toUpperCase()}  |  ${parcel.weightKg} kg',
                        8,
                      ),
                      if (parcel.items.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: text(
                            '${parcel.items.length} PACKAGE'
                            '${parcel.items.length == 1 ? '' : 'S'}'
                            ' IN THIS SHIPMENT',
                            7,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: .7)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  text('DELIVER TO', 6.5, color: PdfColors.grey700),
                  pw.SizedBox(height: 4),
                  pw.SizedBox(
                    height: 25,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.topLeft,
                      child: pw.SizedBox(
                        width: 240,
                        child: text(parcel.recipientName, 11),
                      ),
                    ),
                  ),
                  if (parcel.recipientPhone?.isNotEmpty ?? false) ...[
                    text(parcel.recipientPhone!, 8),
                    pw.SizedBox(height: 4),
                  ],
                  if (parcel.recipientAddress?.isNotEmpty ?? false)
                    pw.SizedBox(
                      height: 35,
                      child: pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        alignment: pw.Alignment.topLeft,
                        child: pw.SizedBox(
                          width: 240,
                          child: text(parcel.recipientAddress!, 8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Divider(height: 12, thickness: .5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                text(
                  'Registered ${DateFormat('dd MMM yyyy').format(parcel.createdAt.toLocal())}',
                  6.5,
                ),
                text('d2fshipping.com', 6.5),
              ],
            ),
            pw.SizedBox(height: 5),
            text(
              'Scan either code to retrieve this parcel. Keep the label flat and visible.',
              6,
            ),
          ],
        ),
      ),
    );

    // Per-package pages ("Box 2 of 6"): each declared package gets its own
    // printable label carrying the package sub-code (P01…) once the goods
    // have entered D2F custody. Scanning still resolves the shipment.
    final items = parcel.items
        .where((item) => item.packageCode != null)
        .toList(growable: false);
    for (final item in items) {
      final position = parcel.items.indexOf(item) + 1;
      final dims =
          (item.lengthCm != null &&
              item.widthCm != null &&
              item.heightCm != null)
          ? '  |  ${_labelCm(item.lengthCm!)}×${_labelCm(item.widthCm!)}×${_labelCm(item.heightCm!)} cm'
          : '';
      doc.addPage(
        pw.Page(
          pageFormat: format,
          theme: pw.ThemeData.withFont(base: font, bold: font),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                children: [
                  pw.Image(logo, width: 29, height: 29),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        text('D2F GLOBAL', 14),
                        text(
                          'PACKAGE P${position.toString().padLeft(2, '0')} OF ${parcel.items.length}',
                          6.5,
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: .7),
                    ),
                    child: text(
                      '${item.typeLabel.toUpperCase()} $position OF ${parcel.items.length}',
                      10,
                    ),
                  ),
                ],
              ),
              pw.Divider(height: 17, thickness: .7),
              text('SHIPMENT TRACKING NUMBER', 6.5, color: PdfColors.grey700),
              pw.SizedBox(height: 4),
              text(parcel.trackingId, 16),
              pw.SizedBox(height: 7),
              pw.Container(
                color: PdfColors.white,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: item.packageCode!,
                  drawText: false,
                  height: 40,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 91,
                    height: 91,
                    padding: const pw.EdgeInsets.all(6),
                    color: PdfColors.white,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: item.packageCode!,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(width: 13),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        field(
                          'PACKAGE (${item.typeLabel.toUpperCase()})',
                          '${item.name} · ×${item.quantity}',
                          size: 10,
                        ),
                        if (item.weightKg != null)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 7),
                            child: field(
                              'WEIGHT',
                              '${item.weightKg} kg$dims',
                              size: 9,
                            ),
                          )
                        else if (dims.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 7),
                            child: field('SIZE', dims.trim(), size: 9),
                          ),
                        if (item.details != null && item.details!.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 7),
                            child: field('NOTE', item.details!, size: 8),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(9),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: .7)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    text('DELIVER TO', 6.5, color: PdfColors.grey700),
                    pw.SizedBox(height: 4),
                    pw.SizedBox(
                      height: 25,
                      child: pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        alignment: pw.Alignment.topLeft,
                        child: pw.SizedBox(
                          width: 240,
                          child: text(parcel.recipientName, 11),
                        ),
                      ),
                    ),
                    if (parcel.recipientPhone?.isNotEmpty ?? false) ...[
                      text(parcel.recipientPhone!, 8),
                      pw.SizedBox(height: 4),
                    ],
                    if (parcel.recipientAddress?.isNotEmpty ?? false)
                      pw.SizedBox(
                        height: 35,
                        child: pw.FittedBox(
                          fit: pw.BoxFit.scaleDown,
                          alignment: pw.Alignment.topLeft,
                          child: pw.SizedBox(
                            width: 240,
                            child: text(parcel.recipientAddress!, 8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Divider(height: 12, thickness: .5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  text('Package code ${item.packageCode}'.toUpperCase(), 6.5),
                  text('d2fshipping.com', 6.5),
                ],
              ),
              pw.SizedBox(height: 5),
              text(
                'Scan the code to open the shipment record. Keep the label flat and visible.',
                6,
              ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  static String _labelCm(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  static Future<bool> save(Parcel parcel) async {
    final bytes = await generate(parcel);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return await _channel.invokeMethod<bool>('savePdf', {
            'name': filename(parcel),
            'bytes': bytes,
          }) ??
          false;
    }
    return Printing.sharePdf(bytes: bytes, filename: filename(parcel));
  }

  static Future<bool> share(Parcel parcel) async => Printing.sharePdf(
    bytes: await generate(parcel),
    filename: filename(parcel),
  );
}
