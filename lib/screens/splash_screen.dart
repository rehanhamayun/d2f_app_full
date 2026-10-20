import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/common.dart';

/// Light, scrollable intro (design reference v3): two swipeable pages with
/// large brand artwork, tagline, decorative blobs and a coral "journey" pill.
/// No determinate loading bar; the user can swipe, tap Get Started or let the
/// pages auto-advance into the app.
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
  static const _ivory = Color(0xFFFCF8F1);
  static const _autoAdvance = Duration(milliseconds: 2600);

  final PageController _pages = PageController();
  Timer? _timer;
  bool _manual = false;
  late int _page;

  bool get _interactive => widget.onSkip != null;

  Iterable<_SplashPage> get _pagesData =>
      _interactive ? [_pageWorkspace(), _pageJourney()] : [_pageJourney()];

  _SplashPage _pageWorkspace() => _SplashPage(
    art: 'assets/images/login.jpg',
    headline: 'Your parcels.\nHandled with care.',
    caption: 'Preparing your workspace...',
  );

  _SplashPage _pageJourney() => _SplashPage(
    art: 'assets/images/journey.jpg',
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
    return Scaffold(
      backgroundColor: _ivory,
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

/// One full intro page, styled after the approved D2F artwork.
class _SplashPageView extends StatelessWidget {
  final _SplashPage data;
  final bool last;
  const _SplashPageView({required this.data, required this.last});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GestureDetector(
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 10, 26, 64),
          child: Column(
            children: [
              _CornerArt(),
              const SizedBox(height: 6),
              const BrandLogo(fontSize: 34, light: false),
              const SizedBox(height: 18),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: .96, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .10),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Image.asset(data.art, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Header row area reserved for decorative blobs (mirrors the artwork).
class _CornerArt extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 26,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          SizedBox(width: 4),
          _Blob(color: AppColors.coral, size: 22),
          SizedBox(width: 6),
          _Blob(color: AppColors.gold, size: 12),
        ],
      ),
    ),
  );
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
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
  const _SplashPage({
    required this.art,
    required this.headline,
    required this.caption,
  });
}
