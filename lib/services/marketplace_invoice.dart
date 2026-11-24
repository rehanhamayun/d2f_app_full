import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/marketplace.dart';

Future<void> printMarketplaceInvoice(MarketplaceOrder order) async {
  final invoice = order.marketplaceInvoice;
  if (invoice == null) return;
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  final document = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
  final date = DateTime.tryParse(invoice['issuedAt'] as String? ?? '');
  final currency = invoice['currency'] as String? ?? order.currency;
  final refunds = order.marketplaceIssues
      .where((issue) => issue['type'] == 'REFUND' && issue['status'] == 'RESOLVED')
      .fold(0, (total, issue) => total + ((issue['amountMinor'] as num?)?.toInt() ?? 0));
  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (_) => [
      pw.Text('Marketplace invoice', style: const pw.TextStyle(fontSize: 24)),
      pw.Text(invoice['number'] as String),
      if (date != null) pw.Text('Issued ${DateFormat.yMMMd().format(date.toLocal())}'),
      pw.SizedBox(height: 14),
      pw.Text('Seller  ${invoice['issuer']}'),
      if ((invoice['issuerLocation'] as String? ?? '').isNotEmpty) pw.Text(invoice['issuerLocation'] as String),
      pw.Text('Buyer  ${invoice['buyer']}'),
      pw.Text('Order ID  ${order.id}'),
      pw.SizedBox(height: 14),
      pw.TableHelper.fromTextArray(
        headers: ['Item', 'Quantity', 'Unit price', 'Line total'],
        data: [[invoice['item'], invoice['quantity'], formatMoney((invoice['unitPriceMinor'] as num?)?.toInt(), currency), formatMoney((invoice['subtotalMinor'] as num?)?.toInt(), currency)]],
      ),
      pw.SizedBox(height: 12),
      pw.Text('Total  ${formatMoney((invoice['totalMinor'] as num?)?.toInt(), currency)} $currency'),
      pw.Text('Payment status  ${order.paymentStatus?.replaceAll('_', ' ') ?? 'Awaiting payment'}'),
      if (refunds > 0) pw.Text('Confirmed refunds  ${formatMoney(refunds, currency)}'),
    ],
  ));
  await Printing.layoutPdf(name: '${invoice['number']}.pdf', onLayout: (_) => document.save());
}
