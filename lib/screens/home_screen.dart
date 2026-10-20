import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'parcel_detail_screen.dart';
import 'scan_screen.dart';

/// Staff dashboard (adapted from the approved customer dashboard design,
/// screen 3) with M1 staff actions.
class HomeScreen extends StatelessWidget {
  final VoidCallback onGoRegister;
  final VoidCallback onGoActivity;
  final ValueChanged<ShippingMethod>? onGoMethod;

  const HomeScreen({
    super.key,
    required this.onGoRegister,
    required this.onGoActivity,
    this.onGoMethod,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const D2FHomeHeader(),
          const SizedBox(height: 10),

          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.blueSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'STAFF WORKSPACE',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 9,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Headline
          Text(
            'Parcels in motion.',
            style: AppTheme.display.copyWith(height: 1.1),
          ),
          const SizedBox(height: 6),
          Text(
            'Register, scan and update every shipment from one desk.',
            style: AppTheme.body.copyWith(color: AppColors.textGrey),
          ),
          const SizedBox(height: 18),

          // Quick actions row
          SizedBox(
            height: 232,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Send Package (big coral card) → Register parcel
                Expanded(
                  flex: 5,
                  child: _QuickCard(
                    color: AppColors.deepPurple,
                    title: 'Register\nparcel',
                    artworkAsset: 'assets/images/home_register_card.png',
                    onTap: onGoRegister,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      // Track Parcel (blue card) → Scan / lookup
                      Expanded(
                        child: _QuickCard(
                          color: AppColors.deepBlue,
                          title: 'Track parcel',
                          artworkAsset: 'assets/images/home_track_card.png',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ScanScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Parcel records are the third primary M1 action.
                      Expanded(
                        child: _QuickCard(
                          color: AppColors.deepTeal,
                          title: 'All parcels',
                          artworkAsset:
                              'assets/images/home_all_parcels_card.png',
                          onTap: onGoActivity,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tracking number lookup
          D2FSearchField(
            hint: 'Enter tracking number',
            onSubmit: (value) => _lookup(context, value),
          ),
          const SizedBox(height: 18),

          // Hero banner
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: const ReferenceArt('warehouse', fit: BoxFit.cover),
          ),
          const SizedBox(height: 22),

          // How would you like to send?
          const Text('Shipping methods', style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final m in ShippingMethod.values) ...[
                Expanded(
                  child: _MethodCard(
                    method: m,
                    onTap: () {
                      if (onGoMethod != null) {
                        onGoMethod!(m);
                      } else {
                        onGoRegister();
                      }
                    },
                  ),
                ),
                if (m != ShippingMethod.ROAD) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 22),

          const Text('More from D2F', style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FutureService(
                  title: 'Marketplace',
                  icon: Icons.storefront_outlined,
                  color: AppColors.deepPurple,
                  artworkAsset: 'assets/images/parcel.jpg',
                  onTap: () => showComingSoon(context, 'D2F Marketplace'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FutureService(
                  title: 'Buy For Me',
                  icon: Icons.shopping_bag_outlined,
                  color: AppColors.deepTeal,
                  artworkAsset: 'assets/images/success.jpg',
                  onTap: () => showComingSoon(context, 'Buy For Me'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Every parcel, connected.', style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          const SectionCard(
            tint: AppColors.tealSoft,
            child: Column(
              children: [
                _WorkflowLine(
                  number: '01',
                  title: 'Register & identify',
                  description:
                      'Save parcel details and generate its QR and barcode.',
                ),
                Divider(height: 24),
                _WorkflowLine(
                  number: '02',
                  title: 'Scan & find',
                  description: 'Scan a label or enter the tracking number.',
                ),
                Divider(height: 24),
                _WorkflowLine(
                  number: '03',
                  title: 'Update & follow',
                  description:
                      'Record a status update and keep a traceable history.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Route banner
          SectionCard(
            tint: AppColors.goldSoft,
            raised: true,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FROM',
                          style: AppTheme.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const Text('Omaha, USA', style: AppTheme.sectionTitle),
                      ],
                    ),
                    Icon(Icons.flight_takeoff_rounded, color: AppColors.navy),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'TO',
                          style: AppTheme.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const Text('Lomé, Togo', style: AppTheme.sectionTitle),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'OUR PRIMARY SHIPPING LANE',
                  style: AppTheme.caption.copyWith(
                    fontSize: 9,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _QuickCard extends StatelessWidget {
  final Color color;
  final String title;
  final String artworkAsset;
  final VoidCallback onTap;

  const _QuickCard({
    required this.color,
    required this.title,
    required this.artworkAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => LiftedSurface(
    color: color,
    child: Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: Image.asset(
                artworkAsset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ],
        ),
      ),
    ),
  );
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

class _WorkflowLine extends StatelessWidget {
  final String number, title, description;
  const _WorkflowLine({
    required this.number,
    required this.title,
    required this.description,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.blueSoft,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: AppColors.blue,
            fontSize: 11,
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
              title,
              style: AppTheme.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: AppTheme.caption.copyWith(fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    ],
  );
}

class _FutureService extends StatelessWidget {
  final String title;
  final String artworkAsset;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _FutureService({
    required this.title,
    required this.artworkAsset,
    required this.icon,
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
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFFFFD18A), size: 25),
                const Spacer(),
                SizedBox(
                  width: 92,
                  height: 80,
                  child: ShaderMask(
                    shaderCallback: (bounds) => RadialGradient(
                      center: const Alignment(.12, -.08),
                      radius: .88,
                      colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                      stops: const [.56, 1],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: ExcludeSemantics(
                      child: Image.asset(
                        artworkAsset,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'COMING SOON',
                style: TextStyle(
                  color: Color(0xFFFFD18A),
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
