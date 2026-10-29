import 'scan_screen.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';

class ShipmentCustodyCard extends StatelessWidget {
  final Parcel parcel;
  final Future<void> Function() onSaved;
  const ShipmentCustodyCard({
    super.key,
    required this.parcel,
    required this.onSaved,
  });
  @override
  Widget build(BuildContext context) {
    final pickup = parcel.deliveryMode == DeliveryMode.PICKUP;
    final schedule =
        pickup && ['REQUESTED', 'PICKUP_SCHEDULED'].contains(parcel.status);
    final legacyPickup =
        parcel.status == 'PICKED_UP' && parcel.pickupConfirmedAt == null;
    final intake =
        !parcel.warehouseReceived &&
        (['RECEIVED', 'PROCESSING'].contains(parcel.status) ||
            parcel.status == 'PICKED_UP' && parcel.pickupConfirmedAt != null ||
            !pickup && parcel.status == 'REQUESTED');
    final dispatch = [
      'ARRIVED_LOME',
      'ARRIVED_DESTINATION',
      'READY_FOR_PICKUP',
    ].contains(parcel.status);
    if (!schedule &&
        !intake &&
        !dispatch &&
        parcel.status != 'OUT_FOR_DELIVERY' &&
        !legacyPickup)
      return const SizedBox.shrink();
    Future<void> open(String mode) async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShipmentCustodyScreen(parcel: parcel, mode: mode),
        ),
      );
      await onSaved();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pickup & warehouse custody',
                  style: AppTheme.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            legacyPickup
                ? 'An older pickup is recorded without driver evidence. Admin must assign verification in the portal; the driver confirms custody before warehouse receipt.'
                : parcel.status == 'PICKUP_SCHEDULED'
                ? 'Appointment confirmed. The assigned driver must confirm physical collection. These goods are not yet at the warehouse.'
                : parcel.status == 'PICKED_UP'
                ? 'In driver custody. Warehouse staff must scan and verify every collected package separately.'
                : parcel.status == 'OUT_FOR_DELIVERY'
                ? 'In delivery-driver custody. The assigned driver records the actual recipient handover.'
                : pickup && parcel.status == 'REQUESTED'
                ? 'Pickup requested. Confirm an appointment, driver and receiving warehouse.'
                : !pickup && parcel.status == 'REQUESTED'
                ? 'Awaiting customer drop-off. Confirm receipt only when the goods are physically here.'
                : 'Verify the actual facility and package handover before proceeding.',
            style: AppTheme.caption,
          ),
          if (schedule)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                onPressed: () => open('schedule'),
                icon: const Icon(Icons.event_available),
                label: Text(
                  parcel.status == 'PICKUP_SCHEDULED'
                      ? 'Manage pickup appointment'
                      : 'Schedule pickup & assign driver',
                ),
              ),
            ),
          if (intake)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                onPressed: () => open('intake'),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan & verify warehouse receipt'),
              ),
            ),
          if (dispatch)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () => open('dispatch'),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Assign driver & dispatch delivery'),
              ),
            ),
        ],
      ),
    );
  }
}

class ShipmentCustodyScreen extends StatefulWidget {
  final Parcel parcel;
  final String mode;
  const ShipmentCustodyScreen({
    super.key,
    required this.parcel,
    required this.mode,
  });
  @override
  State<ShipmentCustodyScreen> createState() => _ShipmentCustodyScreenState();
}

