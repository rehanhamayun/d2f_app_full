import 'package:flutter/material.dart';

import '../core/api.dart';

typedef OperationalRequest = Future<dynamic> Function(
  String, {
  String method,
  Map<String, dynamic>? data,
});

/// A selection records a note only; status changes remain explicit server events.
class OperationalNoteField extends StatefulWidget {
  final String status, serviceType;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final OperationalRequest? request;
  const OperationalNoteField({
    super.key,
    required this.status,
    required this.serviceType,
    required this.onChanged,
    this.request,
  });
  @override
  State<OperationalNoteField> createState() => _OperationalNoteFieldState();
}

class _OperationalNoteFieldState extends State<OperationalNoteField> {
  List<Map<String, dynamic>> _templates = [];
  String? _selected, _error;
  bool _loading = true;
  final _custom = TextEditingController(), _details = TextEditingController();
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OperationalNoteField old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status || old.serviceType != widget.serviceType) {
      _selected = null;
      _custom.clear();
      _details.clear();
      widget.onChanged({});
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await (widget.request ?? Api.I.shipmentOperation)(
        '/operational-notes?status=${Uri.encodeQueryComponent(widget.status)}&serviceType=${Uri.encodeQueryComponent(widget.serviceType)}',
        method: 'GET',
      );
      if (mounted && generation == _generation) {
        setState(() {
          _templates = (rows as List)
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => e['id'] is String && e['message'] is String)
              .toList();
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Standard messages could not load. Retry or choose Other - Custom Message.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _emit() => widget.onChanged(
    _selected == null
        ? {}
        : {
            if (_selected == 'OTHER')
              'customMessage': _custom.text.trim()
            else
              'noteTemplateId': _selected,
            if (_selected != 'OTHER') 'additionalDetails': _details.text.trim(),
          },
  );
  @override
  void dispose() {
    _custom.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey('operational-note-${widget.status}'),
        initialValue: _selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Operational message *',
          helperText: _loading
              ? 'Loading standard messages…'
              : 'Saved privately with staff, facility and timestamp.',
        ),
        items: [
          ..._templates.map(
            (t) => DropdownMenuItem<String>(
              value: t['id'],
              child: Text(
                t['message'],
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const DropdownMenuItem(
            value: 'OTHER',
            child: Text('Other - Custom Message'),
          ),
        ],
        selectedItemBuilder: (context) => [
          ..._templates.map(
            (t) => Text(
              t['message'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Text('Other - Custom Message'),
        ],
        onChanged: (v) {
          setState(() => _selected = v);
          _emit();
        },
      ),
      if (_error != null)
        Row(
          children: [
            Expanded(
              child: Text(_error!, style: const TextStyle(fontSize: 12)),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      if (_selected != null) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _selected == 'OTHER' ? _custom : _details,
          maxLines: 2,
          maxLength: _selected == 'OTHER' ? 1000 : 300,
          onChanged: (_) => _emit(),
          decoration: InputDecoration(
            labelText: _selected == 'OTHER'
                ? 'Custom operational message *'
                : 'Add Additional Details (optional)',
          ),
        ),
      ],
    ],
  );
}
