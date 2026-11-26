import '../core/country_time.dart';
import 'direct_label_print_screen.dart';
import 'scan_screen.dart';
import 'label_preview_screen.dart';
import 'invoice_screen.dart';
import '../widgets/structured_address_field.dart';
import '../widgets/connect_declaration_form.dart';
import '../widgets/connect_payment_evidence.dart';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/service_hero.dart';
import '../providers/auth_provider.dart';
import '../models/models.dart';

typedef ConnectRequest = Future<dynamic> Function(
  String path, {
  String method,
  Map<String, dynamic>? data,
});
String connectLabel(dynamic value) => (value ?? 'Awaiting review')
    .toString()
    .split('_')
    .map((s) => s.isEmpty ? s : '${s[0]}${s.substring(1).toLowerCase()}')
    .join(' ');
String connectMoney(dynamic cents) => cents == null
    ? 'D2F quotation required'
    : '\$${((cents as num) / 100).toStringAsFixed(2)} USD';
String connectDate(dynamic value) => countryDate(value);
String connectBookingDate(
  Map<String, dynamic> booking,
  dynamic value, {
  bool destination = false,
}) {
  final parcel = booking['parcel'] as Map? ?? const {};
  final assignments = connectRows(booking['assignments']);
  final active = assignments.where(
    (a) => ['PROPOSED', 'ACCEPTED', 'CONFIRMED'].contains(a['status']),
  );
  final trip = active.isEmpty
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(active.first['trip'] as Map? ?? {});
  final zone = destination
      ? trip['destinationTimezone'] as String? ??
            suggestedTimezone('${parcel['destination']}')
      : trip['departureTimezone'] as String? ??
            booking['preferredTimezone'] as String? ??
            suggestedTimezone('${parcel['origin']}');
  return countryDate(value, timezone: zone);
}

List<Map<String, dynamic>> connectRows(dynamic rows) => (rows as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
const connectCategories = ['CLOTHING', 'PHONE', 'LAPTOP', 'DOCUMENTS', 'OTHER'];

class ConnectServiceCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool interactive;
  const ConnectServiceCard({super.key, this.onTap, this.interactive = true});
  @override
  Widget build(BuildContext context) {
    void open() {
      if (!interactive) return;
      if (onTap != null) {
        onTap!();
      } else {
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const ConnectScreen()),
        );
      }
    }

    return Semantics(
      button: interactive,
      child: GestureDetector(
        key: const ValueKey('open-d2f-connect'),
        onTap: interactive ? open : null,
        child: ServiceHero(
          image: 'connect',
          eyebrow: '04 / AIR TRAVELLER',
          title: 'D2F Connect',
          description: 'Small parcels. Verified travellers.\nEvery handover managed by D2F.',
          color: const Color(0xFF38226D),
          action: interactive ? 'Explore Air Traveller' : null,
          onAction: open,
        ),
      ),
    );
  }
}

Widget? connectNotificationDestination(String? entityType, String? entityId) {
  if (entityId == null || entityId.isEmpty) return null;
  return switch (entityType) {
    'ConnectAssignment' => ConnectScreen(focusAssignmentId: entityId),
    'ConnectTrip' => ConnectScreen(focusTripId: entityId),
    'ConnectBooking' => ConnectBookingScreen(id: entityId, request: Api.I.connect),
    _ => null,
  };
}

