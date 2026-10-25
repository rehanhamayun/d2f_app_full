import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A4 multipage manifest. Departure freezes the data on the server; printing
/// the same manifest again never changes its contents or parcel identities.
class ContainerManifest {
  static Future<Uint8List> generate(Map<String, dynamic> manifest) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/PlusJakartaSans.ttf'),
    );
    final parcels = (manifest['parcels'] as List).cast<Map>();
    final navy = PdfColor.fromHex('#071541');
    final doc = pw.Document(
      title: '${manifest['code']} container manifest',
      author: 'D2F Shipping LLC',
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        maxPages: (parcels.length / 15).ceil() + 10,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'D2F GLOBAL',
                  style: pw.TextStyle(
                    color: navy,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  manifest['provisional'] == true
                      ? 'DRAFT - LOADING OPEN'
                      : 'FINAL MANIFEST',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              manifest['code'],
              style: pw.TextStyle(fontSize: 22, color: navy),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '${manifest['origin']}  ->  ${manifest['destination']}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '${manifest['method']} | ${manifest['parcelCount']} parcels | ${manifest['totalWeightKg']} kg | Seal: ${manifest['sealNumber'] ?? "Not recorded"}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Issued: ${manifest['issuedAt']}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.Divider(height: 24),
          ],
        ),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'D2F Shipping LLC | ${manifest['code']}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: [
              'Tracking number',
              'Customer / Recipient',
              'Package',
              'Weight (kg)',
            ],
            data: [
              for (final p in parcels)
                [
                  p['trackingId'],
                  '${p['customer']?['displayName'] ?? ""}\n${p['recipientName']}',
                  p['packageType'],
                  '${p['weightKg']}',
                ],
            ],
            headerDecoration: pw.BoxDecoration(color: navy),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(8),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(1.8),
              2: const pw.FlexColumnWidth(.8),
              3: const pw.FlexColumnWidth(.8),
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
