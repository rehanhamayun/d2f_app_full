import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/common.dart';
import '../widgets/route_planner.dart';
import '../widgets/timeline.dart';

typedef CustomerShipmentCreator = Future<Parcel> Function({
  required String recipientName,
  String? recipientPhone,
  String? recipientAddress,
  required String packageType,
  required double weightKg,
  required String origin,
  required String destination,
  required String method,
  String? notes,
  required String clientRequestId,
});

const _defaultCustomerRoute = ShipmentRoute(
  origin: 'Omaha, NE, USA',
  destination: 'Lomé, Togo',
);

const _customerPackageTypes = <(String, String)>[
  ('BOX', 'Box'),
  ('BARREL', 'Barrel'),
  ('TV', 'TV / electronics'),
  ('APPLIANCE', 'Appliance'),
  ('FURNITURE', 'Furniture'),
  ('PALLET', 'Pallet'),
  ('VEHICLE', 'Vehicle'),
  ('DOCUMENTS', 'Documents'),
  ('OTHER', 'Other'),
];

class CustomerShipmentScreen extends StatefulWidget {
  final ShipmentRoute? initialRoute;
  final ValueChanged<ShipmentRoute>? onRouteSelected;
  final Future<List<Parcel>> Function()? loadParcels;
  final CustomerShipmentCreator? createParcel;

  const CustomerShipmentScreen({
    super.key,
    this.initialRoute,
    this.onRouteSelected,
    this.loadParcels,
    this.createParcel,
  });

  @override
  State<CustomerShipmentScreen> createState() => _CustomerShipmentScreenState();
}

