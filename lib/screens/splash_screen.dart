import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/reference_widgets.dart';

class SplashScreen extends StatefulWidget {
  final int stage;
  final VoidCallback? onSkip, onCreateAccount;
  const SplashScreen({
    super.key,
    this.stage = 0,
    this.onSkip,
    this.onCreateAccount,
  });
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final PageController _pages;
  late int _page;
  static const _art = ['journey', 'login', 'success'];
  @override
  void initState() {
    super.initState();
    _page = widget.stage.clamp(0, 2);
    _pages = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onSkip != null || widget.onCreateAccount != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: IllustrationSplashBackground(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.invertedStylus,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: PageView.builder(
                      key: const ValueKey('splash-backgrounds'),
                      controller: _pages,
                      itemCount: _art.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, i) => LayoutBuilder(
                        builder: (context, c) => Padding(
                          padding: EdgeInsets.fromLTRB(
                            12,
                            c.maxHeight * .16,
                            12,
                            c.maxHeight * (interactive ? .43 : .34),
                          ),
                          child: Image.asset(
                            'assets/images/${_art[i]}.jpg',
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: AuthFit(
                      minHeight: interactive ? 650 : 540,
                      builder: (height) => Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const IgnorePointer(
                              child: Center(child: BrandWordmark(fontSize: 34)),
                            ),
                            if (interactive)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: widget.onSkip,
                                  child: const Text(
                                    'Skip',
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            const Spacer(),
                            // Each page tells its own story: identity,
                            // registration, tracking — synced to the artwork.
                            IgnorePointer(
                              child: AnimatedSwitcher(
                                key: const ValueKey('splash-stories'),
                                duration: const Duration(milliseconds: 280),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeIn,
                                child: Column(
                                  key: ValueKey('splash-story-$_page'),
                                  children: [
                                    Text(
                                      const [
                                        'Bridging distances.\nBringing people closer.',
                                        'Register and label\nevery shipment.',
                                        'Track each parcel\nuntil it arrives.',
                                      ][_page],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.navy,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1.1,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      const [
                                        'USA & Europe ↔ West Africa',
                                        'Instant tracking IDs, QR codes and labels.',
                                        'Printed-code scanning keeps history at hand.',
                                      ][_page],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.textGrey,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const IgnorePointer(
                              child: Center(
                                child: SizedBox(
                                  width: 92,
                                  height: 4,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.gold,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (interactive) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  _art.length,
                                  (i) => Semantics(
                                    label:
                                        'Background ${i + 1} of ${_art.length}',
                                    selected: _page == i,
                                    button: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _pages.animateToPage(
                                        i,
                                        duration: const Duration(
                                          milliseconds: 350,
                                        ),
                                        curve: Curves.easeOutCubic,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 12,
                                        ),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          width: _page == i ? 24 : 7,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: _page == i
                                                ? AppColors.coral
                                                : AppColors.border,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              GoldButton(
                                key: const ValueKey('splash-create-account'),
                                label: 'Create an Account',
                                onPressed: widget.onCreateAccount,
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  key: const ValueKey('splash-sign-in'),
                                  onPressed: widget.onSkip,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.navy,
                                    side: const BorderSide(
                                      color: AppColors.navy,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: const Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 30),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 60),
                                child: LinearProgressIndicator(
                                  color: AppColors.coral,
                                  backgroundColor: AppColors.coralSoft,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(10),
                                  ),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Loading your journey…',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textGrey,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
