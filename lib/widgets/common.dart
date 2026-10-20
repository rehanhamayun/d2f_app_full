import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Brand wordmark: "D2F Global" + golden plane, per the approved screens.
class BrandLogo extends StatelessWidget {
  final double fontSize;
  const BrandLogo({super.key, this.fontSize = 24});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'D2F Global',
      image: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(fontSize * .42),
              child: Image.asset(
                fontSize >= 32
                    ? 'assets/images/d2f_3.png'
                    : 'assets/images/d2f_2.png',
                width: fontSize * 1.65,
                height: fontSize * 1.65,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'D2F Global',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: fontSize * .83,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coral pill button with the circular arrow badge, per designs.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.coral.withValues(alpha: .18),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ]
              : [],
        ),
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.coral,
            disabledBackgroundColor: AppColors.coral.withValues(alpha: .45),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.only(left: 20, right: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  children: [
                    const SizedBox(width: 36),
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.arrow_right,
                        color: AppColors.coral,
                        size: 20,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// White pill button with navy border ("Register Another Parcel").
class OutlineButton2 extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const OutlineButton2({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.navy, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

/// White search field with magnifier + gold circular arrow, per designs.
class D2FSearchField extends StatefulWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmit;

  const D2FSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onSubmit,
  });

  @override
  State<D2FSearchField> createState() => _D2FSearchFieldState();
}

class _D2FSearchFieldState extends State<D2FSearchField> {
  final _localController = TextEditingController();
  TextEditingController get _controller =>
      widget.controller ?? _localController;

  @override
  void dispose() {
    _localController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: widget.onSubmit,
        style: AppTheme.body,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.navy),
          suffixIcon: Padding(
            padding: const EdgeInsets.all(6),
            child: IconButton(
              tooltip: 'Search parcels',
              onPressed: () => widget.onSubmit?.call(_controller.text),
              style: IconButton.styleFrom(backgroundColor: AppColors.gold),
              icon: const Icon(
                CupertinoIcons.arrow_right,
                color: AppColors.navy,
                size: 18,
              ),
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: AppColors.gold, width: 1.2),
          ),
        ),
      ),
    );
  }
}

/// Status pill chip: colored dot + label (e.g. "Delivered").
class StatusChip extends StatelessWidget {
  final String status;
  final EdgeInsets padding;
  final bool short;
  const StatusChip({
    super.key,
    required this.status,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    this.short = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = StatusVisual.of(status);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: v.chipBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: v.chipFg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            short ? statusShortLabel(status) : statusLabel(status),
            style: TextStyle(
              color: v.chipFg,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// White rounded section card used across all screens.
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color tint;
  final bool raised;
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tint = const Color(0xFFF2F6FF),
    this.raised = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, tint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Color.lerp(tint, AppColors.blue, .12)!),
        boxShadow: [
          if (raised)
            BoxShadow(
              color: Color.lerp(tint, AppColors.blue, .18)!,
              offset: const Offset(0, 5),
              blurRadius: 0,
            ),
          BoxShadow(
            color: AppColors.navy.withValues(alpha: raised ? .12 : .035),
            blurRadius: 22,
            offset: Offset(0, raised ? 10 : 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Small tinted info tile (Shipment Information grid / summary rows).
class InfoTile extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color iconColor;
  final String label;
  final String value;
  final String? sub;
  final VoidCallback? onTap;

  const InfoTile({
    super.key,
    required this.icon,
    required this.bg,
    required this.iconColor,
    required this.label,
    required this.value,
    this.sub,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      sub!,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.textGrey, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: AppTheme.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTheme.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

void showComingSoon(BuildContext context, String feature) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.schedule_rounded, color: AppColors.gold),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Coming soon', style: AppTheme.sectionTitle),
          ),
        ],
      ),
      content: Text(
        '$feature is planned for a later milestone of the D2F rollout. This build focuses on the Milestone 1 staff parcel foundation.',
        style: AppTheme.body.copyWith(color: AppColors.textGrey, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            'Got it',
            style: TextStyle(
              color: AppColors.coral,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

void copyToClipboard(
  BuildContext context,
  String text, {
  String message = 'Copied to clipboard',
}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1200),
    ),
  );
}

/// Brand header with a quick guide to the working staff tools.
class D2FHomeHeader extends StatelessWidget {
  final VoidCallback? onBell;
  const D2FHomeHeader({super.key, this.onBell});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const BrandLogo(),
        IconButton(
          tooltip: 'Staff guide',
          onPressed:
              onBell ??
              () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text(
                    'Your staff workspace',
                    style: AppTheme.sectionTitle,
                  ),
                  content: const Text(
                    'Register parcels in Ship, scan or enter a tracking number to find a parcel, and use Activity to review records. Open a parcel to update its status and view its timestamped history.',
                    style: AppTheme.body,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border),
          ),
          icon: const Icon(
            CupertinoIcons.question_circle,
            color: AppColors.navy,
            size: 23,
          ),
        ),
      ],
    );
  }
}

/// Illustration assets extracted from the supplied design references.
class ReferenceArt extends StatelessWidget {
  final String name;
  final double? width;
  final double? height;
  final BoxFit fit;
  const ReferenceArt(
    this.name, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/images/$name.jpg',
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
    ),
  );
}

class ScreenIntro extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? art;
  const ScreenIntro({
    super.key,
    required this.title,
    required this.subtitle,
    this.art,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFE1F1FF), Color(0xFFF0EFFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFD9E8FC)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.display),
              const SizedBox(height: 8),
              Text(subtitle, style: AppTheme.caption.copyWith(height: 1.5)),
            ],
          ),
        ),
        if (art != null) ...[
          const SizedBox(width: 8),
          SizedBox(width: 134, child: ReferenceArt(art!)),
        ],
      ],
    ),
  );
}

/// Keep names and route selections readable on compact staff devices.
class FormFieldPair extends StatelessWidget {
  final Widget first;
  final Widget second;
  const FormFieldPair({super.key, required this.first, required this.second});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 14), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );
}

/// A small amount of depth on primary action and summary cards.
class LiftedSurface extends StatelessWidget {
  final Color color;
  final Widget child;
  final double radius;
  const LiftedSurface({
    super.key,
    required this.color,
    required this.child,
    this.radius = 22,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Color.lerp(color, AppColors.navy, .22)!,
          offset: const Offset(0, 5),
          blurRadius: 0,
        ),
        BoxShadow(
          color: color.withValues(alpha: .23),
          offset: const Offset(0, 12),
          blurRadius: 22,
        ),
      ],
    ),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.lerp(color, Colors.white, .16)!,
              color,
              Color.lerp(color, AppColors.navy, .12)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: child,
      ),
    ),
  );
}
