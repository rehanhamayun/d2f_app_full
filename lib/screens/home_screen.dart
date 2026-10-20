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
            'Good things.\nGoing places.',
            style: AppTheme.display.copyWith(height: 1.1),
          ),
          const SizedBox(height: 6),
          Text(
            'Send a little closer to home.',
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
                    color: AppColors.coral,
                    title: 'Register\nparcel',
                    subtitle: 'Register a parcel\nfor a customer.',
                    icon: Icons.inventory_2_rounded,
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
                          color: AppColors.blue,
                          title: 'Track parcel',
                          subtitle: 'Scan or look up a parcel.',
                          icon: Icons.qr_code_scanner_rounded,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ScanScreen(),
                            ),
                          ),
                          compact: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Parcel records are the third primary M1 action.
                      Expanded(
                        child: _QuickCard(
                          color: AppColors.gold,
                          title: 'All parcels',
                          subtitle: 'View status and history.',
                          icon: Icons.inventory_2_outlined,
                          onTap: onGoActivity,
                          compact: true,
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
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  const _QuickCard({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = color == AppColors.gold;
    final foreground = dark ? AppColors.navy : Colors.white;
    return LiftedSurface(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -28,
              top: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: foreground.withValues(alpha: .1),
                    width: 22,
                  ),
                ),
              ),
            ),
            if (!compact)
              const Positioned(
                right: -8,
                bottom: 12,
                child: _ParcelDrawing(size: 100),
              ),
            Padding(
              padding: EdgeInsets.all(compact ? 13 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact) ...[
                    Icon(icon, color: foreground, size: 24),
                    const Spacer(),
                  ],
                  Text(
                    title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: compact ? 15 : 25,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: .85),
                      fontSize: compact ? 10 : 11,
                      height: 1.35,
                    ),
                  ),
                  if (!compact) ...[
                    const Spacer(),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (compact)
              Positioned(
                right: 10,
                top: 12,
                child: Icon(
                  Icons.arrow_outward_rounded,
                  color: foreground,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
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

/// Isometric parcel illustration for the main intake action.
class _ParcelDrawing extends StatelessWidget {
  final double size;
  const _ParcelDrawing({required this.size});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ParcelPainter()),
  );
}

class _ParcelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    Path polygon(List<Offset> points) {
      final p = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        p.lineTo(point.dx, point.dy);
      }
      return p..close();
    }

    final top = polygon([
      const Offset(8, 25),
      const Offset(60, 9),
      const Offset(94, 28),
      const Offset(43, 46),
    ]);
    final front = polygon([
      const Offset(8, 25),
      const Offset(43, 46),
      const Offset(43, 95),
      const Offset(8, 72),
    ]);
    final side = polygon([
      const Offset(43, 46),
      const Offset(94, 28),
      const Offset(94, 77),
      const Offset(43, 95),
    ]);
    canvas.drawShadow(side, Colors.black.withValues(alpha: .28), 7, true);
    canvas.drawPath(top, Paint()..color = const Color(0xFFFFE1AC));
    canvas.drawPath(front, Paint()..color = const Color(0xFFEBA766));
    canvas.drawPath(side, Paint()..color = const Color(0xFFFFC98E));
    canvas.drawPath(
      polygon([
        const Offset(29, 18),
        const Offset(40, 15),
        const Offset(75, 35),
        const Offset(64, 39),
      ]),
      Paint()..color = const Color(0xFFFF6A43),
    );
    canvas.drawPath(
      polygon([
        const Offset(64, 39),
        const Offset(75, 35),
        const Offset(75, 58),
        const Offset(64, 62),
      ]),
      Paint()..color = const Color(0xFFFF6A43),
    );
    final label = polygon([
      const Offset(53, 56),
      const Offset(86, 44),
      const Offset(86, 70),
      const Offset(53, 82),
    ]);
    canvas.drawPath(label, Paint()..color = Colors.white);
    final ink = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 1.3;
    for (var x = 58; x < 82; x += 3) {
      canvas.drawLine(
        Offset(x.toDouble(), 66 - (x - 58) * .35),
        Offset(x.toDouble(), 75 - (x - 58) * .35),
        ink,
      );
    }
    canvas.drawLine(const Offset(58, 60), const Offset(80, 52), ink);
    canvas.drawLine(const Offset(58, 63), const Offset(74, 57), ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
