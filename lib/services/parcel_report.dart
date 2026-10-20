import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';

/// Multi-page parcel summary report (details + event history) used by the
/// "Download parcel details" action on the Tracking tab.
class ParcelReport {
  static const _channel = MethodChannel('d2f/labels');
  static String filename(Parcel parcel) => '${parcel.trackingId}-details.pdf';

  static Future<Uint8List> generate(Parcel parcel) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/PlusJakartaSans.ttf'),
    );
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/d2f_2.png')).buffer.asUint8List(),
    );
    final doc = pw.Document(
      title: '${parcel.trackingId} parcel details',
      author: 'D2F Shipping LLC',
    );
    final df = DateFormat('MMM d, yyyy • h:mm a');

    pw.Widget label(String value) => pw.Text(
      value.toUpperCase(),
      style: pw.TextStyle(
        fontSize: 6.8,
        color: PdfColors.grey700,
        letterSpacing: 1.1,
        fontWeight: pw.FontWeight.bold,
      ),
    );
    pw.Widget value(String text, {double size = 10}) => pw.Text(
      text,
      style: pw.TextStyle(fontSize: size, color: PdfColors.grey900),
    );
    pw.Widget field(String name, String text, {double size = 10}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        label(name),
        pw.SizedBox(height: 3),
        value(text, size: size),
      ],
    );

    final header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Image(logo, width: 30, height: 30),
            pw.SizedBox(width: 9),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'D2F GLOBAL',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'PARCEL DETAILS REPORT',
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey700,
                      letterSpacing: 1.2,
                    ),
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
                color: PdfColors.grey100,
                border: pw.Border.all(width: .7),
              ),
              child: pw.Text(
                statusLabel(parcel.status),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.Divider(height: 16, thickness: .7),
        label('Tracking number'),
        pw.SizedBox(height: 3),
        pw.Text(
          parcel.trackingId,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: parcel.trackingId,
          drawText: false,
          height: 34,
        ),
      ],
    );

    final summary = pw.Wrap(
      spacing: 18,
      runSpacing: 12,
      children: [
        pw.SizedBox(
          width: 160,
          child: field('From (customer)', parcel.customer?.displayName ?? '—'),
        ),
        pw.SizedBox(
          width: 160,
          child: field('Recipient', parcel.recipientName),
        ),
        pw.SizedBox(
          width: 160,
          child: field(
            'Route',
            '${parcel.origin} → ${parcel.destination}',
            size: 9.5,
          ),
        ),
        pw.SizedBox(
          width: 160,
          child: field('Shipping method', parcel.method.label),
        ),
        pw.SizedBox(
          width: 160,
          child: field(
            'Package',
            '${parcel.packageTypeLabel}  |  ${parcel.weightKg} kg',
          ),
        ),
        pw.SizedBox(
          width: 160,
          child: field(
            'Registered',
            df.format(parcel.createdAt.toLocal()),
            size: 9,
          ),
        ),
        pw.SizedBox(
          width: 160,
          child: field(
            'Last update',
            df.format(parcel.updatedAt.toLocal()),
            size: 9,
          ),
        ),
        pw.SizedBox(
          width: 160,
          child: field(
            'Recipient contact',
            parcel.recipientPhone?.isNotEmpty ?? false
                ? parcel.recipientPhone!
                : 'Not provided',
            size: 9,
          ),
        ),
      ],
    );

    final notes = (parcel.notes?.isNotEmpty ?? false)
        ? pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              label('Notes'),
              pw.SizedBox(height: 3),
              value(parcel.notes!, size: 9),
            ],
          )
        : null;

    final events = <pw.Widget>[
      pw.Table(
        border: pw.TableBorder.all(width: .6, color: PdfColors.grey400),
        columnWidths: {
          0: const pw.FixedColumnWidth(72),
          1: const pw.FixedColumnWidth(84),
          2: const pw.FixedColumnWidth(92),
          3: const pw.FixedColumnWidth(84),
          4: const pw.FixedColumnWidth(128),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (final h in ['Status', 'When', 'Location', 'By', 'Note'])
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          for (final e in parcel.events)
            pw.TableRow(
              children: [
                for (final cell in [
                  statusLabel(e.status),
                  DateFormat('MMM d, HH:mm').format(e.createdAt.toLocal()),
                  e.location ?? '—',
                  e.actorName ?? '—',
                  e.note ?? '—',
                ])
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      cell,
                      style: const pw.TextStyle(fontSize: 7.4),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ];

    doc.addPage(
      pw.MultiPage(
        maxPages: 4,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (context) => [
          header,
          pw.SizedBox(height: 14),
          summary,
          if (notes != null) ...[pw.SizedBox(height: 12), notes],
          pw.SizedBox(height: 16),
          label('Shipment history (${parcel.events.length} events)'),
          pw.SizedBox(height: 6),
          ...events,
          pw.SizedBox(height: 18),
          pw.Divider(height: 12, thickness: .5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated ${df.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 6.8),
              ),
              pw.Text(
                'd2fshipping.com',
                style: const pw.TextStyle(fontSize: 6.8),
              ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Saves through the Android document picker (same flow as labels); falls
  /// back to the system share sheet on other platforms.
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
}