class ConnectScreen extends ConsumerStatefulWidget {
  final ConnectRequest? request;
  final String? focusTripId, focusAssignmentId;
  const ConnectScreen({
    super.key,
    this.request,
    this.focusTripId,
    this.focusAssignmentId,
  });
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  Map<String, dynamic> _catalog = {}, _operations = {};
  List<Map<String, dynamic>> _bookings = [], _trips = [];
  int _tab = 0;
  bool _loading = true;
  String? _error;
  bool get _staff => [
    UserRole.ADMIN,
    UserRole.STAFF,
  ].contains(ref.read(authControllerProvider).valueOrNull?.role);
  ConnectRequest get _request => widget.request ?? Api.I.connect;
  @override
  void initState() {
    super.initState();
    if (widget.focusTripId != null || widget.focusAssignmentId != null) {
      _tab = _staff ? 1 : 2;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _request('/catalog', method: 'GET'),
        _request('/bookings', method: 'GET'),
        _request('/trips', method: 'GET'),
        if (_staff) _request('/operations', method: 'GET'),
      ]);
      if (!mounted) return;
      setState(() {
        _catalog = Map<String, dynamic>.from(result[0]);
        _bookings = connectRows(result[1]);
        _trips = connectRows(result[2]);
        if (_staff) _operations = Map<String, dynamic>.from(result[3]);
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Unable to load D2F Connect. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _orderedTrips {
    final trips = _staff ? connectRows(_operations['trips']) : _trips;
    bool focused(Map<String, dynamic> trip) =>
        trip['id'] == widget.focusTripId ||
        connectRows(trip['assignments'])
            .any((a) => a['id'] == widget.focusAssignmentId);
    return [...trips.where(focused), ...trips.where((trip) => !focused(trip))];
  }

  Future<void> _openBooking(Map<String, dynamic> booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectBookingScreen(
          id: booking['id'],
          request: _request,
          staff: _staff,
          admin:
              ref.read(authControllerProvider).valueOrNull?.role ==
              UserRole.ADMIN,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _registerTrip() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ConnectTripForm(request: _request)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff4f7f5),
    appBar: AppBar(
      title: const Text('D2F Connect'),
      backgroundColor: const Color(0xfff4f7f5),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh Connect',
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const ConnectServiceCard(interactive: false),
                const SizedBox(height: 14),
                const _ConnectNotice(
                  icon: Icons.shield_outlined,
                  text: 'Your privacy travels with you. D2F manages every receiving location and handover. Personal addresses and contact details stay protected.',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry
                        in (_staff
                                ? ['Bookings', 'Trips & manifests']
                                : [
                                    'Send a parcel',
                                    'My bookings',
                                    'Travel & earn',
                                  ])
                            .asMap()
                            .entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _tab == entry.key,
                        onSelected: (_) => setState(() => _tab = entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (!_staff && _tab == 0)
                  _ConnectBookingForm(
                    catalog: _catalog,
                    request: _request,
                    onCreated: (booking) async {
                      await _openBooking(booking);
                      if (mounted) setState(() => _tab = 1);
                    },
                  ),
                if ((_staff && _tab == 0) || (!_staff && _tab == 1)) ...[
                  Text(
                    _staff
                        ? 'Connect review queue'
                        : 'Every parcel. One booking.',
                    style: AppTheme.sectionTitle,
                  ),
                  const SizedBox(height: 8),
                  if (_bookings.isEmpty)
                    const _ConnectNotice(
                      icon: Icons.inventory_2_outlined,
                      text: 'Your Connect bookings will appear here, with domestic and international progress together.',
                    ),
                  for (final b in _bookings)
                    _ConnectRecord(
                      title: b['parcel']['trackingId'],
                      subtitle:
                          '${b['parcel']['origin']} → ${b['parcel']['destination']}',
                      status: connectLabel(b['parcel']['status']),
                      onTap: () => _openBooking(b),
                    ),
                ],
                if ((_staff && _tab == 1) || (!_staff && _tab == 2)) ...[
                  Text(
                    _staff
                        ? 'Traveller operations'
                        : 'Make room for a connection.',
                    style: AppTheme.display.copyWith(fontSize: 25),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Register your flight and spare baggage. D2F verifies your trip, proposes permitted parcels and manages both ends of the journey.',
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 16),
                  if (!_staff)
                    FilledButton.icon(
                      onPressed: _registerTrip,
                      icon: const Icon(Icons.add),
                      label: const Text('Register a trip'),
                    ),
                  if (_trips.isEmpty)
                    const _ConnectNotice(
                      icon: Icons.flight_takeoff,
                      text: 'No trips yet. Trips stay under review until D2F verifies the traveller, flight and permitted contents.',
                    ),
                  for (final trip in _orderedTrips)
                    _ConnectTripTile(
                      trip: trip,
                      request: _request,
                      staff: _staff,
                      admin:
                          ref.read(authControllerProvider).valueOrNull?.role ==
                          UserRole.ADMIN,
                      locations: connectRows(_operations['locations']),
                      onChanged: _load,
                    ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'D2F Connect · Air Traveller\nAir Cargo and its AWB workflow remain in Shipping.',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
  );
}

class _ConnectBookingForm extends ConsumerStatefulWidget {
  final Map<String, dynamic> catalog;
  final ConnectRequest request;
  final Future<void> Function(Map<String, dynamic>) onCreated;
  const _ConnectBookingForm({
    required this.catalog,
    required this.request,
    required this.onCreated,
  });
  @override
  ConsumerState<_ConnectBookingForm> createState() =>
      _ConnectBookingFormState();
}

class _ConnectBookingFormState extends ConsumerState<_ConnectBookingForm> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final k in [
      'origin',
      'destination',
      'description',
      'weightKg',
      'quantity',
      'declaredValue',
      'recipientName',
      'recipientPhone',
      'recipientAddress',
      'senderCity',
      'senderAddress',
    ])
      k: TextEditingController(),
  };
  String _category = 'CLOTHING',
      _handover = 'DOMESTIC_SHIPPING',
      _delivery = 'D2F_PICKUP';
  String? _requestedTrip, _preferredZone;
  DateTime? _date;
  bool _ack = false, _busy = false;
  String? _error;
  final _requestId =
      'connect-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  @override
  void initState() {
    super.initState();
    _fields['quantity']!.text = '1';
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String key,
    String label, {
    bool numeric = false,
    bool optional = false,
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _fields[key],
      key: ValueKey('connect-$key'),
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : key.toLowerCase().contains('phone')
          ? TextInputType.phone
          : TextInputType.text,
      maxLines: lines,
      maxLength: lines > 1 ? 500 : 120,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
      onChanged: (_) => setState(() {
        _requestedTrip = null;
        if (key == 'origin') {
          _fields['senderAddress']!.clear();
          _preferredZone = suggestedTimezone(_fields['origin']!.text);
        }
        if (key == 'destination') _fields['recipientAddress']!.clear();
      }),
      validator: (v) {
        if (!optional && (v?.trim().isEmpty ?? true)) {
          return 'Please add $label';
        }
        if (numeric) {
          final n = double.tryParse(v ?? '');
          if (n == null ||
              !n.isFinite ||
              n < (key == 'declaredValue' ? 0 : .001)) {
            return 'Enter a valid amount';
          }
          if (key == 'quantity' && (n != n.roundToDouble() || n > 99)) {
            return 'Enter a whole number from 1 to 99';
          }
          if (key == 'weightKg' && n > 100) {
            return 'Connect accepts up to 100 kg, subject to trip capacity';
          }
        }
        return null;
      },
    ),
  );
  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_date == null) {
      setState(() => _error = 'Choose your earliest preferred travel date.');
      return;
    }
    if (!_ack) {
      setState(
        () => _error =
            'Confirm your parcel declaration just above the booking button.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await widget.request(
        '/bookings',
        method: 'POST',
        data: {
          for (final k in [
            'origin',
            'destination',
            'description',
            'recipientName',
            'recipientPhone',
            'recipientAddress',
            'senderCity',
            'senderAddress',
          ])
            k: _fields[k]!.text.trim(),
          'weightKg': double.parse(_fields['weightKg']!.text),
          'quantity': int.parse(_fields['quantity']!.text),
          'declaredValueMinor':
              (double.parse(_fields['declaredValue']!.text) * 100).round(),
          'category': _category,
          'handoverMode': _handover,
          'deliveryPreference': _delivery,
          'preferredLocalDate': DateFormat('yyyy-MM-dd').format(_date!),
          'preferredTimezone': _preferredZone,
          'requestedTripId': _requestedTrip,
          'restrictionsAcknowledged': true,
          'clientRequestId': _requestId,
        },
      );
      if (!mounted) return;
      await widget.onCreated(Map<String, dynamic>.from(b));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not save your booking. Retry with the same details.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final trips = connectRows(widget.catalog['trips'])
        .where(
          (t) =>
              t['origin'] == _fields['origin']!.text.trim() &&
              t['destination'] == _fields['destination']!.text.trim() &&
              (t['categories'] as List).contains(_category) &&
              (_date == null ||
                  !DateTime.parse(t['departureAt'])
                      .isBefore(countryDateStart(_date!, _preferredZone))),
        )
        .toList();
    final routes = <String, Map<String, dynamic>>{
      for (final r in [
        ...connectRows(widget.catalog['rates']),
        ...connectRows(widget.catalog['trips']),
      ])
        '${r['origin']} → ${r['destination']}': r,
    };
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Send something meaningful.',
            style: AppTheme.display.copyWith(fontSize: 27),
          ),
          const SizedBox(height: 8),
          const Text(
            'A small parcel, a verified traveller, and D2F looking after every step.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 20),
          _ConnectSection(
            number: '01',
            title: 'Choose the international route',
            child: Column(
              children: [
                const _ConnectNotice(
                  icon: Icons.route_outlined,
                  text: 'Choose the traveller’s departure city. Your own city can be different — domestic shipping bridges the distance.',
                ),
                const SizedBox(height: 14),
                if (routes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Available routes (optional)',
                      ),
                      items: routes.keys
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(r, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        final r = routes[v]!;
                        _fields['origin']!.text = r['origin'];
                        _fields['destination']!.text = r['destination'];
                        _preferredZone = suggestedTimezone(
                          _fields['origin']!.text,
                        );
                        _requestedTrip = null;
                      }),
                    ),
                  ),
                _field(
                  'origin',
                  'Departure city & country',
                  hint: 'New York, USA',
                ),
                _field(
                  'destination',
                  'Destination city & country',
                  hint: 'Lomé, Togo',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('preferred-zone-${_fields['origin']!.text}'),
                    initialValue: _preferredZone,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Departure country time zone',
                      helperText: 'Your preferred date follows the departure city’s calendar.',
                    ),
                    items:
                        (countryTimezones[countryForRoute(
                                  _fields['origin']!.text,
                                )] ??
                                <String>[])
                            .map(
                              (z) => DropdownMenuItem(value: z, child: Text(z)),
                            )
                            .toList(),
                    onChanged: (zone) => setState(() {
                      _preferredZone = zone;
                      _requestedTrip = null;
                    }),
                    validator: (zone) => zone == null
                        ? 'Choose the departure country time zone'
                        : null,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate:
                          _date ?? DateTime.now().add(const Duration(days: 7)),
                    );
                    if (d != null && mounted) {
                      setState(() {
                        _date = d;
                        _requestedTrip = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _date == null
                        ? 'Earliest preferred travel date'
                        : DateFormat('EEE, MMM d, yyyy').format(_date!),
                  ),
                ),
              ],
            ),
          ),
          _ConnectSection(
            number: '02',
            title: 'Tell us about your parcel',
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Parcel category',
                  ),
                  items: connectCategories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(connectLabel(c)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _category = v!;
                    _requestedTrip = null;
                  }),
                ),
                const SizedBox(height: 14),
                _field(
                  'description',
                  'Contents & handling details',
                  lines: 3,
                  hint: 'List every item. Include batteries, packaging and fragile contents.',
                ),
                _field('quantity', 'Number of items', numeric: true),
                _field('weightKg', 'Total actual weight (kg)', numeric: true),
                _field('declaredValue', 'Declared value (USD)', numeric: true),
                const _ConnectNotice(
                  icon: Icons.scale_outlined,
                  text: 'Actual weight counts against baggage capacity, even for items with a flat price. Documents above 500 g and exceptional goods need a D2F quotation.',
                ),
              ],
            ),
          ),
          _ConnectSection(
            number: '03',
            title: 'Sender & recipient',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sending as ${user?.fullName ?? 'your D2F account'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.phone ??
                      'Add your phone number in Account before booking.',
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 14),
                _field(
                  'senderCity',
                  'Your city & state',
                  hint: 'Dallas, Texas',
                ),
                if (!isUsRoute(_fields['destination']!.text))
                  _field('recipientName', 'Recipient full name'),
                if (!isUsRoute(_fields['destination']!.text))
                  _field('recipientPhone', 'Recipient phone'),
                if (isUsRoute(_fields['destination']!.text))
                  StructuredAddressField(
                    controller: _fields['recipientAddress']!,
                    label: 'Recipient address',
                    isUs: true,
                    includeContact: true,
                    nameController: _fields['recipientName'],
                    phoneController: _fields['recipientPhone'],
                    onChanged: () => setState(() {}),
                  )
                else
                  _field('recipientAddress', 'Recipient address', lines: 2),
                DropdownButtonFormField<String>(
                  initialValue: _delivery,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'At the destination',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'D2F_PICKUP',
                      child: Text('Collect from D2F'),
                    ),
                    DropdownMenuItem(
                      value: 'DELIVERY_REQUEST',
                      child: Text('Request delivery · D2F will confirm'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _delivery = v!),
                ),
              ],
            ),
          ),
          _ConnectSection(
            number: '04',
            title: 'Get your parcel to D2F',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final option in [
                  (
                    'DOMESTIC_SHIPPING',
                    'Domestic Shipping',
                    'Ship with a domestic carrier to an approved D2F receiving location.',
                  ),
                  (
                    'DROP_OFF',
                    'Drop off at D2F',
                    'Bring your parcel to the approved receiving location.',
                  ),
                  (
                    'PICKUP',
                    'Request D2F pickup',
                    'D2F reviews availability and coordinates your collection.',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => setState(() => _handover = option.$1),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _handover == option.$1
                              ? const Color(0xffe3f0eb)
                              : const Color(0xfff6f8f7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _handover == option.$1
                                ? const Color(0xff327564)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _handover == option.$1
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.$2,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    option.$3,
                                    style: AppTheme.caption.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_handover != 'DROP_OFF')
                  if (isUsRoute(_fields['origin']!.text))
                    StructuredAddressField(
                      controller: _fields['senderAddress']!,
                      label: 'Sender address',
                      isUs: true,
                      includeContact: true,
                      onChanged: () => setState(() {}),
                    )
                  else
                    _field(
                      'senderAddress',
                      _handover == 'PICKUP'
                          ? 'Private pickup address'
                          : 'Private return address',
                      lines: 2,
                    ),
                const _ConnectNotice(
                  icon: Icons.lock_outline,
                  text: 'D2F shares an approved receiving address after review. Your private address is never shared with the traveller. A missing receiving location goes to admin review.',
                ),
              ],
            ),
          ),
          if (trips.isNotEmpty)
            _ConnectSection(
              number: '05',
              title: 'Trip preference · optional',
              child: DropdownButtonFormField<String>(
                key: ValueKey('trip-$_requestedTrip-${trips.length}'),
                initialValue: _requestedTrip,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Request a trip'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Let D2F find a suitable traveller'),
                  ),
                  ...trips.map(
                    (t) => DropdownMenuItem<String>(
                      value: t['id'],
                      child: Text(
                        '${connectTripDate(t)} · ${t['remainingKg']} kg',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _requestedTrip = v),
              ),
            ),
          const _ConnectNotice(
            icon: Icons.receipt_long_outlined,
            text: 'D2F reviews contents and quotes the international fee and domestic shipping separately. You accept the final price before payment. A trip preference is not a confirmed assignment.',
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            key: const ValueKey('connect-declaration'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ack,
            onChanged: _busy ? null : (v) => setState(() => _ack = v ?? false),
            title: const Text(
              'I have accurately declared every item and agree to D2F verification and shipping restrictions.',
              style: TextStyle(fontSize: 12, height: 1.5),
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
          FilledButton.icon(
            key: const ValueKey('connect-submit-booking'),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Register Connect booking'),
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectBookingScreen extends StatefulWidget {
  final String id;
  final ConnectRequest request;
  final bool staff, admin;
  const ConnectBookingScreen({
    super.key,
    required this.id,
    required this.request,
    this.staff = false,
    this.admin = false,
  });
  @override
  State<ConnectBookingScreen> createState() => _ConnectBookingScreenState();
}

class _ConnectBookingScreenState extends State<ConnectBookingScreen> {
  Map<String, dynamic>? _booking;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.request('/bookings/${widget.id}', method: 'GET');
      if (mounted) {
        setState(() {
          _booking = Map<String, dynamic>.from(b);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _action(
    String action,
    String title, {
    List<ConnectInput> fields = const [],
    Map<String, dynamic> fixed = const {},
    String? message,
    Map<String, dynamic>? supplied,
  }) async {
    final data =
        supplied ??
        await connectActionDialog(context, title, fields, message: message);
    if (data == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.request(
        '/bookings/${widget.id}/$action',
        method: 'POST',
        data: {...fixed, ...data},
      );
      if (!mounted) return;
      if (action == 'authorize-handover') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('D2F collection code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  result['code'],
                  style: const TextStyle(
                    fontSize: 32,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Expires ${connectDate(result['expiresAt'])}. Share in person with the assigned traveller after checking the parcel. Never send it to the customer.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _button(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: OutlinedButton(onPressed: _busy ? null : onTap, child: Text(label)),
  );
  @override
  Widget build(BuildContext context) {
    final b = _booking;
    final p = b?['parcel'];
    final assignment = b == null
        ? null
        : connectRows(b['assignments'])
              .where(
                (a) =>
                    ['PROPOSED', 'ACCEPTED', 'CONFIRMED'].contains(a['status']),
              )
              .firstOrNull;
    final flight = [
      assignment?['trip']?['airline'],
      assignment?['trip']?['flightNumber'],
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    final receivedParcel = widget.staff && p is Map && b?['originReceivedAt'] != null
        ? Parcel.fromJson({
            ...Map<String, dynamic>.from(p),
            'warehouseReceivedAt': b?['originReceivedAt'],
            'verifiedWeightKg': b?['verifiedWeightKg'],
          })
        : null;
    return Scaffold(
      backgroundColor: const Color(0xfff4f7f5),
      appBar: AppBar(
        title: const Text('Connect booking'),
        actions: [
          if (receivedParcel != null) ...[
            IconButton(
              tooltip: 'Shipping labels PDF',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LabelPreviewScreen(parcel: receivedParcel)),
              ),
              icon: const Icon(Icons.description_outlined),
            ),
            IconButton(
              tooltip: 'Direct label printing',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DirectLabelPrintScreen(parcel: receivedParcel)),
              ),
              icon: const Icon(Icons.print_outlined),
            ),
          ],
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: b == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xff123f50),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'D2F CONNECT · AIR TRAVELLER',
                          style: TextStyle(
                            color: Color(0xffb4e7d6),
                            fontSize: 10,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          p['trackingId'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${p['origin']} → ${p['destination']}',
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          connectLabel(p['status']),
                          style: const TextStyle(
                            color: Color(0xffc5f0dd),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ConnectSection(
                    number: '01',
                    title: 'Parcel & recipient',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ConnectLine('Contents', p['notes'] ?? ''),
                        _ConnectLine(
                          'Category / quantity',
                          '${connectLabel(b['category'])} · ${b['quantity']} items',
                        ),
                        _ConnectLine(
                          'Declared / verified weight',
                          '${p['weightKg']} kg / ${b['verifiedWeightKg'] ?? 'Awaiting verification'}',
                        ),
                        _ConnectLine(
                          'Declared value',
                          connectMoney(b['declaredValueMinor']),
                        ),
                        _ConnectLine('Recipient', p['recipientName']),
                        _ConnectLine(
                          'Recipient phone',
                          p['recipientPhone'] ?? '',
                        ),
                        _ConnectLine(
                          'Recipient address',
                          p['recipientAddress'] ?? '',
                        ),
                        _ConnectLine(
                          'Delivery preference',
                          connectLabel(b['deliveryPreference']),
                        ),
                        _ConnectLine(
                          'Preferred travel',
                          countryDate(
                            b['preferredDate'],
                            timezone:
                                b['preferredTimezone'] as String? ??
                                suggestedTimezone('${b['parcel']['origin']}'),
                          ),
                        ),
                        if (widget.staff) ...[
                          _ConnectLine(
                            'Sender',
                            p['customer']?['displayName'] ?? '',
                          ),
                          _ConnectLine(
                            'Sender contact',
                            '${p['customer']?['phone'] ?? ''} · ${p['customer']?['email'] ?? ''}',
                          ),
                          _ConnectLine('Sender city', b['senderCity']),
                          _ConnectLine(
                            'Private sender address',
                            b['senderAddress'] ?? 'Not required',
                          ),
                        ],
                      ],
                    ),
                  ),
                  _ConnectSection(
                    number: '02',
                    title: 'Two stages. One booking.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'DOMESTIC · CUSTOMER TO D2F',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ConnectLine(
                          'Handover',
                          connectLabel(b['handoverMode']),
                        ),
                        _ConnectLine(
                          'Domestic progress',
                          connectLabel(b['domesticStatus']),
                        ),
                        if (b['domesticTrackingNumber'] != null) ...[
                          _ConnectLine('Carrier', b['domesticCarrier']),
                          _ConnectLine(
                            'Carrier tracking',
                            b['domesticTrackingNumber'],
                          ),
                        ],
                        if (b['receivingLocation'] != null)
                          _ConnectLine(
                            'Approved receiving location',
                            '${b['receivingLocation']['name']}\n${b['receivingLocation']['address']}',
                          )
                        else
                          const _ConnectNotice(
                            icon: Icons.pending_actions,
                            text: 'D2F is reviewing the receiving location. Wait for the approved address and instructions before sending anything.',
                          ),
                        if (b['domesticLabelUrl'] != null)
                          TextButton.icon(
                            onPressed: () async {
                              final uri = Uri.tryParse(b['domesticLabelUrl']);
                              if (uri != null && uri.scheme == 'https') {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            icon: const Icon(Icons.download),
                            label: const Text('Open domestic shipping label'),
                          ),
                        if (!widget.staff &&
                            b['domesticStatus'] == 'LABEL_READY')
                          _button(
                            'Confirm domestic carrier dispatch',
                            () => _action(
                              'domestic-dispatched',
                              'Confirm carrier dispatch',
                              message: 'Confirm only after you have handed this parcel to the domestic carrier.',
                            ),
                          ),
                        const Divider(height: 28),
                        const Text(
                          'INTERNATIONAL · D2F TO DESTINATION',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ConnectLine(
                          'Requested trip',
                          b['requestedTripId'] == null
                              ? 'Let D2F match a traveller'
                              : 'Customer trip preference recorded',
                        ),
                        _ConnectLine(
                          'Actual assignment',
                          assignment == null
                              ? 'D2F review in progress'
                              : '${connectLabel(assignment['status'])} · ${connectTripDate(Map<String, dynamic>.from(assignment['trip']))}',
                        ),
                        if (flight.isNotEmpty)
                          _ConnectLine('Assigned flight', flight),
                        if (widget.staff && p['location']?['name'] != null)
                          _ConnectLine('Current facility', p['location']['name']),
                        _ConnectLine(
                          'Traveller collection',
                          b['collectedAt'] == null
                              ? 'Awaiting verified D2F handover'
                              : connectBookingDate(b, b['collectedAt']),
                        ),
                        _ConnectLine(
                          'Destination team receipt',
                          b['destinationReceivedAt'] == null
                              ? 'Awaiting confirmed arrival'
                              : connectBookingDate(
                                  b,
                                  b['destinationReceivedAt'],
                                  destination: true,
                                ),
                        ),
                      ],
                    ),
                  ),
                  _ConnectSection(
                    number: '02A',
                    title: 'Contents declaration & compliance',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Customer declaration and D2F staff inspection are separate mandatory steps.',
                        ),
                        if (connectRows(b['declarations']).isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'The sender must open this booking in their customer account and complete the contents declaration before staff can approve it. Staff cannot acknowledge on their behalf.',
                            ),
                          ),
                        for (final d in connectRows(b['declarations'])) ...[
                          const Divider(height: 24),
                          _ConnectLine('Legal name', d['legalName']),
                          _ConnectLine('Itemized declaration', d['contents']),
                          _ConnectLine(
                            'Acknowledged',
                            connectBookingDate(b, d['createdAt']),
                          ),
                          _ConnectLine('Terms version', d['termsVersion']),
                          const Text(
                            'All five declarations and electronic acknowledgment recorded.',
                          ),
                        ],
                        _ConnectLine(
                          'Separate staff review',
                          b['contentsVerifiedAt'] == null
                              ? 'Pending D2F inspection'
                              : 'Recorded · ${connectBookingDate(b, b['contentsVerifiedAt'])}',
                        ),
                        if (!widget.staff &&
                            b['originReceivedAt'] == null &&
                            b['collectedAt'] == null &&
                            !['REJECTED', 'CANCELLED'].contains(p['status']))
                          _button(
                            'Complete / renew contents declaration',
                            () async {
                              final saved = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ConnectDeclarationForm(
                                    bookingId: widget.id,
                                    contents: p['notes'] ?? '',
                                    request: widget.request,
                                  ),
                                ),
                              );
                              if (saved == true) await _load();
                            },
                          ),
                      ],
                    ),
                  ),
                  _ConnectSection(
                    number: '03',
                    title: 'Your fees & payment',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ConnectLine(
                          'International traveller fee',
                          connectMoney(b['internationalFeeMinor']),
                        ),
                        _ConnectLine(
                          'Domestic shipping cost',
                          connectMoney(b['domesticCostMinor']),
                        ),
                        if (b['internationalFeeMinor'] != null &&
                            b['domesticCostMinor'] != null)
                          _ConnectLine(
                            'Total',
                            connectMoney(
                              b['internationalFeeMinor'] +
                                  b['domesticCostMinor'],
                            ),
                          ),
                        _ConnectLine(
                          'Quote',
                          b['quoteAcceptedAt'] == null
                              ? 'Awaiting your acceptance'
                              : 'Accepted · price saved',
                        ),
                        _ConnectLine(
                          'D2F payment instructions',
                          b['paymentInstructions'] ?? 'D2F will provide verified payment instructions here. Wait for these instructions before paying.',
                        ),
                        if (receivedParcel != null)
                          OutlinedButton.icon(
                            onPressed: () => openIntakeReceipt(context, receivedParcel),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Print or share intake receipt'),
                          ),
                        if (b['quoteAcceptedAt'] != null) InvoiceButton(type: 'connect', id: widget.id),
                        _ConnectLine(
                          'Payment',
                          b['payment'] == null
                              ? (connectRows(b['paymentSubmissions'])
                                        .any((s) => s['status'] == 'PENDING')
                                    ? 'Evidence submitted · awaiting D2F verification'
                                    : 'Awaiting payment evidence and D2F verification')
                              : 'Confirmed by D2F',
                        ),
                        for (final submission in connectRows(
                          b['paymentSubmissions'],
                        )) ...[
                          const Divider(height: 20),
                          _ConnectLine(
                            'Payment evidence',
                            '${connectLabel(submission['method'])} · ${connectLabel(submission['status'])}',
                          ),
                          if (submission['transactionId'] != null)
                            _ConnectLine(
                              'Transaction ID',
                              submission['transactionId'],
                            ),
                          if (submission['reviewNote'] != null)
                            _ConnectLine(
                              'D2F review',
                              submission['reviewNote'],
                            ),
                          _button(
                            'View payment screenshot / receipt',
                            () => showConnectPaymentImage(
                              context,
                              widget.id,
                              submission['id'],
                            ),
                          ),
                          if (widget.admin && submission['status'] == 'PENDING')
                            _button(
                              'Reject evidence / request correction',
                              () => _action(
                                'payment-submissions/${submission['id']}/reject',
                                'Request corrected payment evidence',
                                fields: const [
                                  ConnectInput(
                                    'note',
                                    'Reason and correction needed',
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (!widget.staff &&
                            b['quoteAcceptedAt'] != null &&
                            b['paymentInstructions'] != null &&
                            b['payment'] == null &&
                            !connectRows(b['paymentSubmissions'])
                                .any((s) => s['status'] == 'PENDING'))
                          _button(
                            'Approve instructions & submit payment evidence',
                            () async {
                              final saved = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ConnectPaymentEvidenceForm(
                                    bookingId: widget.id,
                                    instructions: b['paymentInstructions'],
                                    version:
                                        b['paymentInstructionsVersion'] ?? 0,
                                  ),
                                ),
                              );
                              if (saved == true) await _load();
                            },
                          ),
                        if (!widget.staff &&
                            b['quoteAcceptedAt'] == null &&
                            b['internationalFeeMinor'] != null &&
                            b['domesticCostMinor'] != null)
                          _button(
                            'Accept quotation',
                            () => _action(
                              'accept-quote',
                              'Accept the quoted fees',
                              fixed: {
                                'totalMinor':
                                    b['internationalFeeMinor'] +
                                    b['domesticCostMinor'],
                              },
                              message:
                                  'Agree to ${connectMoney(b['internationalFeeMinor'] + b['domesticCostMinor'])}, including the international fee and domestic cost shown above. D2F records payment after funds are verified.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.staff)
                    _ConnectSection(
                      number: '04',
                      title: 'D2F operations',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!b.containsKey('collectedAt') ||
                              b['collectedAt'] == null) ...[
                            _button(
                              'Verify contents & actual weight',
                              () => _action(
                                'review',
                                'D2F contents & compliance review',
                                fields: const [
                                  ConnectInput(
                                    'verifiedWeightKg',
                                    'Verified actual weight (kg)',
                                    numeric: true,
                                  ),
                                  ConnectInput(
                                    'declarationReviewed',
                                    'I reviewed the current customer declaration and identity.',
                                    checkbox: true,
                                  ),
                                  ConnectInput(
                                    'inspectionConfirmed',
                                    'I physically inspected and verified the declared contents.',
                                    checkbox: true,
                                  ),
                                  ConnectInput(
                                    'restrictionsChecked',
                                    'I checked origin, transit, destination and carrier restrictions and required documents.',
                                    checkbox: true,
                                  ),
                                  ConnectInput(
                                    'note',
                                    'Staff inspection findings and verification evidence',
                                  ),
                                ],
                                fixed: const {'approved': true},
                              ),
                            ),
                            _button('Propose a matching traveller', () async {
                              try {
                                final matches = connectRows(
                                  await widget.request(
                                    '/bookings/${widget.id}/matches',
                                    method: 'GET',
                                  ),
                                );
                                if (!context.mounted) return;
                                if (matches.isEmpty) {
                                  setState(
                                    () => _error = 'No compatible trip has enough capacity. Keep this booking under review.',
                                  );
                                  return;
                                }
                                _action(
                                  'assign',
                                  'Propose traveller assignment',
                                  fields: [
                                    ConnectInput(
                                      'tripId',
                                      'Compatible approved trip',
                                      options: {
                                        for (final t in matches)
                                          t['id']:
                                              '${t['origin']} → ${t['destination']} · ${connectTripDate(t)} · ${t['remainingKg']} kg',
                                      },
                                    ),
                                  ],
                                );
                              } catch (e) {
                                if (mounted) setState(() => _error = '$e');
                              }
                            }),
                            if (assignment?['status'] == 'ACCEPTED')
                              _button(
                                'Confirm accepted assignment',
                                () => _action(
                                  'confirm-assignment',
                                  'Confirm the traveller assignment',
                                ),
                              ),
                            if (assignment != null)
                              _button(
                                'Remove assignment before collection',
                                () => _action(
                                  'unassign',
                                  'Remove traveller assignment',
                                  fields: const [
                                    ConnectInput('note', 'Reason for removal'),
                                  ],
                                ),
                              ),
                            if (widget.admin && b['payment'] == null)
                              _button(
                                'Provide payment instructions',
                                () => _action(
                                  'payment-instructions',
                                  'Verified D2F payment instructions',
                                  fields: const [
                                    ConnectInput(
                                      'instructions',
                                      'D2F payment channel, account and reference instructions',
                                    ),
                                  ],
                                ),
                              ),
                            if (widget.admin && b['quoteAcceptedAt'] == null)
                              _button(
                                'Set final quotation',
                                () => _action(
                                  'quote',
                                  'Set the final D2F quotation',
                                  fields: const [
                                    ConnectInput(
                                      'internationalFeeMinor',
                                      'International fee (USD)',
                                      money: true,
                                    ),
                                    ConnectInput(
                                      'domesticCostMinor',
                                      'Domestic shipping (USD)',
                                      money: true,
                                    ),
                                    ConnectInput('note', 'Quotation details'),
                                  ],
                                ),
                              ),
                            if (widget.admin &&
                                b['quoteAcceptedAt'] != null &&
                                b['payment'] == null)
                              _button(
                                'Record verified payment',
                                () => _action(
                                  'payment',
                                  'Confirm funds received',
                                  fields: const [
                                    ConnectInput(
                                      'reference',
                                      'Unique payment reference',
                                    ),
                                    ConnectInput(
                                      'amountMinor',
                                      'Total received (USD)',
                                      money: true,
                                    ),
                                  ],
                                ),
                              ),
                            if (b['handoverMode'] == 'DOMESTIC_SHIPPING' &&
                                b['originReceivedAt'] == null)
                              _button(
                                'Add domestic label & tracking',
                                () => _action(
                                  'domestic',
                                  'Domestic carrier label',
                                  fields: const [
                                    ConnectInput(
                                      'carrier',
                                      'Carrier · UPS, FedEx, USPS or other',
                                    ),
                                    ConnectInput(
                                      'trackingNumber',
                                      'Domestic carrier tracking number',
                                    ),
                                    ConnectInput(
                                      'labelUrl',
                                      'Secure HTTPS label link',
                                    ),
                                  ],
                                ),
                              ),
                            if (b['originReceivedAt'] == null)
                              _button(
                                'Confirm receiving-location intake',
                                () => _action(
                                  'receive',
                                  'Confirm parcel physically received',
                                  fields: const [
                                    ConnectInput(
                                      'note',
                                      'Inspection and package condition',
                                    ),
                                    ConnectInput(
                                      'physicalPackages',
                                      'Multiple packages: verified kg, comma separated',
                                      optional: true,
                                      packageWeights: true,
                                    ),
                                  ],
                                ),
                              ),
                            if (b['originReceivedAt'] != null)
                              _button(
                                'Authorize collection & issue code',
                                () => _action(
                                  'authorize-handover',
                                  'Authorize traveller handover',
                                  message: 'Verify the parcel and assigned traveller in person. The single-use code expires in 10 minutes.',
                                ),
                              ),
                          ],
                          if (b['collectedAt'] != null &&
                              b['destinationReceivedAt'] == null)
                            _button('Confirm destination team receipt', () async {
                              final selection =
                                  await showDialog<Map<String, dynamic>>(
                                    context: context,
                                    builder: (_) => _ConnectFacilityDialog(
                                      request: widget.request,
                                      path:
                                          '/bookings/${widget.id}/destination-locations',
                                      requiresNote: true,
                                    ),
                                  );
                              if (selection != null && mounted) {
                                await _action(
                                  'destination-received',
                                  'Confirm destination team receipt',
                                  supplied: selection,
                                );
                              }
                            }),
                          if (p['status'] == 'ARRIVED_DESTINATION')
                            _button(
                              'Mark ready for recipient handover',
                              () => _action(
                                'ready',
                                'Confirm ready for recipient handover',
                              ),
                            ),
                          if (p['status'] == 'READY_FOR_PICKUP')
                            _button(
                              'Confirm final delivery',
                              () => _action(
                                'deliver',
                                'Confirm actual delivery',
                                fields: const [
                                  ConnectInput(
                                    'recipientName',
                                    'Verified recipient name',
                                  ),
                                  ConnectInput(
                                    'evidence',
                                    'Identity check & delivery proof reference',
                                  ),
                                ],
                                fixed: const {'confirmed': true},
                              ),
                            ),
                        ],
                      ),
                    ),
                  Text(
                    'Confirmed tracking events',
                    style: AppTheme.sectionTitle,
                  ),
                  const SizedBox(height: 8),
                  for (final e in connectRows(p['events']).reversed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 20,
                            color: Color(0xff327564),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  connectLabel(e['status']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(e['note'] ?? '', style: AppTheme.caption),
                                const SizedBox(height: 4),
                                Text(
                                  connectBookingDate(
                                    b,
                                    e['createdAt'],
                                    destination: [
                                      'ARRIVED_DESTINATION',
                                      'ARRIVED_LOME',
                                      'READY_FOR_PICKUP',
                                      'DELIVERED',
                                    ].contains(e['status']),
                                  ),
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.coral),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ConnectTripForm extends StatefulWidget {
  final ConnectRequest request;
  const _ConnectTripForm({required this.request});
  @override
  State<_ConnectTripForm> createState() => _ConnectTripFormState();
}

class _ConnectTripFormState extends State<_ConnectTripForm> {
  final _form = GlobalKey<FormState>();
  final _flight = TextEditingController();
  final _capacity = TextEditingController();
  final _categories = <String>{'CLOTHING', 'DOCUMENTS'};
  final _countries = <String?>[null, null];
  final _cities = <String?>[null, null];
  final _zones = <String?>[null, null];
  final _times = <DateTime?>[null, null];
  final _occurrences = <String?>[null, null];
  String? _airline;
  bool _ack = false, _busy = false;
  String? _error;

  static const _citiesByCountry = {
    'United States': ['Omaha, NE', 'New York, NY', 'Atlanta, GA', 'Boston, MA', 'Miami, FL', 'Washington, DC', 'Chicago, IL', 'Dallas, TX', 'Houston, TX', 'Denver, CO', 'Phoenix, AZ', 'Los Angeles, CA', 'San Francisco, CA', 'Seattle, WA', 'Anchorage, AK', 'Honolulu, HI'],
    'France': ['Paris', 'Lyon', 'Marseille', 'Nice', 'Toulouse', 'Bordeaux'],
    'Belgium': ['Brussels', 'Antwerp', 'Charleroi', 'Liège'],
    'Togo': ['Lomé', 'Kara', 'Sokodé'],
    'Benin': ['Cotonou', 'Porto-Novo', 'Parakou'],
    'Burkina Faso': ['Ouagadougou', 'Bobo-Dioulasso'],
    'Gabon': ['Libreville', 'Port-Gentil'],
    'Ghana': ['Accra', 'Kumasi', 'Tamale'],
    'Senegal': ['Dakar', 'Saint-Louis'],
    'Nigeria': ['Lagos', 'Abuja', 'Kano', 'Port Harcourt'],
    'Côte d’Ivoire': ['Abidjan', 'Bouaké', 'Yamoussoukro'],
  };
  static const _airlines = ['Air Belgium', 'Air Burkina', 'Air Côte d’Ivoire', 'Air France', 'Air Senegal', 'American Airlines', 'ASKY Airlines', 'Brussels Airlines', 'Delta Air Lines', 'Ethiopian Airlines', 'Kenya Airways', 'KLM', 'Lufthansa', 'Royal Air Maroc', 'Turkish Airlines', 'United Airlines'];

  String _route(int index) =>
      '${_cities[index]}, ${_countries[index] == 'United States' ? 'USA' : _countries[index]}';

  @override
  void dispose() {
    _flight.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<String?> _choose(String title, Iterable<String> options, {bool allowOther = false}) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _TripOptionPicker(title: title, options: options, allowOther: allowOther),
      );

  Future<void> _pickTime(int index) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      helpText: index == 0 ? 'Departure date' : 'Arrival date',
      firstDate: DateUtils.dateOnly(now).subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 372)),
      initialDate: _times[index] ?? now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      helpText: index == 0 ? 'Departure city time' : 'Arrival city time',
      initialTime: _times[index] == null ? const TimeOfDay(hour: 12, minute: 0) : TimeOfDay.fromDateTime(_times[index]!),
    );
    if (time != null && mounted) setState(() {
      _times[index] = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _occurrences[index] = null;
    });
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    if ([..._cities, ..._zones, ..._times, _airline].contains(null) || !_ack || _categories.isEmpty) {
      setState(() => _error = 'Choose both routes, time zones, travel dates, an airline and at least one category. Confirm the verification requirements.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final saved = await widget.request('/trips', method: 'POST', data: {
        'registrationVersion': 2,
        'origin': _route(0),
        'destination': _route(1),
        'airline': _airline,
        'flightNumber': _flight.text.trim().toUpperCase(),
        'capacityKg': double.parse(_capacity.text),
        'departureLocal': DateFormat("yyyy-MM-dd'T'HH:mm").format(_times[0]!),
        'departureTimezone': _zones[0],
        if (_occurrences[0] != null) 'departureOccurrence': _occurrences[0],
        'arrivalLocal': DateFormat("yyyy-MM-dd'T'HH:mm").format(_times[1]!),
        'destinationTimezone': _zones[1],
        if (_occurrences[1] != null) 'arrivalOccurrence': _occurrences[1],
        'categories': _categories.toList(),
        'complianceAcknowledged': true,
      });
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
        _ConnectTripVerification(tripId: saved['id'] as String, documents: const [])));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _select(String label, String? value, VoidCallback? onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          onPressed: onTap,
          child: Row(children: [Expanded(child: Text(value == null ? label : '$label · $value')), const Icon(Icons.expand_more)]),
        ),
      );

  Widget _location(int index, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _select('$label country', _countries[index], () async {
        final country = await _choose('$label country', countryTimezones.keys);
        if (country != null && mounted && country != _countries[index]) setState(() {
          _countries[index] = country;
          _cities[index] = null;
          _zones[index] = countryTimezones[country]!.length == 1 ? countryTimezones[country]!.first : null;
          _occurrences[index] = null;
        });
      }),
      _select('$label city', _cities[index], _countries[index] == null ? null : () async {
        final city = await _choose('$label city', _citiesByCountry[_countries[index]] ?? const [], allowOther: true);
        if (city != null && mounted) setState(() {
          _cities[index] = city;
          _zones[index] = suggestedTimezone(_route(index));
          _occurrences[index] = null;
        });
      }),
      _select('$label time zone', _zones[index], _countries[index] == null ? null : () async {
        final zone = await _choose('$label time zone', countryTimezones[_countries[index]]!);
        if (zone != null && mounted) setState(() { _zones[index] = zone; _occurrences[index] = null; });
      }),
      OutlinedButton.icon(
        onPressed: () => _pickTime(index),
        icon: const Icon(Icons.calendar_month),
        label: Text(_times[index] == null ? '$label date & time (required)' : '$label · ${DateFormat('MMM d, y · h:mm a').format(_times[index]!)}'),
      ),
      const SizedBox(height: 16),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Register your trip')),
    body: SafeArea(child: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const _ConnectNotice(icon: Icons.verified_user_outlined,
            text: 'Register your travel details. Next, upload your identity and ticket for D2F verification.'),
          const SizedBox(height: 16),
          _location(0, 'Departure'),
          _location(1, 'Arrival'),
          _select('Airline', _airline, () async {
            final value = await _choose('Airline', _airlines, allowOther: true);
            if (value != null && mounted) setState(() => _airline = value);
          }),
          TextFormField(
            controller: _flight,
            maxLength: 16,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Flight number', hintText: 'e.g. AF 864'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Enter your flight number' : null,
          ),
          TextFormField(
            controller: _capacity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Available baggage capacity', suffixText: 'kg'),
            validator: (value) {
              final n = double.tryParse(value ?? '');
              return n == null || !n.isFinite || n < .1 || n > 100 ? 'Enter capacity from 0.1 to 100 kg' : null;
            },
          ),
          ExpansionTile(
            title: const Text('Daylight-saving adjustment'),
            children: [
              for (final (index, label) in [(0, 'Departure'), (1, 'Arrival')])
                DropdownButtonFormField<String>(
                  key: ValueKey('$index-${_times[index]}-${_zones[index]}'),
                  initialValue: _occurrences[index],
                  isExpanded: true,
                  decoration: InputDecoration(labelText: '$label if the local clock time occurs twice'),
                  items: const [
                    DropdownMenuItem(value: 'EARLIER', child: Text('First occurrence')),
                    DropdownMenuItem(value: 'LATER', child: Text('Second occurrence')),
                  ],
                  onChanged: (value) => setState(() => _occurrences[index] = value),
                ),
            ],
          ),
          const Text('Categories you are willing to carry', style: AppTheme.sectionTitle),
          Wrap(spacing: 8, children: [
            for (final c in connectCategories)
              FilterChip(label: Text(connectLabel(c)), selected: _categories.contains(c),
                onSelected: (value) => setState(() { value ? _categories.add(c) : _categories.remove(c); })),
          ]),
          CheckboxListTile(
            value: _ack,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) => setState(() => _ack = value ?? false),
            title: const Text('I agree to identity, ticket, baggage and transport eligibility verification.'),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.coral)),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Submitting…' : 'Submit trip')),
        ],
      ),
    )),
  );
}

class _TripOptionPicker extends StatefulWidget {
  final String title;
  final Iterable<String> options;
  final bool allowOther;
  const _TripOptionPicker({required this.title, required this.options, required this.allowOther});

  @override
  State<_TripOptionPicker> createState() => _TripOptionPickerState();
}

class _TripOptionPickerState extends State<_TripOptionPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.options.where((v) => v.toLowerCase().contains(_query.toLowerCase())).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .65,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: TextField(
            decoration: InputDecoration(labelText: 'Search ${widget.title.toLowerCase()}', prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() => _query = value.trim()),
            maxLength: 80,
          )),
          Expanded(child: ListView(children: [
            for (final value in options) ListTile(title: Text(value), onTap: () => Navigator.pop(context, value)),
            if (options.isEmpty) const ListTile(title: Text('No matching options')),
            if (widget.allowOther && _query.isNotEmpty && !options.any((v) => v.toLowerCase() == _query.toLowerCase()))
              ListTile(title: Text('Use “$_query”'), onTap: () => Navigator.pop(context, _query)),
          ])),
        ]),
      ),
    );
  }
}

