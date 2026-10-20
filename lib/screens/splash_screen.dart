import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/common.dart';

/// Editorial intro (design reference v3): clean ivory canvas, decorative
/// brand blobs, free-flowing artwork (no card frames, borders or shadows)
/// and two swipeable pages that auto-advance into the workspace.
class SplashScreen extends StatefulWidget {
  final int stage;
  final VoidCallback? onSkip;

  /// [onSkip] == null renders a static single page (used while the auth
  /// session restores); otherwise the intro is swipeable and auto-advances.
  const SplashScreen({super.key, this.stage = 0, this.onSkip});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _autoAdvance = Duration(milliseconds: 2600);

  final PageController _pages = PageController();
  Timer? _timer;
  bool _manual = false;
  late int _page;

  bool get _interactive => widget.onSkip != null;

  Iterable<_SplashPage> get _pagesData =>
      _interactive ? [_pageWorkspace(), _pageJourney()] : [_pageJourney()];

  _SplashPage _pageWorkspace() => const _SplashPage(
    art: 'assets/images/login.jpg',
    canvas: Color(0xFFFDFBF4), // blends with the artwork's own ivory
    headline: 'Your parcels.\nHandled with care.',
    caption: 'Preparing your workspace...',
  );

  _SplashPage _pageJourney() => const _SplashPage(
    art: 'assets/images/journey.jpg',
    canvas: Color(0xFFFAF6EA), // blends with the artwork's own ivory
    headline: 'Bridging distances.\nBringing people closer.',
    caption: 'Loading your journey...',
  );

  @override
  void initState() {
    super.initState();
    _page = widget.stage.clamp(0, _pagesData.length - 1);
    _wasInteractive = _interactive;
    _scheduleAuto();
  }

  bool _wasInteractive = false;

  @override
  void didUpdateWidget(covariant SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The splash can mount before Api init resolves (onSkip == null); once it
    // becomes interactive, (re)start pacing.
    if (!_wasInteractive && _interactive) {
      _page = _page.clamp(0, _pagesData.length - 1);
      _scheduleAuto();
    }
    _wasInteractive = _interactive;
  }

