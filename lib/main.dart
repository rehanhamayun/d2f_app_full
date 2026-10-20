import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/staff_only_gate.dart';
import 'screens/login_screen.dart';
import 'screens/staff_shell.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const ProviderScope(child: D2FApp()));
}

class D2FApp extends StatefulWidget {
  const D2FApp({super.key});

  @override
  State<D2FApp> createState() => _D2FAppState();
}

class _D2FAppState extends State<D2FApp> {
  bool _apiReady = false;
  int _stage = 0;
  Timer? _first;
  Timer? _second;
  bool _preparingArtwork = false;

  @override
  void initState() {
    super.initState();
    // Initialize secure storage + dio before the auth controller runs.
    Api.I.init().then((_) {
      if (mounted) setState(() => _apiReady = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preparingArtwork) return;
    _preparingArtwork = true;
    // Start the timed sequence after local artwork has decoded, so a cold
    // launch never skips an illustration while the image cache warms up.
    Future.wait([
      for (final asset in [
        'journey.jpg',
        'warehouse.jpg',
        'login.jpg',
        'd2f_2.png',
        'd2f_3.png',
      ])
        precacheImage(AssetImage('assets/images/$asset'), context),
    ]).then((_) {
      if (!mounted) return;
      _first = Timer(const Duration(milliseconds: 2800), () {
        if (mounted) setState(() => _stage = 1);
      });
      _second = Timer(const Duration(milliseconds: 5600), () {
        if (mounted) setState(() => _stage = 2);
      });
    });
  }

  @override
  void dispose() {
    _first?.cancel();
    _second?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D2F Global',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: child!,
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _apiReady && _stage == 2
            ? const _RootSwitch(key: ValueKey('application'))
            : SplashScreen(
                key: ValueKey('splash-$_stage'),
                stage: _stage.clamp(0, 1),
              ),
      ),
    );
  }
}

/// Root gate: routes based on the global auth session.
class _RootSwitch extends ConsumerWidget {
  const _RootSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return auth.when(
      loading: () => const SplashScreen(stage: 1),
      error: (e, _) => const LoginScreen(),
      data: (user) {
        if (user == null) return const LoginScreen();
        if (user.isStaff) return const StaffShell();
        return const StaffOnlyGate();
      },
    );
  }
}
