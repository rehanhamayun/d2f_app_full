import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import '../services/parcel_label.dart';

class LabelPreviewScreen extends StatefulWidget {
  final Parcel parcel;
  const LabelPreviewScreen({super.key, required this.parcel});
  @override
  State<LabelPreviewScreen> createState() => _LabelPreviewScreenState();
}

class _LabelPreviewScreenState extends State<LabelPreviewScreen> {
  bool _saving = false;
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await ParcelLabel.save(widget.parcel);
      if (mounted && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Shipping label saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the label. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: D2FAppBar(
      title: const Text('Shipping label'),
      actions: [
        IconButton(
          tooltip: 'Save PDF',
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded),
        ),
      ],
    ),
    body: PdfPreview(
      pdfFileName: ParcelLabel.filename(widget.parcel),
      initialPageFormat: ParcelLabel.format,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      build: (_) => ParcelLabel.generate(widget.parcel),
    ),
  );
}
