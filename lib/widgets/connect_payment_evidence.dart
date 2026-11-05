import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/theme.dart';

class ConnectPaymentEvidenceForm extends StatefulWidget {
  final String bookingId, instructions;
  final int version;
  const ConnectPaymentEvidenceForm({
    super.key,
    required this.bookingId,
    required this.instructions,
    required this.version,
  });
  @override
  State<ConnectPaymentEvidenceForm> createState() =>
      _ConnectPaymentEvidenceFormState();
}

class _ConnectPaymentEvidenceFormState
    extends State<ConnectPaymentEvidenceForm> {
  String? _method, _error;
  bool _approved = false, _saving = false;
  Uint8List? _bytes;
  final _transaction = TextEditingController();
  Future<void> _pick() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.length > 4 * 1024 * 1024) {
        throw ApiException('Choose an image under 4 MB.');
      }
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    if (!_approved || _method == null || _bytes == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.I.submitConnectPaymentEvidence(
        widget.bookingId,
        method: _method!,
        instructionsVersion: widget.version,
        transactionId: _transaction.text.trim(),
        bytes: _bytes!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _transaction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Submit payment evidence')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('D2F payment instructions', style: AppTheme.sectionTitle),
        const SizedBox(height: 10),
        SelectableText(widget.instructions),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _approved,
          onChanged: _saving
              ? null
              : (v) => setState(() => _approved = v == true),
          title: const Text(
            'I reviewed and approve these payment instructions. I have paid using the verified D2F details shown above.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Payment method *'),
          items: const [
            DropdownMenuItem(
              value: 'MOBILE_MONEY',
              child: Text('Mobile money'),
            ),
            DropdownMenuItem(value: 'CASH', child: Text('Cash')),
            DropdownMenuItem(value: 'ZELLE', child: Text('Zelle')),
            DropdownMenuItem(value: 'CASH_APP', child: Text('Cash App')),
          ],
          onChanged: (v) => setState(() => _method = v),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _transaction,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Transaction ID / receipt reference (optional)',
          ),
        ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Attach payment screenshot or cash receipt *'),
        ),
        if (_bytes != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Image.memory(_bytes!, height: 220, fit: BoxFit.contain),
          ),
        const Text(
          'Submission is pending verification. It does not confirm funds received or move your shipment to a new physical stage.',
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.coral)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _approved && _method != null && _bytes != null && !_saving
              ? _save
              : null,
          child: Text(_saving ? 'Submitting…' : 'Submit for D2F verification'),
        ),
      ],
    ),
  );
}

Future<void> showConnectPaymentImage(
  BuildContext context,
  String bookingId,
  String submissionId,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Payment evidence'),
      content: SizedBox(
        width: 500,
        height: 420,
        child: FutureBuilder<Uint8List>(
          future: Api.I.connectPaymentImage(bookingId, submissionId),
          builder: (context, snapshot) => snapshot.hasData
              ? InteractiveViewer(
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                )
              : snapshot.hasError
              ? Text('${snapshot.error}')
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
