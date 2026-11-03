import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/direct_label_print.dart';
import '../services/parcel_label.dart';

class DirectLabelPrintScreen extends ConsumerStatefulWidget {
  final Parcel? parcel;
  final String? parcelId, trackingId;
  const DirectLabelPrintScreen({
    super.key,
    this.parcel,
    this.parcelId,
    this.trackingId,
  });
  @override
  ConsumerState<DirectLabelPrintScreen> createState() =>
      _DirectLabelPrintScreenState();
}

class _DirectLabelPrintScreenState
    extends ConsumerState<DirectLabelPrintScreen> {
  Map<String, dynamic> _settings = {};
  List<Map<String, dynamic>> _cached = [], _history = [], _devices = [];
  Uint8List? _pdf;
  String? _selectedParcel, _tracking, _error, _notice;
  String _media = 'DieCutW102H152';
  bool _busy = false, _loading = true;
  User? get _user => ref.read(authControllerProvider).valueOrNull;
  @override
  void initState() {
    super.initState();
    _selectedParcel = widget.parcel?.id ?? widget.parcelId;
    _tracking = widget.parcel?.trackingId ?? widget.trackingId;
    _load();
  }

  Future<void> _load() async {
    final user = _user ?? await ref.read(authControllerProvider.future);
    if (!mounted) return;
    if (!DirectLabelPrint.permitted(user)) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final settings = await DirectLabelPrint.settings();
      if (widget.parcel != null && _pdf == null) {
        _pdf = await DirectLabelPrint.cache(user!, widget.parcel!);
      } else if (_selectedParcel != null && _pdf == null) {
        try {
          final p = Parcel.fromJson(
            Map<String, dynamic>.from(
              await Api.I.shipmentOperation(
                '/label-print/parcels/$_selectedParcel',
              ),
            ),
          );
          _pdf = await DirectLabelPrint.cache(user!, p);
          _tracking = p.trackingId;
        } catch (_) {
          _pdf = await DirectLabelPrint.call('cachedPdf', {
            'ownerId': DirectLabelPrint.owner(user!),
            'parcelId': _selectedParcel,
          }) as Uint8List?;
          if (_pdf == null) rethrow;
        }
      }
      final cached = await DirectLabelPrint.rows('cachedLabels', user!),
          history = await DirectLabelPrint.rows('history', user);
      if (mounted)
        setState(() {
          _settings = settings;
          _cached = cached;
          _history = history;
          _media = settings['defaultPrinter']?['media'] ?? _media;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';
  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _devicesList(bool scan) => _run(() async {
    await DirectLabelPrint.call('permissions');
    final rows =
        await DirectLabelPrint.call(scan ? 'discover' : 'paired') as List;
    if (mounted)
      setState(
        () => _devices = rows.map((v) => Map<String, dynamic>.from(v)).toList(),
      );
  });
  Future<void> _selectCached(Map<String, dynamic> row) async {
    final bytes = await DirectLabelPrint.call('cachedPdf', {
      'ownerId': DirectLabelPrint.owner(_user!),
      'parcelId': row['parcelId'],
    }) as Uint8List?;
    if (mounted)
      setState(() {
        _selectedParcel = row['parcelId'];
        _tracking = row['trackingId'];
        _pdf = bytes;
      });
  }

  Future<void> _print() => _run(() async {
    if (Api.I.offlinePrintingOnly && Api.I.offlinePrintingUser == null)
      throw StateError(
        'Offline printing access expired. Reconnect and sign in again.',
      );
    final prior = _history
        .where((j) => j['parcelId'] == _selectedParcel)
        .toList();
    final reprint = prior.isNotEmpty;
    final reason = TextEditingController();
    String? approved;
    try {
      approved = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            reprint
                ? 'Confirm label reprint'
                : 'Confirm direct Bluetooth print',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Print $_tracking using ${_settings['defaultPrinter']?['name']}? One copy of the shipment label and each registered package label will be sent.',
                ),
                if (reprint) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Check existing labels first. An uncertain or interrupted job may already have produced labels.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Reason for reprinting *',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Printing does not change parcel tracking or confirm physical custody.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reprint && reason.text.trim().isEmpty) return;
                Navigator.pop(context, reason.text.trim());
              },
              child: Text(reprint ? 'Reprint label' : 'Print label'),
            ),
          ],
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 400), reason.dispose);
    }
    if (approved == null) return;
    await DirectLabelPrint.call('permissions');
    final outcome = await DirectLabelPrint.print(
      _user!,
      _selectedParcel!,
      _tracking!,
      reprint: reprint,
      reason: approved,
    );
    if (mounted)
      setState(() => _notice = outcome['message'] ?? outcome['status']);
    await _load();
    try {
      await DirectLabelPrint.sync(_user!);
      await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _notice =
              '${outcome['message']} History saved on this phone; use Sync history when online.',
        );
    }
  });
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (!DirectLabelPrint.permitted(user))
      return Scaffold(
        appBar: AppBar(title: const Text('Label printer')),
        body: const Center(
          child: Text(
            'Sign in as staff or an assigned driver to print operational labels.',
          ),
        ),
      );
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android)
      return Scaffold(
        appBar: AppBar(title: const Text('Label printer')),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Direct Brother Bluetooth printing is available in the Android app. Use the admin dashboard Windows connector on a computer.',
          ),
        ),
      );
    final printer = _settings['defaultPrinter'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brother label printer'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh printer and history',
          ),
        ],
      ),
      bottomNavigationBar: _selectedParcel == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                key: const ValueKey('direct-label-print'),
                onPressed: _busy || printer == null || _pdf == null
                    ? null
                    : _print,
                icon: const Icon(Icons.print),
                label: Text(
                  _busy
                      ? 'Working…'
                      : _history.any((j) => j['parcelId'] == _selectedParcel)
                      ? 'Reprint label'
                      : 'Print label',
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (Api.I.offlinePrintingOnly) ...[
                  const Text(
                    'Offline printing only · Saved labels are available for up to 24 hours after your last verified sign-in. Reconnect and sign in for live operations.',
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => ref
                              .read(authControllerProvider.notifier)
                              .signOut(),
                    child: const Text('Return to sign-in'),
                  ),
                ],
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.coral),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_notice!),
                  ),
                Text(
                  printer == null
                      ? 'Choose your Brother printer'
                      : printer['name'],
                  style: AppTheme.heading,
                ),
                const SizedBox(height: 8),
                Text(
                  printer == null
                      ? 'Proof of concept: QL-1110NWB / QL-1110NWBc, official SDK 4.13.2.'
                      : '${printer['address']} · Saved default · Connection not checked until requested.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => _devicesList(true),
                      child: const Text('Find nearby printers'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _devicesList(false),
                      child: const Text('Refresh paired printers'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await DirectLabelPrint.call('enableBluetooth');
                            }),
                      child: const Text('Enable Bluetooth'),
                    ),
                    if (printer != null)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await DirectLabelPrint.call('permissions');
                                final r = await DirectLabelPrint.call('status');
                                setState(
                                  () => _notice =
                                      'Connection: ${r['connected'] == true ? 'connected' : 'not connected'} · ${r['printerStatus'] ?? r['status']}',
                                );
                              }),
                        child: const Text('Check connection'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _media,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Paper loaded in the printer',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'DieCutW102H152',
                      child: Text('102 × 152 mm die-cut (4×6)'),
                    ),
                    DropdownMenuItem(
                      value: 'RollW102',
                      child: Text('102 mm continuous DK roll'),
                    ),
                    DropdownMenuItem(
                      value: 'DieCutW103H164',
                      child: Text('103 × 164 mm starter roll (larger)'),
                    ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _media = v!),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select the actual roll. A mismatched roll produces a paper-size error. Use 102 × 152 mm or a compatible 102 mm continuous roll for the 4×6 format.',
                ),
                if (printer != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await DirectLabelPrint.call('saveDefault', {
                              'address': printer['address'],
                              'name': printer['name'],
                              'media': _media,
                            });
                            await _load();
                            setState(() => _notice = 'Paper setting saved.');
                          }),
                    child: const Text('Apply paper setting'),
                  ),
                for (final d in _devices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      d['paired'] == true
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_searching,
                    ),
                    title: Text(d['name'] ?? 'Bluetooth printer'),
                    subtitle: Text(d['address']),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              if (d['paired'] != true) {
                                await DirectLabelPrint.call('pair', {
                                  'address': d['address'],
                                });
                                setState(
                                  () => _notice = 'Complete the Android pairing prompt, then refresh paired printers.',
                                );
                              } else {
                                await DirectLabelPrint.call('saveDefault', {
                                  'address': d['address'],
                                  'name': d['name'],
                                  'media': _media,
                                });
                                await _load();
                              }
                            }),
                      child: Text(
                        d['paired'] == true ? 'Save default' : 'Pair',
                      ),
                    ),
                  ),
                if (_pdf != null) ...[
                  const Divider(height: 30),
                  Text(
                    _tracking ?? 'Saved parcel label',
                    style: AppTheme.sectionTitle,
                  ),
                  const Text('Label saved on this phone for offline printing.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 320,
                    child: PdfPreview(
                      build: (_) async => _pdf!,
                      initialPageFormat: ParcelLabel.format,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      allowPrinting: false,
                      allowSharing: false,
                    ),
                  ),
                ],
                const Divider(height: 30),
                const Text(
                  'Saved labels on this phone',
                  style: AppTheme.sectionTitle,
                ),
                if (_cached.isEmpty)
                  const Text(
                    'Open Print Label from a parcel while online to save its label for offline use.',
                  ),
                for (final row in _cached)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['trackingId']),
                    subtitle: Text(
                      'Cached ${DateTime.fromMillisecondsSinceEpoch(row['cachedAt']).toLocal()}',
                    ),
                    onTap: _busy ? null : () => _run(() => _selectCached(row)),
                  ),
                const Divider(height: 30),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Print history',
                        style: AppTheme.sectionTitle,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final count = await DirectLabelPrint.sync(user!);
                              await _load();
                              setState(
                                () => _notice = '$count print results synced.',
                              );
                            }),
                      child: const Text('Sync history'),
                    ),
                  ],
                ),
                if (_history.isEmpty)
                  const Text('No direct print jobs recorded on this phone.'),
                for (final job
                    in _history
                        .where(
                          (j) =>
                              _selectedParcel == null ||
                              j['parcelId'] == _selectedParcel,
                        )
                        .take(50))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${job['trackingId']} · ${job['status']}'),
                    subtitle: Text(
                      '${job['printerName']} · ${job['pages']} page(s)\n${job['message'] ?? ''}\n${job['synced'] == true ? 'Synced' : 'Saved locally; pending sync'}',
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    final license = await rootBundle.loadString(
                      'assets/licenses/Brother-SDK-EULA.txt',
                    );
                    if (context.mounted)
                      showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Brother SDK license'),
                          content: SingleChildScrollView(child: Text(license)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                  },
                  child: const Text('Brother SDK license & notices'),
                ),
                const Text(
                  'The embedded Brother SDK must not be redistributed separately from this application.',
                ),
              ],
            ),
    );
  }
}
