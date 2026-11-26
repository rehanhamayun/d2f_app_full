import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/marketplace.dart';
import '../models/models.dart';
import 'parcel_label.dart';

Future<pw.Font> _font() async =>
    pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));

Future<Uint8List> invoicePdf(Map<String, dynamic> invoice) async {
  final font = await _font();
  final doc = pw.Document(
    title: '${invoice['number']}',
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final currency = invoice['currency'] as String;
  final lines = (invoice['lines'] as List).cast<Map<String, dynamic>>();
  final issued = DateTime.parse(invoice['issuedAt'] as String);
  final dark = PdfColor.fromHex('#153F40');
  final muted = PdfColor.fromHex('#536A66');
  pw.Widget text(Object? value, double size, {PdfColor? color}) => pw.Text(
    '${value ?? ''}',
    style: pw.TextStyle(fontSize: size, color: color),
  );
  pw.Widget party(String heading, Object? name, [Object? location]) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          text(heading, 9, color: muted),
          pw.SizedBox(height: 5),
          text(name, 13),
          if (location != null) text(location, 10, color: muted),
        ],
      );

  doc.addPage(
    pw.MultiPage(
      pageTheme: const pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(44),
      ),
      footer: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: muted, width: .5)),
        ),
        child: text('D2F Shipping', 9, color: muted),
      ),
      build: (_) => [
        text(invoice['service'], 12, color: dark),
        pw.SizedBox(height: 7),
        text('Invoice', 34, color: dark),
        pw.SizedBox(height: 5),
        text(invoice['number'], 12),
        pw.SizedBox(height: 6),
        text('Issued ${DateFormat.yMMMd().format(issued)}', 10, color: muted),
        pw.SizedBox(height: 11),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          color: PdfColor.fromHex('#E9F1ED'),
          child: text(invoice['status'], 10, color: dark),
        ),
        pw.Divider(height: 30, color: dark),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: party(
                'ISSUED BY',
                invoice['issuer'],
                invoice['issuerLocation'],
              ),
            ),
            pw.SizedBox(width: 22),
            pw.Expanded(child: party('BILLED TO', invoice['buyer'])),
          ],
        ),
        pw.SizedBox(height: 22),
        text('REFERENCE', 9, color: muted),
        pw.SizedBox(height: 5),
        text(invoice['reference'], 11),
        if (invoice['route'] != null) text(invoice['route'], 11),
        pw.SizedBox(height: 25),
        pw.TableHelper.fromTextArray(
          headers: ['Description', currency],
          data: [
            for (final row in lines)
              [row['label'], formatMoney(row['amountMinor'] as int, currency)],
          ],
          headerDecoration: pw.BoxDecoration(color: dark),
          headerStyle: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 11),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 10,
          ),
          cellAlignments: {1: pw.Alignment.centerRight},
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
          },
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: muted, width: .4),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text('Invoice total', 13, color: dark),
            text(
              formatMoney(invoice['totalMinor'] as int, currency),
              17,
              color: dark,
            ),
          ],
        ),
        if (invoice['refundsMinor'] is int) ...[
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              text('Confirmed refunds', 10, color: muted),
              text(
                formatMoney(invoice['refundsMinor'] as int, currency),
                10,
                color: muted,
              ),
            ],
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

Future<Uint8List> shipmentReceiptPdf(Parcel parcel) async {
  final font = await _font();
  final doc = pw.Document(
    title: '${parcel.trackingId} intake receipt',
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  pw.Widget text(String? value, double size) => pw.Text(
    value?.trim().isNotEmpty == true ? value! : '-',
    style: pw.TextStyle(fontSize: size),
  );
  pw.Widget party(String heading, String? name, String? phone, String? place) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          text(heading, 8),
          pw.SizedBox(height: 6),
          text(name, 11),
          pw.SizedBox(height: 3),
          text(phone, 9),
          pw.SizedBox(height: 3),
          text(place, 9),
        ],
      );
  final packageCount = parcel.items.isEmpty ? 1 : parcel.items.length;
  final receivedCount = parcel.items.isEmpty
      ? 1
      : parcel.items.where((item) => !item.missed).length;
  final receivedAt = parcel.warehouseReceivedAt ?? parcel.createdAt;
  final rows = [
    if (parcel.items.isEmpty)
      [
        '1 / 1',
        parcel.trackingId,
        parcel.packageTypeLabel,
        '${parcel.verifiedWeightKg ?? parcel.weightKg} kg${parcel.verifiedWeightKg != null ? ' verified' : ' recorded'}',
      ]
    else
      for (final (index, item) in parcel.items.indexed)
        [
          '${index + 1} / $packageCount',
          item.packageCode ?? '-',
          item.typeLabel,
          if (item.missed)
            'Not received'
          else if (item.verifiedWeightKg != null)
            '${item.verifiedWeightKg} kg verified'
          else if (item.weightKg != null)
            '${item.weightKg} kg recorded'
          else
            'Not recorded',
        ],
  ];
  doc.addPage(
    pw.MultiPage(
      pageFormat: ParcelLabel.format,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              text('D2F SHIPPING', 17),
              text(parcel.serviceType.replaceAll('_', ' '), 9),
            ],
          ),
          pw.SizedBox(height: 3),
          text('Shipment intake receipt', 12),
          pw.Divider(height: 13, thickness: 1),
        ],
      ),
      footer: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Divider(height: 12, thickness: .5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              text(parcel.trackingId, 8),
              text('Page ${context.pageNumber} of ${context.pagesCount}', 8),
            ],
          ),
        ],
      ),
      build: (_) => [
        text('DESTINATION', 8),
        pw.SizedBox(height: 4),
        text(parcel.destination.toUpperCase(), 18),
        pw.SizedBox(height: 8),
        text('SHIPMENT GROUP / TRACKING', 8),
        pw.SizedBox(height: 3),
        text(parcel.trackingId, 14),
        pw.SizedBox(height: 6),
        text('Intake ${DateFormat.yMMMd().format(receivedAt.toLocal())}', 9),
        text('$receivedCount of $packageCount packages received', 9),
        text(
          '${parcel.verifiedWeightKg != null ? 'Verified total' : 'Recorded shipment weight'}  ${parcel.verifiedWeightKg ?? parcel.weightKg} kg',
          9,
        ),
        pw.Divider(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: party(
                'FROM',
                parcel.customer?.displayName,
                parcel.customer?.phone,
                parcel.origin,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: party(
                'SHIP TO',
                parcel.recipientName,
                parcel.recipientPhone,
                parcel.recipientAddress?.trim().isNotEmpty == true
                    ? parcel.recipientAddress
                    : parcel.destination,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.TableHelper.fromTextArray(
          headers: ['Package', 'Tracking / type', 'Weight'],
          data: [
            for (final row in rows) [row[0], '${row[1]}\n${row[2]}', row[3]],
          ],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
          headerStyle: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(
            vertical: 5,
            horizontal: 4,
          ),
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(width: .35),
          ),
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
          },
          cellAlignments: {2: pw.Alignment.centerRight},
          columnWidths: {
            0: const pw.FixedColumnWidth(42),
            2: const pw.FixedColumnWidth(83),
          },
        ),
      ],
    ),
  );
  return doc.save();
}