class _ShipmentCustodyScreenState extends State<ShipmentCustodyScreen> {
  final _scan = TextEditingController(), _note = TextEditingController();
  final _verified = <String>{};
  List<dynamic> _locations = [], _drivers = [];
  String? _locationId, _driverId, _error;
  DateTime? _appointment;
  bool _confirmed = false, _busy = false, _loading = true;
  bool get _schedule => widget.mode == 'schedule';
  bool get _dispatch => widget.mode == 'dispatch';
  @override
  void initState() {
    super.initState();
    _appointment =
        widget.parcel.pickupScheduledAt ?? widget.parcel.pickupPreferredAt;
    _locationId = _dispatch
        ? widget.parcel.locationId
        : widget.parcel.pickupTargetLocationId ?? widget.parcel.locationId;
    _driverId = widget.parcel.pickupDriverId;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        Api.I.shipmentOperation('/warehouse/locations'),
        Api.I.shipmentOperation('/parcels/drivers/active'),
      ]);
      if (mounted)
        setState(() {
          _locations = r[0];
          _drivers = r[1];
          if (!_drivers.any((d) => d['id'] == _driverId)) _driverId = null;
          if (_locations.length == 1) _locationId = _locations.first['id'];
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final expected = widget.parcel.items.where((i) => !i.missed).toList();
    if (_locationId == null ||
        !_confirmed ||
        ((_schedule || _dispatch) && _driverId == null) ||
        (_schedule && _appointment == null) ||
        (!_schedule &&
            !_dispatch &&
            (_scan.text.trim().isEmpty ||
                _note.text.trim().isEmpty ||
                _verified.length != expected.length))) {
      setState(
        () => _error = 'Complete the facility, assignment or package checklist, and confirm the actual handover.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.I.shipmentOperation(
        '/parcels/${widget.parcel.id}/${_schedule
            ? 'pickup-schedule'
            : _dispatch
            ? 'events'
            : 'warehouse-intake'}',
        method: 'POST',
        data: {
          'locationId': _locationId,
          'confirmed': true,
          if (_schedule) ...{
            'pickupDriverId': _driverId,
            'pickupScheduledAt': _appointment!.toUtc().toIso8601String(),
          },
          if (_dispatch) ...{
            'status': 'OUT_FOR_DELIVERY',
            'deliveryDriverId': _driverId,
          },
          if (!_schedule && !_dispatch) ...{
            'scannedTrackingId': _scan.text.trim(),
            'verifiedItemIds': _verified.toList(),
            'note': _note.text.trim(),
          },
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _schedule
            ? 'Confirm D2F pickup'
            : _dispatch
            ? 'Dispatch delivery'
            : 'Warehouse receipt',
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(widget.parcel.trackingId, style: AppTheme.sectionTitle),
              const SizedBox(height: 8),
              Text(
                _schedule
                    ? 'Confirm the customer’s appointment and assign responsibility. Scheduling does not move the goods into warehouse custody.'
                    : _dispatch
                    ? 'Confirm the physical handover from this destination facility to the assigned delivery driver.'
                    : 'Scan the physical shipment, check each collected package and record the warehouse inspection.',
                style: AppTheme.caption,
              ),
              const SizedBox(height: 22),
              DropdownButtonFormField<String>(
                initialValue: _locationId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _schedule
                      ? 'Planned receiving warehouse'
                      : 'Actual facility',
                ),
                items: _locations
                    .map(
                      (l) => DropdownMenuItem<String>(
                        value: l['id'],
                        child: Text(
                          '${l['name']} · ${l['city']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _locationId = v),
              ),
              const SizedBox(height: 18),
              if (_schedule || _dispatch) ...[
                DropdownButtonFormField<String>(
                  initialValue: _driverId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Assigned D2F driver',
                  ),
                  items: _drivers
                      .map(
                        (d) => DropdownMenuItem<String>(
                          value: d['id'],
                          child: Text(d['fullName']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _driverId = v),
                ),
                if (_drivers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Admin must invite and activate a Driver account through Team & access.',
                    ),
                  ),
                const SizedBox(height: 18),
              ],
              if (_schedule)
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final initial =
                        _appointment != null && _appointment!.isAfter(now)
                        ? _appointment!
                        : now.add(const Duration(days: 1));
                    final d = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 90)),
                    );
                    if (d == null || !context.mounted) return;
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(initial),
                    );
                    if (t != null && mounted)
                      setState(
                        () => _appointment = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t.hour,
                          t.minute,
                        ),
                      );
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _appointment == null
                        ? 'Choose confirmed pickup time'
                        : DateFormat('EEE, MMM d · h:mm a')
                              .format(_appointment!),
                  ),
                ),
              if (!_schedule && !_dispatch) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final code = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScanScreen(returnTracking: true),
                      ),
                    );
                    if (code != null && mounted)
                      setState(() => _scan.text = code);
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan physical parcel label'),
                ),
                TextField(
                  controller: _scan,
                  decoration: const InputDecoration(
                    labelText: 'Scan / enter the D2F tracking number',
                    prefixIcon: Icon(Icons.qr_code_scanner),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _note,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Inspection & package condition',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Verify every physical package received',
                  style: AppTheme.sectionTitle,
                ),
                for (final item in widget.parcel.items.where((i) => !i.missed))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _verified.contains(item.id),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.packageCode ?? item.typeLabel} · ${item.quantity} contents units',
                    ),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _verified.add(item.id);
                      } else {
                        _verified.remove(item.id);
                      }
                    }),
                  ),
              ],
              const SizedBox(height: 20),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _confirmed,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _confirmed = v ?? false),
                title: Text(
                  _schedule
                      ? 'D2F confirmed this appointment, driver and receiving facility with the customer.'
                      : 'I physically verified and confirmed this handover at the selected facility.',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.coral),
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : _schedule
                        ? 'Confirm pickup appointment'
                        : _dispatch
                        ? 'Confirm driver dispatch'
                        : 'Confirm warehouse receipt',
                  ),
                ),
              ),
            ],
          ),
  );
}

class DriverTasksScreen extends StatefulWidget {
  final Future<dynamic> Function(
    String, {
    String method,
    Map<String, dynamic>? data,
  })?
  request;
  const DriverTasksScreen({super.key, this.request});
  @override
  State<DriverTasksScreen> createState() => _DriverTasksScreenState();
}

