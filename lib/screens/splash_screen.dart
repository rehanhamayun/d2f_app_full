import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/common.dart';

class SplashScreen extends StatelessWidget {
  final int stage;
  const SplashScreen({super.key, this.stage = 0});

  @override
  Widget build(BuildContext context) {
    final second = stage == 1;
    return Scaffold(
      body: BrandedBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLogo(fontSize: 36, light: true)),
                const SizedBox(height: 28),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(stage),
                    tween: Tween(begin: .94, end: 1),
                    duration: const Duration(milliseconds: 1800),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) =>
                        Transform.scale(scale: value, child: child),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF6),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .25),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .22),
                            blurRadius: 30,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        second
                            ? 'assets/images/warehouse.jpg'
                            : 'assets/images/journey.jpg',
                        fit: second ? BoxFit.cover : BoxFit.contain,
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  second
                      ? 'Every parcel.\nOne connected journey.'
                      : 'Bridging distances.\nBringing people closer.',
                  textAlign: TextAlign.center,
                  style: AppTheme.display.copyWith(
                    color: Colors.white,
                    fontSize: 29,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  second
                      ? 'Register. Scan. Follow every step.'
                      : 'From Omaha to Lomé, with care.',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(
                    color: const Color(0xFFBFD3F0),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 2; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: stage == i ? 32 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: stage == i ? AppColors.gold : Colors.white24,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    color: AppColors.gold,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
