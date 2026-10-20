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
                    subtitle: 'Create a record and print\nits shipping label.',
                    icon: Icons.inventory_2_rounded,
                    art: const Positioned(
                      right: -8,
                      bottom: 12,
                      child: _ParcelDrawing(size: 100),
                    ),
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
                          subtitle:
                              'Scan the label or look\nup a tracking number.',
                          icon: Icons.qr_code_scanner_rounded,
                          art: const Positioned(
                            right: -2,
                            bottom: 4,
                            child: _ScanDrawing(size: 96),
                          ),
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
                          color: AppColors.deepTeal,
                          title: 'All parcels',
                          subtitle:
                              'Every shipment, acting on\nits latest status.',
                          icon: Icons.inventory_2_outlined,
                          art: const Positioned(
                            right: -2,
                            bottom: 4,
                            child: _CrateStackDrawing(size: 96),
                          ),
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

          const Text('More from D2F', style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FutureService(
                  title: 'Marketplace',
                  icon: Icons.storefront_outlined,
                  color: AppColors.deepPurple,
                  art: 'parcel',
                  onTap: () => showComingSoon(context, 'D2F Marketplace'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FutureService(
                  title: 'Buy For Me',
                  icon: Icons.shopping_bag_outlined,
                  color: AppColors.deepTeal,
                  art: 'success',
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
  final String subtitle;
  final IconData icon;
  final Widget? art;
  final VoidCallback onTap;
  final bool compact;

  const _QuickCard({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.art,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const foreground = Colors.white;
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
            if (art != null) art!,
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

/// Radar / scan-frame artwork for the tracking action: concentric rings
/// sweeping a labelled scan frame — reads as "follow the parcel live".
class _ScanDrawing extends StatelessWidget {
  final double size;
  const _ScanDrawing({required this.size});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ScanPainter()),
  );
}

class _ScanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final center = const Offset(52, 52);

    // Faint concentric signal rings (largest first, behind the frame).
    final rings = [46.0, 36.0, 26.0];
    for (var i = 0; i < rings.length; i++) {
      canvas.drawCircle(
        center,
        rings[i],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.3 - i * .55
          ..color = Colors.white.withValues(alpha: .30 - i * .08),
      );
    }

    // Radar sweep wedge.
    final sweep = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: .32),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 46));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.6);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 46),
      0,
      1.15,
      true,
      sweep,
    );
    canvas.restore();

    // Label sheet (the parcel's live record) tilted in 3D perspective.
    Path polygon(List<Offset> points) {
      final p = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        p.lineTo(point.dx, point.dy);
      }
      return p..close();
    }

    final sheet = polygon([
      const Offset(30, 26),
      const Offset(74, 16),
      const Offset(80, 62),
      const Offset(36, 74),
    ]);
    canvas.drawShadow(sheet, Colors.black.withValues(alpha: .45), 8, true);
    canvas.drawPath(sheet, Paint()..color = Colors.white);
    final labelLine = Paint()
      ..color = AppColors.deepBlue.withValues(alpha: .85)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(39, 33), const Offset(66, 27), labelLine);
    canvas.drawLine(const Offset(40, 40), const Offset(63, 35), labelLine);
    // Tracking dashes across the sheet.
    final dash = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(38, 52), Offset(58, 47.5), dash);
    canvas.drawLine(const Offset(61.5, 46.8), Offset(64, 46.2), dash);

    // Scan frame corners around the sheet.
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    void cornerMark(Offset a, Offset b) => canvas.drawLine(a, b, corner);
    cornerMark(const Offset(22, 22), const Offset(34, 19));
    cornerMark(const Offset(85, 10), const Offset(87, 22));
    cornerMark(const Offset(87, 55), const Offset(80, 66));
    cornerMark(const Offset(32, 84), const Offset(42, 82));

    // Signal dot.
    canvas.drawCircle(
      const Offset(20, 48),
      3.4,
      Paint()..color = AppColors.gold,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Isometric crate stack for the parcel-records action: a warehouse stack of
/// three labelled boxes — one shelf view of every shipment on file.
class _CrateStackDrawing extends StatelessWidget {
  final double size;
  const _CrateStackDrawing({required this.size});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _CrateStackPainter()),
  );
}

class _CrateStackPainter extends CustomPainter {
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

    void box(
      Offset o,
      double w,
      double h, {
      required Color top,
      required Color front,
      required Color side,
      bool label = false,
    }) {
      final topFace = polygon([
        o,
        Offset(o.dx + w * .55, o.dy - w * .28),
        Offset(o.dx + w * .95, o.dy - w * .28 + h * .24),
        Offset(o.dx + w * .40, o.dy + h * .26),
      ]);
      final frontFace = polygon([
        o,
        Offset(o.dx + w * .40, o.dy + h * .26),
        Offset(o.dx + w * .40, o.dy + h * .26 + h * .62),
        Offset(o.dx, o.dy + h * .88),
      ]);
      final sideFace = polygon([
        Offset(o.dx + w * .40, o.dy + h * .26),
        Offset(o.dx + w * .95, o.dy - w * .28 + h * .24),
        Offset(o.dx + w * .95, o.dy - w * .28 + h * .24 + h * .62),
        Offset(o.dx + w * .40, o.dy + h * .88),
      ]);
      canvas.drawShadow(sideFace, Colors.black.withValues(alpha: .30), 6, true);
      canvas.drawPath(topFace, Paint()..color = top);
      canvas.drawPath(frontFace, Paint()..color = front);
      canvas.drawPath(sideFace, Paint()..color = side);
      if (label) {
        final white = Paint()..color = Colors.white;
        canvas.drawPath(
          polygon([
            Offset(o.dx + w * .06, o.dy + h * .34),
            Offset(o.dx + w * .30, o.dy + h * .26),
            Offset(o.dx + w * .30, o.dy + h * .66),
            Offset(o.dx + w * .06, o.dy + h * .74),
          ]),
          white,
        );
        final ink = Paint()
          ..color = AppColors.deepTeal.withValues(alpha: .8)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            Offset(o.dx + w * .09, o.dy + h * (.40 + i * .09)),
            Offset(o.dx + w * .27, o.dy + h * (.32 + i * .09)),
            ink,
          );
        }
      }
    }

    // Ground shadow.
    canvas.drawOval(
      Rect.fromLTWH(14, 86, 74, 10),
      Paint()..color = Colors.black.withValues(alpha: .14),
    );

    // Bottom big crate, middle crate offset, small crate on top — solid stack.
    box(
      const Offset(16, 62),
      46,
      30,
      top: const Color(0xFFF3D9A4),
      front: const Color(0xFFE3AF6D),
      side: const Color(0xFFEDC189),
      label: true,
    );
    box(
      const Offset(58, 58),
      34,
      22,
      top: const Color(0xFFF6E3B8),
      front: const Color(0xFFE8BA80),
      side: const Color(0xFFF0C790),
    );
    box(
      const Offset(30, 34),
      36,
      24,
      top: const Color(0xFFEFCA92),
      front: const Color(0xFFD9A463),
      side: const Color(0xFFE4B375),
      label: true,
    );
    box(
      const Offset(64, 34),
      26,
      18,
      top: const Color(0xFFF7E7C6),
      front: const Color(0xFFEDC491),
      side: const Color(0xFFF5D5A8),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FutureService extends StatelessWidget {
  final String title, art;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _FutureService({
    required this.title,
    required this.art,
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ReferenceArt(
                    art,
                    width: 52,
                    height: 48,
                    fit: BoxFit.cover,
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