class _DriverTasksScreenState extends State<DriverTasksScreen> {
  List<dynamic> _tasks = [];
  bool _loading = true, _busy = false;
  String? _error;
  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) => (widget.request ?? Api.I.shipmentOperation)(
    path,
    method: method,
    data: data,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _request('/driver/tasks');
      if (mounted)
        setState(() {
          _tasks = rows;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(Map<String, dynamic> task) async {
    final scan = TextEditingController(),
        proof = TextEditingController(),
        recipient = TextEditingController();
    final missed = <String, TextEditingController>{};
    bool confirmed = false;
    final pickup = task['status'] != 'OUT_FOR_DELIVERY';
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            pickup ? 'Confirm physical pickup' : 'Confirm recipient delivery',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(task['trackingId']),
                  TextButton.icon(
                    onPressed: () async {
                      final code = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ScanScreen(returnTracking: true),
                        ),
                      );
                      if (code != null && context.mounted)
                        setDialog(() => scan.text = code);
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan physical label'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: scan,
                    onChanged: (_) => setDialog(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Scan / enter D2F tracking number',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!pickup)
                    TextField(
                      controller: recipient,
                      onChanged: (_) => setDialog(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Actual recipient name',
                      ),
                    ),
                  TextField(
                    controller: proof,
                    onChanged: (_) => setDialog(() {}),
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Handover / identity / proof reference',
                    ),
                  ),
                  if (pickup) ...[
                    const Text(
                      'Mark only packages not collected, with a reason.',
                    ),
                    for (final item in task['items'] as List)
                      Column(
                        children: [
                          CheckboxListTile(
                            value: missed.containsKey(item['id']),
                            title: Text('Not collected: ${item['name']}'),
                            onChanged: (v) => setDialog(() {
                              if (v == true) {
                                missed[item['id']] = TextEditingController();
                              } else {
                                missed.remove(item['id']);
                              }
                            }),
                          ),
                          if (missed.containsKey(item['id']))
                            TextField(
                              controller: missed[item['id']],
                              onChanged: (_) => setDialog(() {}),
                              maxLength: 300,
                              decoration: const InputDecoration(
                                labelText:
                                    'Why was this package not collected?',
                              ),
                            ),
                        ],
                      ),
                  ],
                  CheckboxListTile(
                    value: confirmed,
                    onChanged: (v) => setDialog(() => confirmed = v ?? false),
                    title: Text(
                      pickup
                          ? 'I physically collected these goods. They are in my custody, awaiting warehouse receipt.'
                          : 'I verified the recipient and physically completed the delivery.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  !confirmed ||
                      scan.text.trim().isEmpty ||
                      proof.text.trim().isEmpty ||
                      (!pickup && recipient.text.trim().isEmpty) ||
                      missed.values.any((c) => c.text.trim().isEmpty) ||
                      (pickup &&
                          (task['items'] as List).isNotEmpty &&
                          missed.length == (task['items'] as List).length)
                  ? null
                  : () => Navigator.pop(context, {
                      'confirmed': true,
                      'scannedTrackingId': scan.text.trim(),
                      'proofReference': proof.text.trim(),
                      'recipientName': recipient.text.trim(),
                      'missedItems': [
                        for (final e in missed.entries)
                          {'itemId': e.key, 'reason': e.value.text.trim()},
                      ],
                    }),
              child: const Text('Confirm actual handover'),
            ),
          ],
        ),
      ),
    );
    // Dialog controllers are released after their closing animation.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      scan.dispose();
      proof.dispose();
      recipient.dispose();
      for (final c in missed.values) {
        c.dispose();
      }
    });
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _request(
        '/driver/tasks/${task['id']}/confirm',
        method: 'POST',
        data: body,
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Your assigned handovers', style: AppTheme.display),
          const SizedBox(height: 10),
          const Text(
            'Confirm only the goods you physically collect or deliver. Warehouse receipt is verified separately by warehouse staff.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 18),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.coral)),
          if (!_loading && _tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No active assignments. Your dispatcher assigns pickup and delivery jobs here.',
              ),
            ),
          for (final raw in _tasks)
            Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(raw['trackingId'], style: AppTheme.sectionTitle),
                    const SizedBox(height: 8),
                    Text(
                      raw['status'] != 'OUT_FOR_DELIVERY'
                          ? raw['status'] == 'PICKED_UP'
                                ? 'Recorded pickup · driver verification required'
                                : 'Scheduled pickup · driver confirmation required'
                          : 'Out for delivery',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      raw['pickupAddress'] ??
                          raw['recipientAddress'] ??
                          'Address pending',
                    ),
                    Text(
                      '${raw['contactName']} · ${raw['contactPhone'] ?? ''}',
                    ),
                    if (raw['pickupScheduledAt'] != null)
                      Text(
                        'Confirmed appointment: ${DateFormat('MMM d · h:mm a').format(DateTime.parse(raw['pickupScheduledAt']).toLocal())}',
                      ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _confirm(Map<String, dynamic>.from(raw)),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(
                        raw['status'] != 'OUT_FOR_DELIVERY'
                            ? 'Confirm physical pickup'
                            : 'Confirm actual delivery',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
