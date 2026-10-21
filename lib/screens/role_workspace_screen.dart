import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/country_flag.dart';
import '../widgets/d2f_navigation_bar.dart';
import '../widgets/reference_widgets.dart';
import '../widgets/timeline.dart';
import '../widgets/route_planner.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';
import 'account_screen.dart';

/// Customers and drivers never mount the staff shell or fetch staff records.
class RoleWorkspaceScreen extends ConsumerStatefulWidget {
  const RoleWorkspaceScreen({super.key});
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
    if (!RegExp(r'^D2F-\d{4}-\d{6}$').hasMatch(code)) {
      authMessage(context, 'Enter a tracking number like D2F-2026-000123.');
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

  void _select(int index) => setState(() => _section = index);
  Widget _trackingPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Track a shipment', style: AppTheme.display),
      const SizedBox(height: 8),
      const Text(
        'Every update, all in one place. Enter the number on your shipping label.',
        style: AppTheme.caption,
      ),
      const SizedBox(height: 24),
      D2FSearchField(
        controller: _tracking,
        hint: 'D2F-2026-000123',
        onSubmit: (_) => _track(),
      ),
      const SizedBox(height: 14),
      PrimaryButton(label: 'Track Shipment', loading: _busy, onPressed: _track),
      const SizedBox(height: 24),
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
    final compact = MediaQuery.sizeOf(context).width < 360;
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1.15;
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
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView(
                    padding: !driver && _section == 0
                        ? const EdgeInsets.fromLTRB(18, 0, 18, 10)
                        : AppSpacing.pageInsets,
                    children: [
                      D2FHomeHeader(
                        onBell: () => _select(2),
                        actionTooltip: 'Track a parcel',
                        dense: !driver && _section == 0,
                      ),
                      SizedBox(height: !driver && _section == 0 ? 0 : 22),
                      if (_section == 2)
                        _trackingPanel()
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
                          _trackingPanel(),
                        ] else ...[
                          Text(
                            'Good things.\nGoing places.',
                            style: AppTheme.display.copyWith(
                              fontSize: 29,
                              height: 1.06,
                            ),
                          ),
                          const SizedBox(height: 0),
                          Text(
                            'Send a little closer to home.',
                            style: AppTheme.caption.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: enlargedText
                                ? 270
                                : compact
                                ? 176
                                : 184,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: ReferenceActionCard(
                                    title: 'Send\nPackage',
                                    artwork: 'assets/images/send_parcel_reference.png',
                                    subtitle:
                                        'Across borders.\nCloser to home.',
                                    color: AppColors.coral,
                                    icon: Icons.inventory_2_outlined,
                                    onTap: () => _select(1),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: ReferenceActionCard(
                                          title: 'Track Parcel',
                                          subtitle: 'Follow its journey',
                                          color: AppColors.blue,
                                          icon: Icons.location_on_outlined,
                                          onTap: () => _select(2),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: ReferenceActionCard(
                                          title: 'Buy For Me',
                                          subtitle: 'Coming soon',
                                          color: AppColors.yellow,
                                          icon: Icons.shopping_bag_outlined,
                                          onTap: () => showComingSoon(
                                            context,
                                            'Buy For Me',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          D2FSearchField(
                            controller: _tracking,
                            hint: 'Enter tracking number',
                            onSubmit: (_) => _track(),
                            compact: true,
                          ),
                          if (_busy)
                            const LinearProgressIndicator(minHeight: 2),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: const ReferenceArt(
                              'warehouse',
                              height: 150,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const Text(
                            'How would you like to send?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              for (final method in ShippingMethod.values) ...[
                                Expanded(child: _shippingMethodCard(method)),
                                if (method != ShippingMethod.ROAD)
                                  const SizedBox(width: 10),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Explore more',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: _explore(
                                  'Shop & Ship',
                                  Icons.shopping_bag_outlined,
                                  AppColors.coralSoft,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _explore(
                                  'Recharge & Data',
                                  Icons.phone_android_rounded,
                                  AppColors.blueSoft,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _explore(
                                  'Partner Offers',
                                  Icons.sell_outlined,
                                  AppColors.goldSoft,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _customerRouteCard(),
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
                          Icons.flight_takeoff_rounded,
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
              _destinationChip('Togo', 'Lomé, Togo'),
              const SizedBox(width: 4),
              _destinationChip('Benin', 'Cotonou, Benin'),
              const SizedBox(width: 4),
              _destinationChip('Burkina Faso', 'Ouagadougou, Burkina Faso'),
              const SizedBox(width: 4),
              _destinationChip('Gabon', 'Libreville, Gabon'),
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

  Widget _explore(String title, IconData icon, Color tint) => Material(
    color: tint,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: () => showComingSoon(context, title),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(1) > 1.15 ? 72 : 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 19, color: AppColors.navy),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 8,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Coming soon',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 6.5,
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
            method: shippingMethodFrom(shipment['method'] as String).label,
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
