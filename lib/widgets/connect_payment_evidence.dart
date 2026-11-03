import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/theme.dart';

class ConnectPaymentEvidenceForm extends StatefulWidget {
  final String bookingId, instructions;
  final int version;
  final Future<Uint8List?> Function(ImageSource)? pickImage;
  final Future<void> Function({
    required String method,
    required String transactionId,
    required Uint8List bytes,
  })?
  submit;
  const ConnectPaymentEvidenceForm({
    super.key,
    required this.bookingId,
    required this.instructions,
    required this.version,
    this.pickImage,
    this.submit,
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
  Future<void> _pick(ImageSource source) async {
    try {
      final bytes = widget.pickImage != null
          ? await widget.pickImage!(source)
          : await _pickDevice(source);
      if (bytes == null) return;
      if (bytes.length > 4 * 1024 * 1024) {
        throw ApiException('Choose an image under 4 MB.');
      }
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _error = null;
        });
      }
    } on PlatformException catch (e) {
      if (mounted)
        setState(
          () => _error = e.code.toLowerCase().contains('denied')
              ? 'Camera or photo access was denied. Enable access in Android Settings > Apps > D2F Global > Permissions, then try again.'
              : 'Could not open the camera or photo picker. Please try again.',
        );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<Uint8List?> _pickDevice(ImageSource source) async {
    if (source == ImageSource.camera &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android)
      await const MethodChannel('d2f/permissions').invokeMethod('camera');
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 85,
    );
    return image == null ? null : await image.readAsBytes();
  }

  String get _missing => [
    if (!_approved) 'approve the payment instructions',
    if (_method == null) 'select the payment method',
    if (_bytes == null) 'attach a camera photo or screenshot',
  ].join(' · ');

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_approved || _method == null || _bytes == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.submit != null) {
        await widget.submit!(
          method: _method!,
          transactionId: _transaction.text.trim(),
          bytes: _bytes!,
        );
      } else
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
    resizeToAvoidBottomInset: false,
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_missing, style: AppTheme.caption),
              ),
            FilledButton(
              key: const ValueKey('payment-evidence-submit'),
              onPressed:
                  _approved && _method != null && _bytes != null && !_saving
                  ? _save
                  : null,
              child: Text(
                _saving ? 'Submitting…' : 'Submit for D2F verification',
              ),
            ),
          ],
        ),
      ),
    ),
    body: SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('payment-camera'),
                onPressed: _saving ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('payment-gallery'),
                onPressed: _saving ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose screenshot / receipt'),
              ),
            ],
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
        ],
      ),
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