class _CustomerShipmentScreenState extends State<CustomerShipmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientAddress = TextEditingController();
  final _weight = TextEditingController();
  final _notes = TextEditingController();

  ShipmentRoute _route = _defaultCustomerRoute;
  String? _packageType;
  String? _requestId;
  List<Parcel> _parcels = const [];
  String? _parcelsError;
  bool _loadingParcels = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute ?? _defaultCustomerRoute;
    _loadParcels();
  }

  @override
  void didUpdateWidget(covariant CustomerShipmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRoute != widget.initialRoute &&
        widget.initialRoute != null) {
      _route = widget.initialRoute!;
    }
  }

  @override
  void dispose() {
    _recipientName.dispose();
    _recipientPhone.dispose();
    _recipientAddress.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _invalidateRequest() => _requestId = null;

  Future<void> _editRoute() async {
    final route = await showRoutePlanner(context, _route);
    if (route == null || !mounted) return;
    setState(() {
      _route = route;
      _invalidateRequest();
    });
    widget.onRouteSelected?.call(route);
  }

  Future<void> _loadParcels() async {
    setState(() {
      _loadingParcels = true;
      _parcelsError = null;
    });
    try {
      final parcels = await (widget.loadParcels ?? Api.I.customerParcels)();
      if (!mounted) return;
      setState(() {
        _parcels = parcels;
        _loadingParcels = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _parcelsError = error.message;
        _loadingParcels = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _parcelsError = 'Could not load your shipments. Please try again.';
        _loadingParcels = false;
      });
    }
  }

  Future<void> _contactSupport() async {
    try {
      if (await launchUrl(
        Uri(scheme: 'mailto', path: 'info@d2fshipping.com'),
      )) {
        return;
      }
    } catch (_) {
      // Copy the address when no email app is available.
    }
    if (mounted) {
      copyToClipboard(
        context,
        'info@d2fshipping.com',
        message: 'Support email copied.',
      );
    }
  }

  Future<void> _createShipment() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final weight = double.tryParse(_weight.text.trim());
    if (weight == null || !weight.isFinite || weight <= 0) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    _requestId ??=
        'customer-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    try {
      final parcel = await (widget.createParcel ?? Api.I.createCustomerParcel)(
        recipientName: _recipientName.text.trim(),
        recipientPhone: _recipientPhone.text.trim(),
        recipientAddress: _recipientAddress.text.trim(),
        packageType: _packageType!,
        weightKg: weight,
        origin: _route.origin,
        destination: _route.destination,
        method: _route.method.name,
        notes: _notes.text.trim(),
        clientRequestId: _requestId!,
      );
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CustomerParcelDetailsScreen(parcel: parcel, justCreated: true),
        ),
      );
      if (!mounted) return;
      _resetForm();
      await _loadParcels();
    } on ApiException catch (error) {
      if (mounted) authMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        authMessage(
          context,
          'Could not create your shipment. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _recipientName.clear();
    _recipientPhone.clear();
    _recipientAddress.clear();
    _weight.clear();
    _notes.clear();
    setState(() {
      _packageType = null;
      _requestId = null;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BrandLogo(fontSize: 24),
                ),
              ),
              IconButton(
                tooltip: 'Contact D2F',
                onPressed: _contactSupport,
                icon: const Icon(
                  Icons.support_agent_rounded,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: AppSpacing.pageInsets,
            children: [
              Text('Your next shipment', style: AppTheme.display),
              const SizedBox(height: 6),
              const Text(
                'Create a shipment request and get a trackable ID straight away.',
                style: AppTheme.caption,
              ),
              const SizedBox(height: 18),
              _routeCard(),
              const SizedBox(height: 18),
              _shipmentForm(),
              const SizedBox(height: 12),
              SectionCard(
                tint: AppColors.goldSoft,
                padding: const EdgeInsets.all(13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.navy,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your tracking ID is created now. D2F will confirm physical intake before the parcel moves to Received.',
                        style: AppTheme.caption.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  const Expanded(
                    child: Text('Your shipments', style: AppTheme.sectionTitle),
                  ),
                  IconButton(
                    tooltip: 'Refresh shipments',
                    onPressed: _loadingParcels ? null : _loadParcels,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _shipmentList(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _routeCard() => Material(
    color: AppColors.blueSoft,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      key: const ValueKey('customer-route'),
      onTap: _editRoute,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public_rounded, color: AppColors.blue),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'YOUR ROUTE',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  'Edit',
                  style: TextStyle(
                    color: AppColors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.blue),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _routePoint('FROM', _route.origin)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.flight_takeoff_rounded,
                    color: AppColors.coral,
                  ),
                ),
                Expanded(
                  child: _routePoint('TO', _route.destination, alignEnd: true),
                ),
              ],
            ),
            const Divider(height: 25),
            Row(
              children: [
                Icon(_route.method.icon, size: 18, color: AppColors.navy),
                const SizedBox(width: 8),
                Text(
                  '${_route.method.label} · ${_route.method.tagline}',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _routePoint(String label, String value, {bool alignEnd = false}) =>
      Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
      );

  Widget _shipmentForm() => SectionCard(
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Recipient details', style: AppTheme.sectionTitle),
          const SizedBox(height: 5),
          const Text(
            'Who should receive this shipment?',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('customer-recipient-name'),
            controller: _recipientName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _invalidateRequest(),
            decoration: const InputDecoration(
              labelText: 'Recipient name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 11),
          TextFormField(
            key: const ValueKey('customer-recipient-phone'),
            controller: _recipientPhone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _invalidateRequest(),
            decoration: const InputDecoration(
              labelText: 'Recipient phone (optional)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 11),
          TextFormField(
            key: const ValueKey('customer-recipient-address'),
            controller: _recipientAddress,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _invalidateRequest(),
            decoration: const InputDecoration(
              labelText: 'Delivery address (optional)',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: 11),
          DropdownButtonFormField<String>(
            key: const ValueKey('customer-package-type'),
            initialValue: _packageType,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Package type',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
            items: [
              for (final type in _customerPackageTypes)
                DropdownMenuItem(value: type.$1, child: Text(type.$2)),
            ],
            onChanged: (value) => setState(() {
              _packageType = value;
              _invalidateRequest();
            }),
            validator: (value) =>
                value == null ? 'Choose a package type' : null,
          ),
          const SizedBox(height: 11),
          TextFormField(
            key: const ValueKey('customer-package-weight'),
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _invalidateRequest(),
            decoration: const InputDecoration(
              labelText: 'Weight (kg)',
              prefixIcon: Icon(Icons.scale_outlined),
            ),
            validator: (value) {
              final weight = double.tryParse(value?.trim() ?? '');
              if (weight == null || !weight.isFinite || weight <= 0) {
                return 'Enter a weight greater than 0 kg';
              }
              return null;
            },
          ),
          const SizedBox(height: 11),
          TextFormField(
            key: const ValueKey('customer-shipment-notes'),
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _invalidateRequest(),
            decoration: const InputDecoration(
              labelText: 'Notes for D2F (optional)',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            key: const ValueKey('customer-create-shipment'),
            label: 'Create shipment request',
            loading: _saving,
            onPressed: _saving ? null : _createShipment,
          ),
        ],
      ),
    ),
  );

  Widget _shipmentList() {
    if (_loadingParcels) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_parcelsError != null) {
      return SectionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_parcelsError!, style: AppTheme.caption),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadParcels,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_parcels.isEmpty) {
      return SectionCard(
        tint: Colors.white,
        padding: const EdgeInsets.all(18),
        child: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.textGrey),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your shipment requests and tracking IDs will appear here.',
                style: AppTheme.caption,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final parcel in _parcels) ...[
          _CustomerParcelTile(
            parcel: parcel,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CustomerParcelDetailsScreen(parcel: parcel),
              ),
            ),
          ),
          if (parcel != _parcels.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CustomerParcelTile extends StatelessWidget {
  final Parcel parcel;
  final VoidCallback onTap;
  const _CustomerParcelTile({required this.parcel, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      key: ValueKey('customer-parcel-${parcel.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parcel.trackingId,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${parcel.origin} → ${parcel.destination}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontSize: 10),
                  ),
                  const SizedBox(height: 7),
                  StatusChip(status: parcel.status, short: true),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textGrey),
          ],
        ),
      ),
    ),
  );
}

class CustomerParcelDetailsScreen extends StatelessWidget {
  final Parcel parcel;
  final bool justCreated;
  const CustomerParcelDetailsScreen({
    super.key,
    required this.parcel,
    this.justCreated = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = justCreated ? 'Request submitted' : 'Shipment details';
    return Scaffold(
      backgroundColor: authCanvas,
      appBar: AppBar(
        backgroundColor: authCanvas,
        foregroundColor: AppColors.navy,
        title: Text(title, style: AppTheme.sectionTitle),
        centerTitle: false,
      ),
      body: ListView(
        padding: AppSpacing.pageInsets,
        children: [
          if (justCreated) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Request created.',
                          style: AppTheme.display.copyWith(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your tracking ID is ready. We’ll update you when D2F confirms intake.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.flight_takeoff_rounded,
                    color: AppColors.gold,
                    size: 56,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          SectionCard(
            tint: AppColors.blueSoft,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TRACKING ID',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy tracking ID',
                      onPressed: () =>
                          copyToClipboard(context, parcel.trackingId),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
                Text(
                  parcel.trackingId,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 12),
                QrImageView(
                  data: parcel.trackingId,
                  version: QrVersions.auto,
                  size: 150,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.navy,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    color: AppColors.navy,
                    dataModuleShape: QrDataModuleShape.square,
                  ),
                ),
                const SizedBox(height: 8),
                StatusChip(status: parcel.status),
                const SizedBox(height: 10),
                Text(
                  statusHeadline(parcel.status),
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('Shipment route', style: AppTheme.sectionTitle),
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _detailRow('From', parcel.origin),
                const Divider(height: 22),
                _detailRow('To', parcel.destination),
                const Divider(height: 22),
                _detailRow(
                  'Method',
                  '${parcel.method.label} · ${parcel.method.tagline}',
                ),
                const Divider(height: 22),
                _detailRow('Package', parcel.packageTypeLabel),
                const Divider(height: 22),
                _detailRow('Weight', '${parcel.weightKg} kg'),
                const Divider(height: 22),
                _detailRow('Recipient', parcel.recipientName),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('Progress', style: AppTheme.sectionTitle),
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: TrackingTimeline(
              events: parcel.events,
              currentStatus: parcel.status,
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'View my shipments',
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 10),
          OutlineButton2(
            label: justCreated ? 'Done' : 'Back',
            onPressed: () => Navigator.pop(context, false),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 78,
        child: Text(label, style: AppTheme.caption.copyWith(fontSize: 11)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}