  void _scheduleAuto() {
    if (!_interactive || _manual) return;
    _timer?.cancel();
    _timer = Timer(_autoAdvance, () {
      if (!mounted) return;
      if (_page < _pagesData.length - 1) {
        _pages.nextPage(
          duration: _interactive
              ? const Duration(milliseconds: 550)
              : Duration.zero,
          curve: Curves.easeOutCubic,
        );
      } else {
        widget.onSkip?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pagesData.toList(growable: false);
    // Scaffold tone follows the visible page so swipes never show a seam.
    final canvas = pages[_page.clamp(0, pages.length - 1)].canvas;
    return Scaffold(
      backgroundColor: canvas,
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null) {
            _manual = true; // swiping hands control to the user
            _timer?.cancel();
          }
          return false;
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: pages.length,
              onPageChanged: (i) {
                setState(() => _page = i);
                _scheduleAuto();
              },
              itemBuilder: (context, i) =>
                  _SplashPageView(data: pages[i], last: i == pages.length - 1),
            ),
            // Skip jumps straight into the workspace.
            if (_interactive)
              Positioned(
                top: 14,
                right: 18,
                child: SafeArea(
                  child: TextButton(
                    onPressed: widget.onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textGrey,
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            if (_interactive)
              Positioned(
                bottom: 26,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 26 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i
                              ? AppColors.coral
                              : const Color(0x33FF5139),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One full intro page: logo, edge-to-edge artwork, tagline and journey pill.
class _SplashPageView extends StatelessWidget {
  final _SplashPage data;
  final bool last;
  const _SplashPageView({required this.data, required this.last});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tapping the final page also enters the app (modern quick entry).
      onTap:
          last &&
              (context
                      .findAncestorStateOfType<_SplashScreenState>()
                      ?.widget
                      .onSkip !=
                  null)
          ? () => context
                .findAncestorStateOfType<_SplashScreenState>()
                ?.widget
                .onSkip
                ?.call()
          : null,
      child: Stack(
        children: [
          // Per-page soft-ivory canvas, blended with the artwork's own tone.
          Positioned.fill(child: ColoredBox(color: data.canvas)),
          // ── Decorative brand shapes (no cards, no shadows) ──────────────
          const Positioned(
            top: -70,
            left: -55,
            child: _Circle(96, AppColors.coral),
          ),
          Positioned(
            top: 74,
            left: 26,
            child: Transform.rotate(
              angle: -.8,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.gold, width: 1.6),
                ),
              ),
            ),
          ),
          const Positioned(
            top: 120,
            right: 44,
            child: _Circle(9, AppColors.coral),
          ),
          const Positioned(
            top: 150,
            right: 30,
            child: _Circle(5, AppColors.gold),
          ),
          // Soft clouds.
          const Positioned(top: 210, left: -26, child: _Cloud(width: 84)),
          const Positioned(top: 330, right: -34, child: _Cloud(width: 110)),
          // Bottom-right gold blob + coral flourish, echoing the artwork.
          const Positioned(
            bottom: -90,
            right: -60,
            child: _Circle(180, Color(0xFFF5C24B)),
          ),
          Positioned.fill(child: CustomPaint(painter: _CurvePainter())),

          // ── Content ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 22),
                // Wordmark with the little gold plane from the artwork.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const BrandLogo(fontSize: 30, light: false),
                    const SizedBox(width: 4),
                    Transform.rotate(
                      angle: .45,
                      child: const Icon(
                        Icons.flight_rounded,
                        color: AppColors.gold,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 14),
                        child: child,
                      ),
                    ),
                    // Free-flowing artwork: full-bleed, no frame, no shadow.
                    child: Image.asset(
                      data.art,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
                Text(
                  data.headline,
                  textAlign: TextAlign.center,
                  style: AppTheme.display.copyWith(
                    fontSize: 27,
                    height: 1.16,
                    letterSpacing: -.9,
                  ),
                ),
                const SizedBox(height: 8),
                const _GoldSwoosh(width: 150),
                const SizedBox(height: 16),
                const _JourneyPill(),
                const SizedBox(height: 10),
                Text(
                  data.caption,
                  style: AppTheme.caption.copyWith(
                    color: const Color(0xFF8A93A5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 74),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat brand circle (flat fill — deliberately shadow-free).
class _Circle extends StatelessWidget {
  final double size;
  final Color color;
  const _Circle(this.size, this.color);
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Soft cream cloud silhouette.
class _Cloud extends StatelessWidget {
  final double width;
  const _Cloud({required this.width});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * .34,
    child: CustomPaint(painter: _CloudPainter()),
  );
}

class _CloudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFF6EDDE);
    final h = size.height;
    canvas.drawCircle(Offset(size.width * .22, h * .68), h * .46, paint);
    canvas.drawCircle(Offset(size.width * .45, h * .42), h * .62, paint);
    canvas.drawCircle(Offset(size.width * .72, h * .66), h * .44, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * .62, size.width, h * .38),
        Radius.circular(h * .2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thin coral flourish tucked into the lower-left corner, clear of text.
class _CurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.coral.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * .025, size.height * .962)
      ..quadraticBezierTo(
        size.width * .055,
        size.height * .902,
        size.width * .115,
        size.height * .944,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Hand-painted style gold underline stroke.
class _GoldSwoosh extends StatelessWidget {
  final double width;
  const _GoldSwoosh({required this.width});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, 8), painter: _SwooshPainter());
}

class _SwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(6, 5.5)
      ..quadraticBezierTo(size.width * .5, 10, size.width - 6, 4);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Static coral flight-progress capsule from the artwork (decorative).
class _JourneyPill extends StatelessWidget {
  const _JourneyPill();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      width: 300,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.coral, Color(0xFFFF8A70)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 12,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EADC),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Transform.rotate(
              angle: .5,
              child: const Icon(
                Icons.flight_rounded,
                color: AppColors.gold,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashPage {
  final String art, headline, caption;
  final Color canvas;
  const _SplashPage({
    required this.art,
    required this.canvas,
    required this.headline,
    required this.caption,
  });
}
