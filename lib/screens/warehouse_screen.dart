import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/warehouse.dart';
import '../widgets/common.dart';
import 'container_detail_screen.dart';

class WarehouseScreen extends StatefulWidget {
  final Future<dynamic> Function(Map<String, dynamic> query)? loadContainers;
  const WarehouseScreen({super.key, this.loadContainers});
  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<FreightContainer> _containers = [];
  String _filter = 'ALL';
  String? _error;
  bool _loading = true;
  int _offset = 0, _total = 0, _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{
        'q': _search.text.trim(),
        'status': _filter,
        'offset': _offset,
      };
      final data =
          await (widget.loadContainers?.call(query) ??
              Api.I.warehouseRequest('/containers', query: query));
      if (!mounted || request != _request) return;
      setState(() {
        _containers = (data['containers'] as List)
            .map((j) => FreightContainer.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        _total = data['total'];
        _loading = false;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final created = await Navigator.push<FreightContainer>(
      context,
      MaterialPageRoute(builder: (_) => const CreateContainerScreen()),
    );
    if (!mounted || created == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContainerDetailScreen(containerId: created.id),
      ),
    );
    if (mounted) {
      _offset = 0;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const D2FAppBar(title: Text('Warehouse')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          SectionCard(
            tint: AppColors.navy,
            dark: true,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warehouse_outlined,
                  color: AppColors.gold,
                  size: 34,
                ),
                const SizedBox(height: 16),
                Text(
                  'Every parcel.\nReady to move.',
                  style: AppTheme.heading.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Load, manifest and follow each container from origin to destination.',
                  style: TextStyle(
                    color: Color(0xFFBAC8DB),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(label: 'Create Container', onPressed: _create),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Your containers', style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _offset = 0;
                _load();
              });
            },
            decoration: const InputDecoration(
              hintText: 'Search container reference',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final status in ['ALL', 'LOADING', 'DEPARTED', 'ARRIVED'])
                ChoiceChip(
                  label: Text(
                    status == 'ALL'
                        ? 'All'
                        : status[0] + status.substring(1).toLowerCase(),
                  ),
                  selected: _filter == status,
                  onSelected: (_) {
                    setState(() {
                      _filter = status;
                      _offset = 0;
                    });
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            WarehouseError(message: _error!, onRetry: _load)
          else if (_containers.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No containers yet',
              subtitle: 'Create a container to start loading parcels, or try another search.',
            )
          else ...[
            for (final c in _containers)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ContainerDetailScreen(containerId: c.id),
                        ),
                      );
                      if (mounted) _load();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: AppColors.blueSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.inventory_2_outlined,
                                color: AppColors.blue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(c.code, style: AppTheme.sectionTitle),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textGrey,
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Text(
                          '${c.origin.label}  →  ${c.destination.label}',
                          style: AppTheme.body,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ContainerStatus(status: c.status),
                            Text(
                              '${c.parcelCount} ${c.parcelCount == 1 ? 'parcel' : 'parcels'} · ${c.method}',
                              style: AppTheme.caption,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _offset > 0
                      ? () {
                          _offset -= 50;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text(
                  '${_offset + 1}–${_offset + _containers.length} of $_total',
                  style: AppTheme.caption,
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _offset + 50 < _total
                      ? () {
                          _offset += 50;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class ContainerStatus extends StatelessWidget {
  final String status;
  const ContainerStatus({super.key, required this.status});
  @override
  Widget build(BuildContext context) {
    final color = status == 'ARRIVED'
        ? AppColors.green
        : status == 'DEPARTED'
        ? AppColors.blue
        : AppColors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status[0] + status.substring(1).toLowerCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class WarehouseError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const WarehouseError({
    super.key,
    required this.message,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) => SectionCard(
    tint: AppColors.coralSoft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: AppTheme.body),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

class CreateContainerScreen extends StatefulWidget {
  final Future<List<WarehouseLocation>> Function()? loadLocations;
  const CreateContainerScreen({super.key, this.loadLocations});
  @override
  State<CreateContainerScreen> createState() => _CreateContainerScreenState();
}

class _CreateContainerScreenState extends State<CreateContainerScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController(),
      _seal = TextEditingController(),
      _notes = TextEditingController();
  List<WarehouseLocation>? _locations;
  String? _origin, _destination, _error;
  String _method = 'SEA';
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _seal.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data =
          await (widget.loadLocations?.call() ?? Api.I.warehouseLocations());
      if (mounted) setState(() => _locations = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await Api.I.warehouseRequest(
        '/containers',
        method: 'POST',
        data: {
          'code': _code.text.trim(),
          'originId': _origin,
          'destinationId': _destination,
          'method': _method,
          if (_seal.text.trim().isNotEmpty) 'sealNumber': _seal.text.trim(),
          if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        },
      );
      if (mounted) {
        Navigator.pop(
          context,
          FreightContainer.fromJson(Map<String, dynamic>.from(data)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  Widget _locationField(
    String label,
    String? selected,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.location_on_outlined),
    ),
    items: [
      for (final l in _locations ?? <WarehouseLocation>[])
        DropdownMenuItem(
          value: l.id,
          child: Text(
            '${l.code} · ${l.label}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: _saving ? null : onChanged,
    validator: (v) => v == null
        ? 'Choose a location.'
        : (_origin == _destination ? 'Choose two different locations.' : null),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const D2FAppBar(title: Text('Create Container')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const ScreenIntro(
          title: 'A new journey.',
          subtitle: 'Choose the route, give your container a reference, and start loading.',
        ),
        const SizedBox(height: 22),
        if (_locations == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          WarehouseError(
            message: _error!,
            onRetry: _locations == null ? _load : _save,
          ),
          const SizedBox(height: 16),
        ],
        if (_locations != null && _locations!.length < 2)
          const SectionCard(
            tint: AppColors.goldSoft,
            child: Text(
              'An administrator needs to add at least two warehouse locations before you can create a container.',
              style: AppTheme.body,
            ),
          ),
        if (_locations != null && _locations!.length >= 2)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: 'Container reference',
                          hintText: 'e.g. D2F-SEA-001',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        validator: (v) =>
                            RegExp(r'^[A-Za-z0-9-]{1,40}$')
                                .hasMatch(v?.trim() ?? '')
                            ? null
                            : 'Use letters, numbers and hyphens.',
                      ),
                      const SizedBox(height: 14),
                      _locationField(
                        'Origin warehouse',
                        _origin,
                        (v) => setState(() => _origin = v),
                      ),
                      const SizedBox(height: 16),
                      _locationField(
                        'Destination warehouse',
                        _destination,
                        (v) => setState(() => _destination = v),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _method,
                        decoration: const InputDecoration(
                          labelText: 'Shipping method',
                        ),
                        items: [
                          for (final m in ['SEA', 'AIR', 'ROAD'])
                            DropdownMenuItem(value: m, child: Text(m)),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _method = v!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _seal,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Seal number (optional)',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: 'Loading notes (optional)',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Create Container',
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
