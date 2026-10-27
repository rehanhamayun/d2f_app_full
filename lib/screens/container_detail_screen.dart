import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/warehouse.dart';
import '../services/container_manifest.dart';
import '../widgets/common.dart';
import 'warehouse_screen.dart';
import 'scan_screen.dart';
import 'parcel_detail_screen.dart';

class ContainerDetailScreen extends StatefulWidget {
  final String containerId;
  final Future<FreightContainer> Function()? loadContainer;
  final Future<dynamic> Function(
    String path,
    String method,
    Map<String, dynamic>? data,
  )?
  performRequest;
  const ContainerDetailScreen({
    super.key,
    required this.containerId,
    this.loadContainer,
    this.performRequest,
  });
  @override
  State<ContainerDetailScreen> createState() => _ContainerDetailScreenState();
}

class _ContainerDetailScreenState extends State<ContainerDetailScreen> {
  final _tracking = TextEditingController();
  FreightContainer? _container;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c =
          await (widget.loadContainer?.call() ??
              Api.I.containerDetail(widget.containerId));
      if (mounted) {
        setState(() {
          _container = c;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) =>
      widget.performRequest?.call(path, method, data) ??
      Api.I.warehouseRequest(path, method: method, data: data);
  Future<void> _loadParcel(String tracking) async {
    if (tracking.trim().isEmpty) return;
    await _perform(() async {
      final result = await _request(
        '/containers/${widget.containerId}/parcels',
        method: 'POST',
        data: {'trackingId': tracking.trim()},
      );
      _tracking.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['alreadyLoaded'] == true
                  ? 'This parcel is already loaded.'
                  : 'Parcel loaded successfully.',
            ),
          ),
        );
      }
    });
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _event(String action) async {
    final c = _container!;
    final departure = action == 'DEPARTED';
    if (!await _confirm(
          departure ? 'Confirm departure' : 'Confirm arrival',
          departure
              ? 'Mark ${c.code} and all ${c.parcelCount} parcels as departed from ${c.origin.label}? Loading will close and the manifest will be finalized.'
              : 'Mark ${c.code} and all ${c.parcelCount} parcels as arrived at ${c.destination.label}?',
          departure ? 'Depart container' : 'Record arrival',
        ) ||
        !mounted) {
      return;
    }
    await _perform(() async {
      await _request(
        '/containers/${c.id}/events',
        method: 'POST',
        data: {'action': action},
      );
    });
  }

  Future<void> _manifest() async {
    await _perform(() async {
      final data = Map<String, dynamic>.from(
        await _request('/containers/${widget.containerId}/manifest'),
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: const D2FAppBar(title: Text('Container Manifest')),
            body: PdfPreview(
              pdfFileName: '${_container!.code}-manifest.pdf',
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              build: (_) => ContainerManifest.generate(data),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _container;
    return Scaffold(
      appBar: D2FAppBar(
        title: Text(c?.code ?? 'Container'),
        actions: [
          IconButton(
            tooltip: 'Refresh container',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: c == null
          ? (_error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: WarehouseError(message: _error!, onRetry: _load),
                  )
                : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  if (_error != null) ...[
                    WarehouseError(message: _error!, onRetry: _load),
                    const SizedBox(height: 16),
                  ],
                  SectionCard(
                    tint: AppColors.blueSoft,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ContainerStatus(status: c.status),
                            Text(
                              '${c.method} FREIGHT',
                              style: AppTheme.caption,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          c.code,
                          style: AppTheme.heading.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 16),
                        _routeEndpoint(
                          'FROM',
                          c.origin.label,
                          Icons.trip_origin_rounded,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 9.5),
                          child: Container(
                            height: 18,
                            width: 1,
                            color: AppColors.blue,
                          ),
                        ),
                        _routeEndpoint(
                          'TO',
                          c.destination.label,
                          Icons.location_on_outlined,
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth < 260
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _metric(
                                      '${c.parcelCount}',
                                      'Loaded parcels',
                                    ),
                                    const SizedBox(height: 12),
                                    _metric(
                                      '${c.totalWeight.toStringAsFixed(2)} kg',
                                      'Total weight',
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: _metric(
                                        '${c.parcelCount}',
                                        'Loaded parcels',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _metric(
                                        '${c.totalWeight.toStringAsFixed(2)} kg',
                                        'Total weight',
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        if (c.sealNumber != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            'Seal: ${c.sealNumber}',
                            style: AppTheme.caption,
                          ),
                        ],
                        if (c.notes != null) ...[
                          const SizedBox(height: 10),
                          Text(c.notes!, style: AppTheme.body),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _manifest,
                      icon: const Icon(Icons.print_outlined),
                      label: Text(
                        c.status == 'LOADING'
                            ? 'Preview Draft Manifest'
                            : 'Print Manifest',
                      ),
                    ),
                  ),
                  if (c.status == 'LOADING') ...[
                    const SizedBox(height: 18),
                    SectionCard(
                      tint: AppColors.goldSoft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Load a parcel',
                            style: AppTheme.sectionTitle,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Scan the saved label or enter its tracking number. Shipping methods must match.',
                            style: AppTheme.caption,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _tracking,
                            enabled: !_busy,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.go,
                            onSubmitted: _loadParcel,
                            decoration: const InputDecoration(
                              labelText: 'Tracking number',
                              prefixIcon: Icon(Icons.tag_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FormFieldPair(
                            first: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final code = await Navigator.push<String>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const ScanScreen(
                                            returnTracking: true,
                                          ),
                                        ),
                                      );
                                      if (mounted && code != null) {
                                        _loadParcel(code);
                                      }
                                    },
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: const Text('Scan label'),
                            ),
                            second: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _loadParcel(_tracking.text),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Load parcel'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text('Loaded parcels', style: AppTheme.sectionTitle),
                  const SizedBox(height: 12),
                  if (c.parcels.isEmpty)
                    const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Ready for your first parcel',
                      subtitle: 'Loaded parcels will appear here and on the manifest.',
                    ),
                  for (final p in c.parcels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SectionCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ParcelDetailScreen(parcelId: p.id),
                                    ),
                                  );
                                  if (mounted) _load();
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.trackingId,
                                      style: AppTheme.body.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      p.recipientName,
                                      style: AppTheme.caption,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${p.packageTypeLabel} · ${p.weightKg} kg',
                                      style: AppTheme.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (c.status == 'LOADING')
                              IconButton(
                                tooltip: 'Remove parcel',
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (!await _confirm(
                                              'Remove parcel?',
                                              'Remove ${p.trackingId} from ${c.code}? Its parcel record and history will be kept.',
                                              'Remove',
                                            ) ||
                                            !mounted) {
                                          return;
                                        }
                                        _perform(() async {
                                          await _request(
                                            '/containers/${c.id}/parcels/${p.id}',
                                            method: 'DELETE',
                                          );
                                        });
                                      },
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: AppColors.coral,
                                ),
                              )
                            else
                              const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  if (c.status != 'ARRIVED') ...[
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: c.status == 'LOADING'
                          ? 'Confirm Departure'
                          : 'Record Arrival',
                      loading: _busy,
                      onPressed: c.parcelCount == 0
                          ? null
                          : () => _event(
                              c.status == 'LOADING' ? 'DEPARTED' : 'ARRIVED',
                            ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  const Text('Container history', style: AppTheme.sectionTitle),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      children: [
                        for (final e in c.events)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: AppColors.teal,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (e['action'] as String).replaceAll(
                                          '_',
                                          ' ',
                                        ),
                                        style: AppTheme.body.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        e['detail'] ?? '',
                                        style: AppTheme.caption,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${e['actorName']} · ${DateFormat('MMM d, y · HH:mm').format(DateTime.parse(e['createdAt']).toLocal())}',
                                        style: AppTheme.caption,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _routeEndpoint(String label, String value, IconData icon) => Row(
    children: [
      Icon(icon, size: 20, color: AppColors.blue),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTheme.caption.copyWith(fontSize: 10, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTheme.body.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _metric(String value, String label) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTheme.sectionTitle),
        const SizedBox(height: 4),
        Text(label, style: AppTheme.caption),
      ],
    ),
  );
}
