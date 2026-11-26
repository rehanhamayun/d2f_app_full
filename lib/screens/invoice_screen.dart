import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../services/invoice_pdf.dart';
import '../services/parcel_label.dart';
import '../models/models.dart';
import '../widgets/common.dart';

void openIntakeReceipt(BuildContext context, Parcel parcel) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: D2FAppBar(title: const Text('Intake receipt')),
        body: PdfPreview(
          pdfFileName: '${parcel.trackingId}-receipt.pdf',
          initialPageFormat: ParcelLabel.format,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          build: (_) => shipmentReceiptPdf(parcel),
        ),
      ),
    ),
  );
}

class InvoiceButton extends StatelessWidget {
  final String type, id;
  const InvoiceButton({super.key, required this.type, required this.id});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.receipt_long_outlined),
    label: const Text('View invoice'),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _InvoiceScreen(path: '/invoices/$type/${Uri.encodeComponent(id)}'),
      ),
    ),
  );
}

class _InvoiceScreen extends StatefulWidget {
  final String path;
  const _InvoiceScreen({required this.path});

  @override
  State<_InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<_InvoiceScreen> {
  late Future<Map<String, dynamic>> _invoice = _fetch();
  bool _sharing = false;

  Future<Map<String, dynamic>> _fetch() async =>
      Map<String, dynamic>.from(await Api.I.shipmentOperation(widget.path));

  Future<void> _share(Map<String, dynamic> invoice) async {
    setState(() => _sharing = true);
    try {
      final result = await Api.I.shipmentOperation(
        '${widget.path}/share',
        method: 'POST',
      );
      final link = Uri.parse(Api.I.currentBaseUrl)
          .resolve(result['path'] as String)
          .toString();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        useSafeArea: true,
        context: context,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Share invoice',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Anyone with the link can view this invoice for 7 days.',
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Copy invoice link'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      if (mounted) {
                        copyToClipboard(
                          context,
                          link,
                          message: 'Invoice link copied',
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: const Text('WhatsApp'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _launch(
                        Uri.https('wa.me', '/', {
                          'text': 'D2F invoice ${invoice['number']}\n$link',
                        }),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _launch(
                        Uri(
                          scheme: 'mailto',
                          query:
                              'subject=${Uri.encodeComponent('D2F invoice ${invoice['number']}')}&body=${Uri.encodeComponent(link)}',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        _message(
          error is ApiException
              ? error.message
              : 'Could not create a share link.',
        );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _launch(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted)
      _message('Could not open the app. You can copy the invoice link.');
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _invoice,
    builder: (context, snapshot) {
      final invoice = snapshot.data;
      return Scaffold(
        appBar: D2FAppBar(
          title: const Text('Invoice'),
          actions: [
            if (invoice != null)
              IconButton(
                tooltip: 'Share invoice link',
                onPressed: _sharing ? null : () => _share(invoice),
                icon: const Icon(Icons.ios_share_rounded),
              ),
          ],
        ),
        body: snapshot.connectionState != ConnectionState.done
            ? const Center(child: CircularProgressIndicator())
            : invoice == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : 'Could not load the invoice.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => setState(() => _invoice = _fetch()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : PdfPreview(
                pdfFileName: '${invoice['number']}.pdf',
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                build: (_) => invoicePdf(invoice),
              ),
      );
    },
  );
}
