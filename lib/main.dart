import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/staff_only_gate.dart';
import 'screens/login_screen.dart';
import 'screens/staff_shell.dart';
import 'widgets/common.dart';

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

  @override
  void initState() {
    super.initState();
    // Initialize secure storage + dio before the auth controller runs.
    Api.I.init().then((_) {
      if (mounted) setState(() => _apiReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D2F Global',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: _apiReady
          ? const _RootSwitch()
          : const SplashScreen(), // brief warm-up while storage initializes
    );
  }
}

/// Root gate: routes based on the global auth session.
class _RootSwitch extends ConsumerWidget {
  const _RootSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return auth.when(
      loading: () => const SplashScreen(),
      error: (e, _) => const LoginScreen(),
      data: (user) {
        if (user == null) return const LoginScreen();
        if (user.isStaff) return const StaffShell();
        return const StaffOnlyGate();
      },
    );
  }
}

/// Branded splash screen (design screen 1).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -80,
            left: -80,
            child: _blob(AppColors.coral.withValues(alpha: 0.15), 220),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: _blob(AppColors.gold.withValues(alpha: 0.18), 200),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandLogo(fontSize: 40),
                const SizedBox(height: 32),
                const Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28),
                    child: ReferenceArt('journey', height: 330),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Bridging distances.\nBringing people closer.',
                  textAlign: TextAlign.center,
                  style: AppTheme.heading.copyWith(
                    fontSize: 24,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 60),
                const SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    backgroundColor: Color(0xFFF1E4D2),
                    color: AppColors.coral,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Loading your journey…', style: AppTheme.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