class _ConnectTripVerification extends StatefulWidget {
  final String tripId;
  final List<Map<String, dynamic>> documents;
  const _ConnectTripVerification({required this.tripId, required this.documents});

  @override
  State<_ConnectTripVerification> createState() => _ConnectTripVerificationState();
}

class _ConnectTripVerificationState extends State<_ConnectTripVerification> {
  late final _uploaded = widget.documents.map((row) => row['kind']).toSet();
  bool _busy = false;
  String? _error;

  Future<void> _select(String kind) async {
    setState(() { _busy = true; _error = null; });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final contentType = switch (file.name.toLowerCase().split('.').last) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => null,
      };
      if (contentType == null || await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('Choose a JPEG, PNG or WebP image up to 4 MB.');
      }
      await Api.I.uploadConnectTripDocument(widget.tripId, kind, await file.readAsBytes(), contentType);
      if (mounted) setState(() => _uploaded.add(kind));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trip verification')),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_uploaded.length == 2 ? 'Documents submitted for review' : 'Upload verification documents', style: AppTheme.sectionTitle),
        const Text('D2F reviews your identity, ticket, baggage allowance and transport eligibility before approval. Documents are visible only to you and authorized D2F reviewers.'),
        const SizedBox(height: 16),
        for (final (kind, label) in [('IDENTITY', 'Identity document'), ('TICKET', 'Flight ticket with baggage allowance')])
          ListTile(
            title: Text(label),
            subtitle: Text(_uploaded.contains(kind) ? 'Uploaded · tap to replace' : 'Upload image'),
            leading: Icon(_uploaded.contains(kind) ? Icons.check_circle_outline : Icons.upload_file),
            onTap: _busy ? null : () => _select(kind),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.coral)),
        FilledButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(_uploaded.length == 2 ? 'Done' : 'Finish later')),
      ],
    )),
  );
}

