import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../widgets/reference_widgets.dart';

/// Stage 1 of the launch experience: the brand identity splash.
///
/// Plays a one-shot entrance choreography (wordmark pop-in, illustration
/// reveal, tagline, drawn gold underline) followed by a repeating plane
/// glide across the loading bar. It does not navigate: `main` replaces it
/// with the welcome intro, the sign-in screen or the signed-in workspace
/// once early work has finished, so identical frames never re-run the
/// choreography (which would look like a flicker).
class BrandIdentScreen extends StatefulWidget {
  const BrandIdentScreen({super.key});

  @override
  State<BrandIdentScreen> createState() => _BrandIdentScreenState();
}

class _BrandIdentScreenState extends State<BrandIdentScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _flight;
  late final Animation<double> _wordmark;
  late final Animation<double> _art;
  late final Animation<double> _tagline;
  late final Animation<double> _underline;
  late final Animation<double> _controls;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();

    _wordmark = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.0, 0.42, curve: Curves.easeOutBack),
      ),
    );
    _art = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.18, 0.66, curve: Curves.easeOut),
      ),
    );
    _tagline = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.45, 0.82, curve: Curves.easeOut),
      ),
    );
    _underline = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.60, 0.93, curve: Curves.easeOutCubic),
      ),
    );
    _controls = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.76, 1.0, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: IllustrationSplashBackground(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final artHeight =
                              (constraints.maxHeight * .44).clamp(210.0, 340.0);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ScaleTransition(
                                scale: Tween(begin: 0.86, end: 1.0).animate(
                                  _wordmark,
                                ),
                                child: FadeTransition(
                                  opacity: _wordmark,
                                  child: const Center(
                                    child: IgnorePointer(
                                      child: BrandWordmark(fontSize: 40),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 26),
                              FadeTransition(
                                opacity: _art,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, .05),
                                    end: Offset.zero,
                                  ).animate(_art),
                                  child: Center(
                                    child: ExcludeSemantics(
                                      child: Image.asset(
                                        'assets/images/journey.jpg',
                                        height: artHeight,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.high,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              FadeTransition(
                                opacity: _tagline,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, .12),
                                    end: Offset.zero,
                                  ).animate(_tagline),
                                  child: const IgnorePointer(
                                    child: Text(
                                      'Bridging distances.\nBringing people closer.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.navy,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1.1,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Gold underline draws in, matching the reference
                              // hand-drawn flourish under the brand promise.
                              Align(
                                alignment: Alignment.center,
                                child: AnimatedBuilder(
                                  animation: _underline,
                                  builder: (context, child) {
                                    return FadeTransition(
                                      opacity: _tagline,
                                      child: Container(
                                        width: 92 * _underline.value,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          color: AppColors.gold,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(4),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 18),
                              FadeTransition(
                                opacity: _controls,
                                child: Center(
                                  child: SizedBox(
                                    width: 230,
                                    child: FlightLoadingBar(sweep: _flight),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FadeTransition(
                                opacity: _controls,
                                child: const IgnorePointer(
                                  child: Text(
                                    'Loading your journey…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Coral loading bar with a golden plane gliding across, mirroring the
/// reference splash art's "flight progress" treatment.
class FlightLoadingBar extends StatelessWidget {
  final Animation<double> sweep;
  const FlightLoadingBar({super.key, required this.sweep});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: sweep,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 26;
        final progress = sweep.value.clamp(0.0, 1.0);
        return SizedBox(
          height: 24,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.coralSoft,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 0,
                child: Container(
                  height: 6,
                  width: width * progress + 4,
                  decoration: const BoxDecoration(
                    color: AppColors.coral,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              ),
              Positioned(
                top: 1,
                left: width * progress,
                child: Transform.rotate(
                  angle: .45,
                  child: const Icon(
                    Icons.flight_rounded,
                    size: 21,
                    color: AppColors.gold,
                          ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
