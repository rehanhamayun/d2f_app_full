import 'shipment_custody_screen.dart';
import '../widgets/service_experience.dart';
import '../widgets/shipment_updates.dart';
import 'scan_screen.dart';
import 'connect_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/country_flag.dart';
import '../core/service_area.dart';
import '../widgets/d2f_navigation_bar.dart';
import '../widgets/reference_widgets.dart';
import '../widgets/timeline.dart';
import '../widgets/route_planner.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';
import 'account_screen.dart';
import 'customer_shipment_screen.dart';
import '../widgets/customer_tracking_history.dart';

/// Customers and drivers never mount the staff shell or fetch staff records.
class RoleWorkspaceScreen extends ConsumerStatefulWidget {
  final Future<List<Parcel>> Function()? loadCustomerParcels;
  final CustomerShipmentCreator? createCustomerParcel;

  const RoleWorkspaceScreen({
    super.key,
    this.loadCustomerParcels,
    this.createCustomerParcel,
  });
  @override
  ConsumerState<RoleWorkspaceScreen> createState() =>
      _RoleWorkspaceScreenState();
}

class _RoleWorkspaceScreenState extends ConsumerState<RoleWorkspaceScreen> {
  final _tracking = TextEditingController();
  bool _busy = false;
  int _section = 0;
  ShipmentRoute? _plannedRoute;
  @override
  void dispose() {
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final code = _tracking.text.trim().toUpperCase();
    if (!RegExp(r'^(?:[A-Z0-9]{3,5}(?:\d{12}|\d{15})|D2F-\d{4}-\d{6})$')
        .hasMatch(code)) {
      authMessage(
        context,
        'Enter the tracking number shown on the shipment label.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final shipment = await Api.I.trackShipment(code);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PublicTrackingScreen(shipment: shipment),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) authMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        authMessage(
          context,
          'Could not track your shipment. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'info@d2fshipping.com',
      queryParameters: {
        'subject': 'D2F shipping enquiry',
        if (_plannedRoute != null)
          'body':
              'Hello D2F,\n\nI would like to arrange a shipment.\nFrom: ${_plannedRoute!.origin}\nTo: ${_plannedRoute!.destination}\nMethod: ${_plannedRoute!.method.label}\n\nPlease confirm the available options and requirements.',
      },
    );
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {
      /* Copy fallback below. */
    }
    await Clipboard.setData(const ClipboardData(text: 'info@d2fshipping.com'));
    if (mounted) {
      authMessage(context, 'Support email copied: info@d2fshipping.com');
    }
  }

  Future<void> _editRoute() async {
    final route = await showRoutePlanner(
      context,
      _plannedRoute ??
          const ShipmentRoute(
            origin: 'USA / Europe',
            destination: 'West Africa',
          ),
    );
    if (route != null && mounted) setState(() => _plannedRoute = route);
  }

  void _planShippingMethod(ShippingMethod method) {
    setState(() {
      _plannedRoute = ShipmentRoute(
        origin: 'USA / Europe',
        destination: 'West Africa',
        method: method,
      );
      _section = 1;
    });
  }

  void _planDestination(String destination) {
    setState(() {
      _plannedRoute = ShipmentRoute(
        origin: 'USA / Europe',
        destination: destination,
        method: _plannedRoute?.method ?? ShippingMethod.AIR,
      );
      _section = 1;
    });
  }

  Widget _routeSummary() => SectionCard(
    tint: AppColors.goldSoft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.public_rounded, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Your shipment route',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: _editRoute,
              child: const Text('Edit', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _routeLine('FROM', _plannedRoute!.origin, Icons.trip_origin_rounded),
        const Padding(
          padding: EdgeInsets.only(left: 9),
          child: SizedBox(height: 15, child: VerticalDivider(width: 1)),
        ),
        _routeLine(
          'TO',
          _plannedRoute!.destination,
          Icons.location_on_outlined,
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 13),
        Row(
          children: [
            Icon(_plannedRoute!.method.icon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_plannedRoute!.method.label} · ${_plannedRoute!.method.tagline}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _routeLine(String label, String value, IconData icon) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: AppColors.coral),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textGrey,
                letterSpacing: .9,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _updates() => showShipmentUpdates(
    context,
    loadParcels: widget.loadCustomerParcels ?? Api.I.customerTrackingParcels,
    onOpen: (parcel) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            parcel.serviceType == 'AIR_TRAVELLER' &&
                parcel.connectBookingId != null
            ? ConnectBookingScreen(
                id: parcel.connectBookingId!,
                request: Api.I.connect,
              )
            : CustomerParcelDetailsScreen(parcel: parcel),
      ),
    ),
  );

  Future<void> _scanTracking() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen(returnTracking: true)),
    );
    if (!mounted || value == null) return;
    _tracking.text = value;
    await _track();
  }

  void _openService(D2FService service) {
    if (service == D2FService.buy) {
      _select(5);
      return;
    }
    if (service == D2FService.marketplace) {
      _select(4);
      return;
    }
    openD2FService(
      context,
      service,
      onShip: () => _select(1),
      onContact: _contact,
    );
  }

  void _select(int index) => setState(() => _section = index);
  Widget _trackingPanel({required bool driver}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Track a shipment', style: AppTheme.display),
      const SizedBox(height: 8),
      Text(
        driver
            ? 'Every update, all in one place. Enter the number on your shipping label.'
            : 'Every update, all in one place. Enter a tracking number or find your shipment below.',
        style: AppTheme.caption,
      ),
      const SizedBox(height: 24),
      D2FSearchField(
        controller: _tracking,
        hint: 'D2F000000000001',
        onSubmit: (_) => _track(),
      ),
      const SizedBox(height: 14),
      PrimaryButton(label: 'Track Shipment', loading: _busy, onPressed: _track),
      const SizedBox(height: 24),
      if (!driver)
        CustomerTrackingHistory(loadParcels: widget.loadCustomerParcels),
      if (driver)
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: const ReferenceArt('journey', height: 230),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final driver = user?.role == UserRole.DRIVER;
    return Scaffold(
      backgroundColor: authCanvas,
      bottomNavigationBar: D2FNavigationBar(
        selectedIndex: _section,
        publicWorkspace: true,
        driver: driver,
        onSelected: _select,
      ),
      body: _section == 3
          ? AccountScreen(onTrack: () => _select(2), onShip: () => _select(1))
          : !driver && (_section == 4 || _section == 5)
          ? D2FServiceScreen(
              key: ValueKey('customer-service-$_section'),
              service: _section == 4 ? D2FService.marketplace : D2FService.buy,
              embedded: true,
              onContact: _contact,
              onProfile: () => _select(3),
              onNotifications: _updates,
            )
          : driver && _section == 1
          ? const DriverTasksScreen()
          : !driver && _section == 1
          ? CustomerShipmentScreen(
              initialRoute:
                  _plannedRoute ??
                  const ShipmentRoute(
                    origin: 'Omaha, NE, USA',
                    destination: 'Lomé, Togo',
                  ),
              onRouteSelected: (route) => setState(() => _plannedRoute = route),
              loadParcels: widget.loadCustomerParcels,
              createParcel: widget.createCustomerParcel,
            )
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView(
                    key: PageStorageKey('workspace-section-$_section'),
                    padding: !driver && _section == 0
                        ? const EdgeInsets.fromLTRB(18, 0, 18, 10)
                        : AppSpacing.pageInsets,
                    children: [
                      D2FHomeHeader(
                        onBell: driver ? () => _select(2) : _updates,
                        onProfile: () => _select(3),
                        actionTooltip: driver
                            ? 'Track a parcel'
                            : 'Shipment updates',
                        dense: !driver && _section == 0,
                      ),
                      SizedBox(height: !driver && _section == 0 ? 0 : 22),
                      if (_section == 2)
                        _trackingPanel(driver: driver)
                      else if (_section == 1) ...[
                        ScreenIntro(
                          title: driver
                              ? 'Your next delivery.'
                              : 'Let’s get it moving.',
                          subtitle: driver
                              ? 'Coordinate your deliveries with your D2F dispatcher.'
                              : 'USA & Europe to West Africa. And back again.',
                          art: 'parcel',
                        ),
                        const SizedBox(height: 24),
                        if (!driver) ...[
                          if (_plannedRoute != null)
                            _routeSummary()
                          else
                            RoutePlannerCard(
                              initialRoute: const ShipmentRoute(
                                origin: 'USA / Europe',
                                destination: 'West Africa',
                              ),
                              onRouteSelected: (route) =>
                                  setState(() => _plannedRoute = route),
                            ),
                          const SizedBox(height: 18),
                        ],
                        SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                driver
                                    ? 'Delivery coordination'
                                    : 'Arrange a shipment',
                                style: AppTheme.sectionTitle,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                driver
                                    ? 'Contact your dispatcher for your delivery assignments and instructions.'
                                    : 'Our shipping team will help confirm your route, parcel requirements and available shipping options.',
                                style: AppTheme.caption,
                              ),
                              const SizedBox(height: 22),
                              PrimaryButton(
                                label: driver
                                    ? 'Contact dispatcher'
                                    : 'Contact shipping team',
                                onPressed: _contact,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const ReferenceArt('warehouse'),
                      ] else ...[
                        if (driver) ...[
                          Text(
                            'Hello, ${user?.fullName.split(' ').first ?? 'there'}.',
                            style: AppTheme.display,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your driver workspace.',
                            style: AppTheme.caption,
                          ),
                          const SizedBox(height: 20),
                          const ScreenIntro(
                            title: 'Ready for the road.',
                            subtitle: 'Connect with your dispatcher and follow a shipment’s progress.',
                            art: 'journey',
                          ),
                          const SizedBox(height: 20),
                          PrimaryButton(
                            label: 'Contact your dispatcher',
                            onPressed: _contact,
                          ),
                          const SizedBox(height: 24),
                          _trackingPanel(driver: true),
                        ] else ...[
                          D2FServiceHome(
                            onShip: () => _select(1),
                            onTrack: () => _select(2),
                            onContact: _contact,
                            onServiceSelected: _openService,
                            trackingField: TextField(
                              key: const ValueKey('home-tracking-input'),
                              controller: _tracking,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _track(),
                              decoration: InputDecoration(
                                hintText: 'Enter tracking number',
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 10,
                                ),
                                prefixIcon: IconButton(
                                  tooltip: 'Track shipment',
                                  onPressed: _track,
                                  icon: const Icon(
                                    Icons.search_rounded,
                                    color: AppColors.blue,
                                  ),
                                ),
                                suffixIcon: IconButton(
                                  key: const ValueKey('home-scan-tracking'),
                                  tooltip: 'Scan tracking label',
                                  onPressed: _scanTracking,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: AppColors.blue,
                                  ),
                                ),
                              ),
                            ),
                            shippingMethods: Row(
                              children: [
                                for (final method in ShippingMethod.values) ...[
                                  Expanded(child: _shippingMethodCard(method)),
                                  if (method != ShippingMethod.ROAD)
                                    const SizedBox(width: 10),
                                ],
                              ],
                            ),
                            destinations: _customerRouteCard(),
                          ),
                          if (_busy)
                            const LinearProgressIndicator(minHeight: 2),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _shippingMethodCard(ShippingMethod method) => Material(
    color: switch (method) {
      ShippingMethod.AIR => AppColors.coralSoft,
      ShippingMethod.SEA => AppColors.blueSoft,
      ShippingMethod.ROAD => AppColors.goldSoft,
    },
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      key: ValueKey('home-method-${method.name.toLowerCase()}'),
      onTap: () => _planShippingMethod(method),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(1) > 1.15 ? 78 : 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Row(
            children: [
              Icon(method.icon, size: 23),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      method.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8,
                        height: 1.2,
                        color: AppColors.textGrey,
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
  );

  Widget _customerRouteCard() => SectionCard(
    tint: Colors.white,
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 38,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/auth_reference_map.png',
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
                ColoredBox(color: Colors.white.withValues(alpha: .16)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(child: _routePlace('FROM', 'USA / Europe')),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.public_rounded,
                          color: AppColors.navy,
                          size: 17,
                        ),
                      ),
                      Expanded(
                        child: _routePlace('TO', 'West Africa', alignEnd: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in kCountryLocations.entries) ...[
                _destinationChip(entry.key, entry.value),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _routePlace(String label, String place, {bool alignEnd = false}) =>
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 7,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            place,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );

  Widget _destinationChip(String country, String destination) => ActionChip(
    key: ValueKey(
      'home-destination-${country.toLowerCase().replaceAll(' ', '-')}',
    ),
    avatar: CountryFlag(country: country),
    label: Text(country),
    onPressed: () => _planDestination(destination),
    backgroundColor: AppColors.cream,
    side: const BorderSide(color: AppColors.border),
    labelStyle: const TextStyle(
      color: AppColors.navy,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    ),
    visualDensity: VisualDensity.compact,
  );
}

/// Only the public, redacted tracking response is rendered for customers/drivers.
class PublicTrackingScreen extends StatelessWidget {
  final Map<String, dynamic> shipment;
  const PublicTrackingScreen({super.key, required this.shipment});
  @override
  Widget build(BuildContext context) {
    final events = (shipment['events'] as List).asMap().entries.map((entry) {
      final event = entry.value as Map;
      return TrackingEvent(
        id: 'public-${entry.key}',
        status: event['status'] as String,
        createdAt: DateTime.parse(event['createdAt'] as String),
      );
    }).toList();
    return Scaffold(
      appBar: D2FAppBar(title: const Text('Track your parcel')),
      body: ListView(
        padding: AppSpacing.pageInsets,
        children: [
          ParcelSummaryCard(
            trackingId: shipment['trackingId'] as String,
            status: shipment['status'] as String,
            method: shipment['serviceType'] == 'AIR_TRAVELLER'
                ? 'D2F Connect · Air Traveller'
                : shippingMethodFrom(shipment['method'] as String).label,
            onCopy: () =>
                copyToClipboard(context, shipment['trackingId'] as String),
          ),
          const SizedBox(height: 24),
          const Text('Tracking Timeline', style: AppTheme.sectionTitle),
          const SizedBox(height: 14),
          SectionCard(
            child: TrackingTimeline(
              events: events,
              currentStatus: shipment['status'] as String,
            ),
          ),
        ],
      ),
    );
  }
}