class _ConnectTripTile extends StatelessWidget {
  final Map<String, dynamic> trip;
  final ConnectRequest request;
  final bool staff, admin;
  final List<Map<String, dynamic>> locations;
  final Future<void> Function() onChanged;
  const _ConnectTripTile({
    required this.trip,
    required this.request,
    required this.staff,
    required this.admin,
    required this.locations,
    required this.onChanged,
  });
  Future<void> _run(
    BuildContext context,
    String path,
    String title, {
    List<ConnectInput> fields = const [],
    Map<String, dynamic> fixed = const {},
    String method = 'POST',
  }) async {
    final data = await connectActionDialog(context, title, fields);
    if (data == null) return;
    try {
      await request(path, method: method, data: {...fixed, ...data});
      await onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _scanPackage(
    BuildContext context,
    Map<String, dynamic> assignment,
  ) async {
    final trackingId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen(returnTracking: true)),
    );
    if (trackingId == null || !context.mounted) return;
    try {
      final result = await request(
        '/assignments/${assignment['id']}/package-receipts',
        method: 'POST',
        data: {'trackingId': trackingId},
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['duplicate'] == true
                  ? 'Package already scanned.'
                  : '${result['scanned']} of ${result['expected']} packages scanned.',
            ),
          ),
        );
      }
      await onChanged();
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _selectFacility(BuildContext context) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ConnectFacilityDialog(
        request: request,
        path: '/trips/${trip['id']}/receiving-locations',
      ),
    );
    if (data == null || !context.mounted) return;
    try {
      await request(
        '/trips/${trip['id']}/receiving-location',
        method: 'PATCH',
        data: data,
      );
      await onChanged();
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.flight_takeoff, color: Color(0xff327564)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${trip['origin']} → ${trip['destination']}',
                style: AppTheme.sectionTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ConnectLine('Departure', connectTripDate(trip)),
        if (trip['arrivalAt'] != null)
          _ConnectLine(
            'Arrival',
            countryDate(
              trip['arrivalAt'],
              timezone: trip['destinationTimezone'] as String?,
            ),
          ),
        if (trip['flightNumber'] != null)
          _ConnectLine(
            'Flight',
            [trip['airline'], trip['flightNumber']].whereType<String>().join(' '),
          ),
        if (!staff &&
            trip['airline'] != null &&
            ['PENDING_REVIEW', 'REJECTED'].contains(trip['status']))
          OutlinedButton(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => _ConnectTripVerification(
                    tripId: trip['id'] as String,
                    documents: connectRows(trip['verificationDocuments']),
                  ),
                ),
              );
              await onChanged();
            },
            child: Text(
              connectRows(trip['verificationDocuments']).length == 2
                  ? 'Review verification uploads'
                  : 'Complete trip verification',
            ),
          ),
        _ConnectLine(
          'Available / total capacity',
          '${trip['remainingKg']} / ${trip['capacityKg']} kg',
        ),
        _ConnectLine('Trip status', connectLabel(trip['status'])),
        if (trip['scheduleChange'] != null)
          _ConnectLine(
            'Schedule update',
            trip['scheduleChange']['type'] == 'DELAY'
                ? 'Flight delayed'
                : 'Flight rebooked',
          ),
        if (staff && trip['status'] == 'APPROVED')
          OutlinedButton.icon(
            onPressed: () => _selectFacility(context),
            icon: const Icon(Icons.location_on_outlined),
            label: const Text('Set public receiving facility'),
          ),
        _ConnectLine(
          'Accepted categories',
          (trip['categories'] as List).map(connectLabel).join(', '),
        ),
        if (admin &&
            trip['status'] == 'PENDING_REVIEW' &&
            trip['airline'] == null)
          OutlinedButton(
            onPressed: () => _run(
              context,
              '/trips/${trip['id']}/review',
              'Approve traveller after verification',
              fields: [
                const ConnectInput(
                  'reviewNote',
                  'Identity, ticket, baggage & compliance checks',
                ),
                ConnectInput(
                  'receivingLocationId',
                  'Approved departure receiving location',
                  options: {
                    for (final l in locations.where(
                      (l) => l['connectReceiving'] == true,
                    ))
                      l['id']: l['name'],
                  },
                ),
              ],
              fixed: const {'approved': true, 'complianceVerified': true},
            ),
            child: const Text('Verify & approve trip'),
          ),
        if (staff && trip['status'] == 'APPROVED')
          OutlinedButton(
            onPressed: () => _run(
              context,
              '/trips/${trip['id']}/depart',
              'Confirm actual traveller departure',
              fixed: const {'confirmed': true},
            ),
            child: const Text('Confirm departure & freeze manifest'),
          ),
        for (final a in connectRows(trip['assignments']).where(
          (a) => ['PROPOSED', 'ACCEPTED', 'CONFIRMED'].contains(a['status']),
        ))
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfff3f7f5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  a['trackingId'],
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '${connectLabel(a['category'])} · ${a['quantity']} items · ${a['weightKg']} kg',
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 6),
                Text(a['description'] ?? '', style: AppTheme.caption),
                if (!staff &&
                    (a['scannedPackageCount'] ?? 0) == 0 &&
                    a['collectedAt'] == null &&
                    trip['status'] == 'APPROVED') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConnectDeclarationForm(
                            bookingId: a['bookingId'],
                            resourcePath: '/assignments/${a['id']}',
                            traveller: true,
                            contents: a['description'] ?? '',
                            request: request,
                          ),
                        ),
                      );
                      if (saved == true) await onChanged();
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      a['travellerDeclaration'] == null
                          ? 'Complete traveller declaration'
                          : 'Review / renew traveller declaration',
                    ),
                  ),
                ],
                if (a['travellerDeclaration'] != null)
                  Text(
                    'Traveller declaration recorded · ${countryDate(a['travellerDeclaration']['createdAt'], timezone: trip['departureTimezone'] as String? ?? suggestedTimezone('${trip['origin']}'))}',
                    style: AppTheme.caption,
                  ),
                if (!staff && a['status'] == 'PROPOSED')
                  OutlinedButton(
                    onPressed: () => _run(
                      context,
                      '/assignments/${a['id']}/respond',
                      'Accept permitted parcel contents',
                      fields: const [
                        ConnectInput('note', 'Your contents acceptance note'),
                      ],
                      fixed: const {'accepted': true},
                    ),
                    child: const Text('Review & accept parcel'),
                  ),
                if (!staff &&
                    (a['scannedPackageCount'] ?? 0) == 0 &&
                    a['collectedAt'] == null &&
                    trip['status'] == 'APPROVED')
                  TextButton(
                    onPressed: () => _run(
                      context,
                      '/assignments/${a['id']}/respond',
                      'Reject unsafe or incompatible contents',
                      fields: const [
                        ConnectInput('note', 'Reason for declining'),
                      ],
                      fixed: const {'accepted': false},
                    ),
                    child: const Text('Decline parcel'),
                  ),
                if (!staff &&
                    a['status'] == 'CONFIRMED' &&
                    a['collectedAt'] == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    a['handoverAuthorized'] == true
                        ? '${a['scannedPackageCount'] ?? 0} of ${a['expectedPackageCount'] ?? 0} packages scanned'
                        : 'The receiving team will authorize package collection.',
                    style: AppTheme.caption,
                  ),
                  if (a['handoverAuthorized'] == true &&
                      (a['scannedPackageCount'] ?? 0) <
                          (a['expectedPackageCount'] ?? 0))
                    OutlinedButton.icon(
                      onPressed: () => _scanPackage(context, a),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan package received'),
                    ),
                  if (a['handoverAuthorized'] == true &&
                      (a['expectedPackageCount'] ?? 0) > 0 &&
                      a['scannedPackageCount'] == a['expectedPackageCount'])
                    FilledButton.icon(
                      onPressed: () => _run(
                        context,
                        '/assignments/${a['id']}/collect',
                        'Confirm physical handover',
                        fields: const [
                          ConnectInput(
                            'code',
                            'Single-use code from D2F receiving team',
                          ),
                          ConnectInput(
                            'contentsAccepted',
                            'I received every scanned package and verified the contents',
                            checkbox: true,
                          ),
                        ],
                      ),
                      icon: const Icon(Icons.password),
                      label: const Text('Confirm handover with D2F code'),
                    ),
                ],
                if (a['collectedAt'] != null)
                  const Text(
                    'Package handover confirmed',
                    style: AppTheme.caption,
                  ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () async {
            try {
              final manifest = await request(
                '/trips/${trip['id']}/manifest',
                method: 'GET',
              );
              if (!context.mounted) return;
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Traveller manifest'),
                  content: SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${trip['origin']} → ${trip['destination']}'),
                          const SizedBox(height: 12),
                          if ((manifest['parcels'] as List).isEmpty)
                            const Text('No confirmed parcels yet.'),
                          for (final a in connectRows(manifest['parcels']))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text(
                                '${a['trackingId']}\n${a['description']}\n${a['weightKg']} kg · ${connectLabel(a['status'])}',
                              ),
                            ),
                        ],
                      ),
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
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          icon: const Icon(Icons.list_alt),
          label: const Text('View traveller manifest'),
        ),
      ],
    ),
  );
}

