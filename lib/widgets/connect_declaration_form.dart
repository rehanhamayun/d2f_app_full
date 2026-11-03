import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import 'operational_note_field.dart';

class ConnectDeclarationForm extends StatefulWidget {
  final String bookingId, contents;
  final OperationalRequest request;
  final String? resourcePath;
  final bool traveller;
  const ConnectDeclarationForm({
    super.key,
    required this.bookingId,
    required this.contents,
    required this.request,
    this.resourcePath,
    this.traveller = false,
  });
  @override
  State<ConnectDeclarationForm> createState() => _ConnectDeclarationFormState();
}

class _ConnectDeclarationFormState extends State<ConnectDeclarationForm> {
  final _contents = TextEditingController(), _name = TextEditingController();
  final _checks = List<bool>.filled(5, false);
  bool _electronic = false, _saving = false;
  Map<String, dynamic>? _policy;
  String? _error;
  @override
  void initState() {
    super.initState();
    _contents.text = widget.contents;
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.request(
        '${widget.resourcePath ?? '/bookings/${widget.bookingId}'}/declaration-policy',
        method: 'GET',
      );
      if (mounted)
        setState(() {
          _policy = Map<String, dynamic>.from(p);
          if (widget.traveller)
            _contents.text = p['contents'] ?? widget.contents;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool get _valid =>
      _policy != null &&
      _checks.every((c) => c) &&
      _electronic &&
      _contents.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty;
  String get _missing {
    final missing = <String>[];
    if (_contents.text.trim().isEmpty) missing.add('itemized contents');
    final remaining = _checks.where((c) => !c).length;
    if (remaining > 0)
      missing.add(
        '$remaining declaration checkbox${remaining == 1 ? '' : 'es'}',
      );
    if (_name.text.trim().isEmpty)
      missing.add('full legal name (one or more words)');
    if (!_electronic) missing.add('electronic acknowledgment');
    return 'To confirm, complete: ${missing.join(', ')}.';
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.request(
        '${widget.resourcePath ?? '/bookings/${widget.bookingId}'}/declarations',
        method: 'POST',
        data: {
          'contents': _contents.text.trim(),
          'legalName': _name.text.trim(),
          'termsVersion': _policy!['termsVersion'],
          'checks': _checks.toList(),
          'electronicAcknowledgment': _electronic,
        },
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
    _contents.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.traveller ? 'Traveller declaration' : 'Contents declaration',
      ),
    ),
    resizeToAvoidBottomInset: false,
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_valid && _policy != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_missing, style: AppTheme.caption),
              ),
            FilledButton(
              key: const ValueKey('declaration-confirm'),
              onPressed: _valid && !_saving ? _save : null,
              child: Text(_saving ? 'Saving…' : 'Confirm declaration'),
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
          if (_policy == null) ...[
            if (_error == null)
              const LinearProgressIndicator()
            else
              TextButton(
                onPressed: _load,
                child: const Text('Retry loading declaration'),
              ),
          ],
          if (_policy != null) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.coralSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.gpp_maybe_outlined, color: AppColors.coral),
                  const SizedBox(height: 10),
                  const Text(
                    'LEGAL & SAFETY WARNING',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(_policy!['warning']),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final g in _policy!['guidance'] as List) ...[
              Text(g['title'], style: AppTheme.sectionTitle),
              const SizedBox(height: 6),
              Text(g['message']),
              if (g['source'] != null)
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(g['source']),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Read official guidance'),
                ),
              const SizedBox(height: 14),
            ],
            TextField(
              key: const ValueKey('declaration-contents'),
              controller: _contents,
              readOnly: widget.traveller,
              minLines: 4,
              maxLines: 7,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Itemized contents with quantities *',
                hintText: 'e.g. 3 cotton shirts; 2 pairs of shoes; 1 book. Declare all electronics, batteries and regulated goods.',
              ),
              onChanged: (_) => setState(() {
                for (var i = 0; i < 5; i++) {
                  _checks[i] = false;
                }
                _electronic = false;
              }),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 5; i++)
              CheckboxListTile(
                key: ValueKey('declaration-check-$i'),
                value: _checks[i],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _checks[i] = v == true),
                title: Text((_policy!['checks'] as List)[i]),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            const Divider(height: 28),
            const Text('D2F shipping terms', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            Text(_policy!['terms']),
            const SizedBox(height: 8),
            Text(
              'Terms version: ${_policy!['termsVersion']}',
              style: AppTheme.caption,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('declaration-legal-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full legal name *'),
              onChanged: (_) => setState(() => _electronic = false),
            ),
            CheckboxListTile(
              key: const ValueKey('declaration-electronic'),
              value: _electronic,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _electronic = v == true),
              title: const Text(
                'I electronically acknowledge this declaration and the displayed D2F shipping terms using my full legal name.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const Text(
              'Your acknowledgment is saved with this booking and timestamp. D2F staff must separately inspect and approve the parcel. If you decline, the booking cannot progress to acceptance.',
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.coral),
              ),
            ),
        ],
      ),
    ),
  );
}
