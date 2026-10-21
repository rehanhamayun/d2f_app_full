import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/reference_widgets.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/route_planner.dart';
import 'ship_screen.dart';
import 'parcel_detail_screen.dart';
import 'scan_screen.dart';

/// Staff and admin dashboard. Counts and recents come from the existing API.
class HomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onGoRegister, onGoActivity;
  final ValueChanged<ShippingMethod>? onGoMethod;
  final ValueChanged<ShipmentRoute>? onGoRoute;
  final Future<Map<String, int>> Function()? loadStats;
  final Future<List<Parcel>> Function()? loadRecent;
  const HomeScreen({
    super.key,
    required this.onGoRegister,
    required this.onGoActivity,
    this.onGoMethod,
    this.onGoRoute,
    this.loadStats,
    this.loadRecent,
  });
  @override
  ConsumerState<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, int>? _stats;
  List<Parcel>? _recent;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _failed = false);
    await Future.wait([
      () async {
        try {
          final data = await (widget.loadStats?.call() ?? Api.I.parcelStats());
          if (mounted) setState(() => _stats = data);
        } catch (_) {
          if (mounted) setState(() => _failed = true);
        }
      }(),
      () async {
        try {
          final data = await (widget.loadRecent?.call() ?? Api.I.parcels());
          if (mounted) setState(() => _recent = data);
        } catch (_) {
          if (mounted) setState(() => _failed = true);
        }
      }(),
    ]);
  }

  Future<void> refresh() => _refresh();

  String _count(String status) =>
      _stats == null ? '—' : '${_stats![status] ?? 0}';
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final name = user?.fullName.trim().split(' ').first ?? 'there';
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final compact = MediaQuery.sizeOf(context).width < 360;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            D2FHomeHeader(onBell: widget.onGoActivity),
            const SizedBox(height: 19),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.goldSoft,
                  child: Text(
                    name.isEmpty ? 'D' : name[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting, $name.',
                        style: AppTheme.sectionTitle.copyWith(
                          fontSize: 24,
                          letterSpacing: -.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.role == UserRole.ADMIN
                            ? 'Your operations, at a glance.'
                            : 'Let’s get things moving today.',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SectionCard(
              tint: AppColors.blueSoft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assigned location: ${user?.locationName ?? 'Not assigned'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.verified_user_outlined, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final metric in [
                    (
                      'Total Parcels',
                      _stats == null
                          ? '—'
                          : '${_stats!.values.fold<int>(0, (a, b) => a + b)}',
                      'All registered shipments',
                      Icons.inventory_2_outlined,
                      AppColors.blueSoft,
                    ),
                    (
                      'In Transit',
                      _count('IN_TRANSIT'),
                      'Currently on the move',
                      Icons.local_shipping_outlined,
                      AppColors.goldSoft,
                    ),
                    (
                      'Processing',
                      _count('PROCESSING'),
                      'Being prepared for shipment',
                      Icons.pending_actions_rounded,
                      AppColors.greenSoft,
                    ),
                    (
                      'Delivered',
                      _count('DELIVERED'),
                      'Successfully completed',
                      Icons.task_alt_rounded,
                      AppColors.coralSoft,
                    ),
                  ])
                    SizedBox(
                      width: (c.maxWidth - 10) / 2,
                      child: DashboardMetric(
                        title: metric.$1,
                        value: metric.$2,
                        caption: metric.$3,
                        icon: metric.$4,
                        tint: metric.$5,
                        onTap: widget.onGoActivity,
                      ),
                    ),
                ],
              ),
            ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Some shipment information could not load.',
                        style: AppTheme.caption,
                      ),
                    ),
                    TextButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            const SizedBox(height: 22),
            SizedBox(
              height: compact ? 176 : 184,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 6,
                    child: ReferenceActionCard(
                      title: 'Register\nParcel',
                      subtitle: 'Create a shipment',
                      color: AppColors.coral,
                      icon: Icons.add_box_outlined,
                      onTap: widget.onGoRegister,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        Expanded(
                          child: ReferenceActionCard(
                            title: 'Scan Parcel',
                            subtitle: 'Scan a QR or barcode',
                            color: AppColors.blue,
                            icon: Icons.qr_code_scanner_rounded,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ScanScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ReferenceActionCard(
                            title: 'Search Parcel',
                            subtitle: 'Find any shipment',
                            color: AppColors.yellow,
                            icon: Icons.search_rounded,
                            onTap: widget.onGoActivity,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text('Recent shipments', style: AppTheme.sectionTitle),
                ),
                TextButton(
                  onPressed: widget.onGoActivity,
                  child: const Text(
                    'View all',
                    style: TextStyle(fontSize: 11, color: AppColors.textGrey),
                  ),
                ),
              ],
            ),
            if (_recent == null && !_failed)
              const LinearProgressIndicator(minHeight: 2),
            if (_recent?.isEmpty ?? false)
              const SectionCard(
                child: Text(
                  'No shipments yet. Register your first parcel to get started.',
                  style: AppTheme.caption,
                ),
              ),
            for (final parcel in (_recent ?? <Parcel>[]).take(3))
              ShipmentRecordTile(
                parcel: parcel,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ParcelDetailScreen(parcelId: parcel.id),
                    ),
                  );
                  if (mounted) _refresh();
                },
              ),
            const SizedBox(height: 20),
            D2FSearchField(
              hint: 'Enter tracking number',
              onSubmit: (value) => _lookup(context, value),
            ),
            const SizedBox(height: 22),
            const Text('Shipping methods', style: AppTheme.sectionTitle),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final method in ShippingMethod.values) ...[
                  Expanded(
                    child: _MethodCard(
                      method: method,
                      onTap: () => widget.onGoMethod != null
                          ? widget.onGoMethod!(method)
                          : widget.onGoRegister(),
                    ),
                  ),
                  if (method != ShippingMethod.ROAD) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: const ReferenceArt('warehouse', fit: BoxFit.cover),
            ),
            const SizedBox(height: 22),
            const Text('Explore more', style: AppTheme.sectionTitle),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FutureService(
                    title: 'Marketplace',
                    color: AppColors.coralSoft,
                    artworkAsset: 'assets/images/home_marketplace.svg',
                    onTap: () => showComingSoon(context, 'D2F Marketplace'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FutureService(
                    title: 'Buy For Me',
                    color: AppColors.blueSoft,
                    artworkAsset: 'assets/images/home_buy_for_me.svg',
                    onTap: () => showComingSoon(context, 'Buy For Me'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            RoutePlannerCard(
              onRouteSelected: (route) {
                if (widget.onGoRoute != null) {
                  widget.onGoRoute!(route);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          Scaffold(body: ShipScreen(initialRoute: route)),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lookup(BuildContext context, String value) async {
    final term = value.trim();
    if (term.isEmpty) return;
    try {
      final parcel = await Api.I.parcelDetail(term);
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ParcelDetailScreen(parcelId: parcel.id),
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _MethodCard extends StatelessWidget {
  final ShippingMethod method;
  final VoidCallback onTap;
  const _MethodCard({required this.method, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (tint, fg) = switch (method) {
      ShippingMethod.AIR => (AppColors.coralSoft, AppColors.coral),
      ShippingMethod.SEA => (AppColors.blueSoft, AppColors.blue),
      ShippingMethod.ROAD => (AppColors.goldSoft, Color(0xFF9A7100)),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(method.icon, color: fg, size: 22),
                const SizedBox(width: 6),
                Text(
                  method.label,
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              method.tagline,
              style: const TextStyle(color: AppColors.textGrey, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _FutureService extends StatelessWidget {
  final String title;
  final String artworkAsset;
  final Color color;
  final VoidCallback onTap;
  const _FutureService({
    required this.title,
    required this.artworkAsset,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              height: 100,
              child: ExcludeSemantics(
                child: SvgPicture.asset(
                  artworkAsset,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'COMING SOON',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .9,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