class _ConnectFacilityDialog extends StatefulWidget {
  final ConnectRequest request;
  final String path;
  final bool requiresNote;
  const _ConnectFacilityDialog({
    required this.request,
    required this.path,
    this.requiresNote = false,
  });

  @override
  State<_ConnectFacilityDialog> createState() => _ConnectFacilityDialogState();
}

class _ConnectFacilityDialogState extends State<_ConnectFacilityDialog> {
  late Future<dynamic> facilities;
  final form = GlobalKey<FormState>();
  final note = TextEditingController();
  String? selected;

  Future<dynamic> _load() => widget.request(widget.path, method: 'GET');

  @override
  void initState() {
    super.initState();
    facilities = _load();
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  void _retry() => setState(() {
    selected = null;
    facilities = _load();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: facilities,
    builder: (context, snapshot) {
      final data = snapshot.connectionState == ConnectionState.done
          ? snapshot.data
          : null;
      final options = connectRows(data?['locations']);
      return AlertDialog(
        title: const Text('Choose the public receiving facility'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Loading facilities',
                    )
                  else if (snapshot.hasError) ...[
                    const Text('Could not load receiving facilities.'),
                    TextButton(onPressed: _retry, child: const Text('Retry')),
                  ] else if (options.isEmpty) ...[
                    Text(
                      'No public receiving facility is configured for ${data['route']}. Ask your D2F administrator to set up a public address in Connect locations.',
                    ),
                    TextButton(onPressed: _retry, child: const Text('Refresh')),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Receiving facility',
                      ),
                      items: [
                        for (final option in options)
                          DropdownMenuItem(
                            value: option['id'] as String,
                            child: Text(
                              option['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => selected = value),
                    ),
                    if (widget.requiresNote)
                      TextFormField(
                        controller: note,
                        decoration: const InputDecoration(
                          labelText: 'Condition & receiving evidence',
                        ),
                        maxLength: 1000,
                        validator: (value) => value?.trim().isNotEmpty == true
                            ? null
                            : 'Required',
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selected == null || options.isEmpty
                ? null
                : () {
                    if (form.currentState?.validate() == true)
                      Navigator.pop(context, {
                        'locationId': selected,
                        if (widget.requiresNote) 'note': note.text.trim(),
                      });
                  },
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
}

class ConnectInput {
  final String key, label;
  final bool numeric, money, checkbox, optional, packageWeights;
  final Map<String, String>? options;
  const ConnectInput(
    this.key,
    this.label, {
    this.checkbox = false,
    this.numeric = false,
    this.money = false,
    this.optional = false,
    this.packageWeights = false,
    this.options,
  });
}

Future<Map<String, dynamic>?> connectActionDialog(
  BuildContext context,
  String title,
  List<ConnectInput> fields, {
  String? message,
}) async {
  final form = GlobalKey<FormState>();
  final controllers = {for (final f in fields) f.key: TextEditingController()};
  final choices = <String, String>{};
  final checks = <String, bool>{};
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 450,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(message),
                    ),
                  for (final f in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: f.checkbox
                          ? FormField<bool>(
                              initialValue: false,
                              validator: (_) =>
                                  checks[f.key] == true ? null : 'Required',
                              builder: (field) => Column(
                                children: [
                                  CheckboxListTile(
                                    value: field.value ?? false,
                                    onChanged: (v) {
                                      checks[f.key] = v == true;
                                      field.didChange(v);
                                    },
                                    title: Text(f.label),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  if (field.hasError)
                                    Text(
                                      field.errorText!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                ],
                              ),
                            )
                          : f.options != null
                          ? DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: InputDecoration(labelText: f.label),
                              items: f.options!.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) choices[f.key] = v;
                              },
                              validator: (v) =>
                                  v == null ? 'Select an option' : null,
                            )
                          : TextFormField(
                              controller: controllers[f.key],
                              decoration: InputDecoration(labelText: f.label),
                              maxLength: 1000,
                              keyboardType: f.numeric || f.money
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                    )
                                  : TextInputType.text,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return f.optional ? null : 'Required';
                                }
                                if (f.packageWeights &&
                                    v.split(',').any((text) {
                                      final weight = double.tryParse(
                                        text.trim(),
                                      );
                                      return weight == null ||
                                          !weight.isFinite ||
                                          weight <= 0;
                                    }))
                                  return 'Enter valid package weights';
                                if (f.numeric || f.money) {
                                  final n = double.tryParse(v);
                                  if (n == null || !n.isFinite || n < 0) {
                                    return 'Enter a valid number';
                                  }
                                }
                                return null;
                              },
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!(form.currentState?.validate() ?? false)) return;
              Navigator.pop(context, {
                for (final f in fields)
                  f.key: f.checkbox
                      ? checks[f.key] == true
                      : f.options != null
                      ? choices[f.key]
                      : f.packageWeights
                      ? (controllers[f.key]!.text.trim().isEmpty
                            ? null
                            : controllers[f.key]!.text
                                  .split(',')
                                  .map((v) => double.parse(v.trim()))
                                  .toList())
                      : f.money
                      ? (double.parse(controllers[f.key]!.text) * 100).round()
                      : f.numeric
                      ? double.parse(controllers[f.key]!.text)
                      : controllers[f.key]!.text.trim(),
              });
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  } finally {
    // Dispose after the closing transition releases the dialog fields.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
  }
}

class _ConnectSection extends StatelessWidget {
  final String number, title;
  final Widget child;
  const _ConnectSection({
    required this.number,
    required this.title,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffe1e9e5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xffe3f0eb),
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xff245e4e),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: AppTheme.sectionTitle)),
          ],
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

class _ConnectLine extends StatelessWidget {
  final String label;
  final dynamic value;
  const _ConnectLine(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.caption.copyWith(fontSize: 10)),
        const SizedBox(height: 4),
        SelectableText(
          '$value',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _ConnectNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ConnectNotice({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffeaf1ed),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xff327564)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: Color(0xff254c42),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ConnectRecord extends StatelessWidget {
  final String title, subtitle, status;
  final VoidCallback onTap;
  const _ConnectRecord({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 10),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.all(14),
      leading: const Icon(Icons.inventory_2_outlined, color: Color(0xff327564)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('$subtitle\n$status', style: const TextStyle(height: 1.6)),
      ),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}
