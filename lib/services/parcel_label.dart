import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';

class ParcelLabel {
  static const format = PdfPageFormat(
    4 * PdfPageFormat.inch,
    6 * PdfPageFormat.inch,
    marginAll: 15,
  );
  static const _channel = MethodChannel('d2f/labels');
  static String filename(Parcel parcel) => '${parcel.trackingId}-label.pdf';

  static Future<Uint8List> generate(Parcel parcel) async {
    final packages = parcel.items.indexed
        .where((entry) => !entry.$2.missed && entry.$2.packageCode != null)
        .map((entry) => (entry.$1 + 1, entry.$2 as ParcelItem?))
        .toList();
    if (parcel.items.isEmpty) packages.add((1, null));
    if (packages.isEmpty) {
      throw StateError(
        'Labels are available after D2F records physical custody.',
      );
    }

    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/PlusJakartaSans.ttf'),
    );
    final doc = pw.Document(
      title: '${parcel.trackingId} shipping labels',
      author: 'D2F Shipping',
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );

    pw.Widget field(
      String value,
      double left,
      double top,
      double width,
      double height,
      double size, {
      int maxLines = 1,
      PdfColor color = PdfColors.black,
    }) => pw.Positioned(
      left: left,
      top: top,
      child: pw.SizedBox(
        width: width,
        height: height,
        child: pw.FittedBox(
          alignment: pw.Alignment.topLeft,
          fit: pw.BoxFit.scaleDown,
          child: pw.SizedBox(
            width: width,
            child: pw.Text(
              value.trim().isEmpty ? '-' : value,
              maxLines: maxLines,
              style: pw.TextStyle(fontSize: size, color: color),
            ),
          ),
        ),
      ),
    );

    pw.Widget rule(double top, {double height = .7}) => pw.Positioned(
      left: 0,
      top: top,
      child: pw.Container(width: 258, height: height, color: PdfColors.black),
    );

    List<pw.Widget> address(
      String title,
      String name,
      String? phone,
      String place,
      double left,
    ) => [
      field(title, left, 235, 120, 10, 8),
      field(name, left, 251, 120, 23, 11, maxLines: 2),
      field(phone ?? '', left, 277, 120, 13, 9),
      field(place, left, 293, 120, 35, 9, maxLines: 4),
    ];

    for (final (position, item) in packages) {
      final code = item?.packageCode ?? parcel.trackingId;
      final count = parcel.items.isEmpty ? 1 : parcel.items.length;
      final verifiedWeight =
          item?.verifiedWeightKg ??
          (count == 1 ? parcel.verifiedWeightKg : null);
      final labelWeight =
          verifiedWeight ??
          item?.weightKg ??
          (count == 1 ? parcel.weightKg : null);
      final verified =
          verifiedWeight != null ||
          (parcel.warehouseReceived &&
              parcel.restrictionsAcknowledgedAt == null);
      final method = switch (parcel.serviceType) {
        'AIR_TRAVELLER' => 'AIR TRAVELLER',
        'AIR_CARGO' => 'AIR CARGO',
        _ => parcel.method.name,
      };

      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.SizedBox(
            width: 258,
            height: 402,
            child: pw.Stack(
              children: [
                field('D2F SHIPPING', 0, 1, 184, 25, 20),
                pw.Positioned(
                  left: 194,
                  top: 1,
                  child: pw.Container(
                    width: 64,
                    height: 25,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.Text(
                      method,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ),
                rule(34, height: 1.3),
                field('DESTINATION', 0, 45, 184, 11, 8),
                field(
                  parcel.destination.toUpperCase(),
                  0,
                  62,
                  187,
                  47,
                  23,
                  maxLines: 2,
                ),
                pw.Positioned(
                  left: 196,
                  top: 45,
                  child: pw.Container(
                    width: 62,
                    height: 59,
                    color: PdfColors.black,
                    alignment: pw.Alignment.center,
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          '$position / $count',
                          style: const pw.TextStyle(
                            fontSize: 16,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'PACKAGE',
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                rule(114),
                field('PACKAGE TRACKING', 0, 125, 258, 11, 8),
                pw.Positioned(
                  left: 0,
                  top: 140,
                  child: pw.SizedBox(
                    width: 258,
                    height: 27,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.topLeft,
                      child: pw.Text(
                        code,
                        style: const pw.TextStyle(fontSize: 21),
                      ),
                    ),
                  ),
                ),
                pw.Positioned(
                  left: 16,
                  top: 173,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: code,
                    drawText: false,
                    width: 226,
                    height: 44,
                  ),
                ),
                rule(225),
                ...address(
                  'FROM',
                  parcel.customer?.displayName ?? '',
                  parcel.customer?.phone,
                  parcel.origin,
                  0,
                ),
                ...address(
                  'SHIP TO',
                  parcel.recipientName,
                  parcel.recipientPhone,
                  parcel.recipientAddress?.trim().isNotEmpty == true
                      ? parcel.recipientAddress!
                      : parcel.destination,
                  134,
                ),
                rule(332),
                field('SHIPMENT GROUP', 0, 341, 182, 11, 8),
                field(parcel.trackingId, 0, 355, 182, 17, 13),
                field(
                  (item?.typeLabel ?? parcel.packageTypeLabel).toUpperCase(),
                  0,
                  376,
                  180,
                  12,
                  9,
                ),
                field(
                  labelWeight == null
                      ? 'WEIGHT NOT RECORDED'
                      : '${verified ? 'VERIFIED' : 'RECORDED'} WEIGHT  $labelWeight kg',
                  0,
                  389,
                  180,
                  12,
                  9,
                ),
                pw.Positioned(
                  left: 192,
                  top: 336,
                  child: pw.Container(
                    width: 66,
                    height: 66,
                    padding: const pw.EdgeInsets.all(7),
                    color: PdfColors.white,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: code,
                      drawText: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return doc.save();
  }

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
