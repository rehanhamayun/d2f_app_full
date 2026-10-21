import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';

class BrandWordmark extends StatelessWidget {
  final double fontSize;
  final bool light;
  const BrandWordmark({super.key, this.fontSize = 23, this.light = false});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'D2F Global',
    image: true,
    child: ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'D2F Global',
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                color: light ? Colors.white : AppColors.navy,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
                height: 1.1,
              ),
            ),
            const SizedBox(width: 4),
            Transform.rotate(
              angle: math.pi / 4,
              child: Icon(
                Icons.flight_rounded,
                size: fontSize * 1.25,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReferenceActionCard extends StatelessWidget {
  final String title, subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final String? artwork;
  const ReferenceActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
    this.artwork,
  });
  @override
  Widget build(BuildContext context) {
    final fg = color == AppColors.yellow || color == AppColors.goldSoft
        ? AppColors.navy
        : Colors.white;
    return Semantics(
      button: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, c) {
                final short = c.maxHeight < 130;
                final narrow = c.maxWidth < 100;
                if (short) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: fg, size: 25),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: fg,
                            size: 17,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        style: TextStyle(
                          color: fg,
                          fontSize: narrow ? 13 : 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: fg.withValues(alpha: .9),
                          fontSize: 9,
                          height: 1.2,
                        ),
                      ),
                    ],
                  );
                }
                return Stack(
                  children: [
                    if (artwork != null)
                      Positioned(
                        right: -8,
                        bottom: -5,
                        child: Image.asset(
                          artwork!,
                          width: c.maxWidth * .48,
                          excludeFromSemantics: true,
                        ),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: fg, size: narrow ? 29 : 35),
                        const SizedBox(height: 11),
                        Text(
                          title,
                          style: TextStyle(
                            color: fg,
                            fontSize: narrow ? 15 : 23,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.6,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: fg.withValues(alpha: .9),
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: fg == Colors.white ? color : AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardMetric extends StatelessWidget {
  final String title, value, caption;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  const DashboardMetric({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: tint,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 27, color: AppColors.navy),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 8.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ShipmentRecordTile extends StatelessWidget {
  final Parcel parcel;
  final VoidCallback onTap;
  const ShipmentRecordTile({
    super.key,
    required this.parcel,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final visual = StatusVisual.of(parcel.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 44,
                  child: Image.asset(
                    'assets/images/parcel.jpg',
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parcel.trackingId,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: visual.chipBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusShortLabel(parcel.status),
                              style: TextStyle(
                                color: visual.chipFg,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            DateFormat('MMM d · h:mm a')
                                .format(parcel.updatedAt.toLocal()),
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        parcel.destination,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textGrey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class IllustrationSplashBackground extends StatelessWidget {
  final Widget child;
  const IllustrationSplashBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: AppColors.cream),
      Positioned(
        left: -100,
        top: -100,
        child: Container(
          width: 170,
          height: 220,
          decoration: const BoxDecoration(
            color: AppColors.coral,
            borderRadius: BorderRadius.all(Radius.circular(120)),
          ),
        ),
      ),
      Positioned(
        right: -95,
        bottom: -100,
        child: Container(
          width: 220,
          height: 235,
          decoration: const BoxDecoration(
            color: AppColors.yellow,
            borderRadius: BorderRadius.all(Radius.circular(120)),
          ),
        ),
      ),
      child,
    ],
  );
}

class ParcelSummaryCard extends StatelessWidget {
  final String trackingId, status, method;
  final VoidCallback? onCopy;
  const ParcelSummaryCard({
    super.key,
    required this.trackingId,
    required this.status,
    required this.method,
    this.onCopy,
  });
  @override
  Widget build(BuildContext context) {
    final visual = StatusVisual.of(status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tracking Number',
                  style: TextStyle(fontSize: 11, color: AppColors.textGrey),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  trackingId,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: visual.chipBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    statusLabel(status),
                    style: TextStyle(
                      fontSize: 14,
                      color: visual.chipFg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '$method shipment. ${status == 'DELIVERED' ? 'Journey complete.' : 'Follow every recorded update below.'}',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  'assets/images/tracking_globe_reference.png',
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
                if (onCopy != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Copy tracking number',
                      onPressed: onCopy,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .85),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
