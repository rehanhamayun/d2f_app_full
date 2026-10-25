import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/brand_ident_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/role_workspace_screen.dart';
import 'screens/staff_shell.dart';
import 'screens/splash_screen.dart';
import 'widgets/reference_widgets.dart';

void main() => runApp(const ProviderScope(child: D2FApp()));

class D2FApp extends StatefulWidget {
  const D2FApp({super.key});
  @override
  State<D2FApp> createState() => _D2FAppState();
}

class _D2FAppState extends State<D2FApp> {
  bool _apiReady = false;
  bool _identDone = false;
  String? _startupError;
  @override
  void initState() {
    super.initState();
    // The brand identity splash must hold long enough to read as an opening
    // frame, even when secure storage and session restore finish instantly.
    Future<void>.delayed(const Duration(milliseconds: 2300), () {
      if (mounted) setState(() => _identDone = true);
    });
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Api.I.init();
      if (mounted) {
        setState(() {
          _apiReady = true;
          _startupError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _startupError =
              'Could not open secure storage. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'D2F Shipping',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: const Color(0xFFF0EFEA),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxWidth),
            child: LayoutBuilder(
              builder: (context, constraints) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(
                    constraints.maxWidth,
                    MediaQuery.sizeOf(context).height,
                  ),
                ),
                child: child!,
              ),
            ),
          ),
        ),
      ),
    ),
    // Stage 1 of the launch: the animated brand ident always plays on cold
    // start (≥2.3s of hold). Secure storage failure only surfaces after the
    // ident finishes, so the error screen never flashes over the opening.
    home: (!_apiReady || !_identDone)
        ? const BrandIdentScreen()
        : _startupError == null
        ? const _RootSwitch()
        : Scaffold(
            backgroundColor: AppColors.cream,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_startupError!),
                  TextButton(
                    onPressed: _initialize,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
  );
}

enum _Entry { welcome, login, signup }

class _RootSwitch extends ConsumerStatefulWidget {
  const _RootSwitch();
  @override
  ConsumerState<_RootSwitch> createState() => _RootSwitchState();
}

class _RootSwitchState extends ConsumerState<_RootSwitch> {
  _Entry _entry = _Entry.welcome;
  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.valueOrNull != null &&
          next is AsyncData &&
          next.valueOrNull == null) {
        setState(() => _entry = _Entry.login);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final auth = ref.watch(authControllerProvider);
    Widget signedOut() => switch (_entry) {
      _Entry.welcome => SplashScreen(
        onSkip: () => setState(() => _entry = _Entry.login),
        onCreateAccount: () => setState(() => _entry = _Entry.signup),
      ),
      _Entry.login => LoginScreen(
        onBack: () => setState(() => _entry = _Entry.welcome),
      ),
      _Entry.signup => SignupScreen(
        onBack: () => setState(() => _entry = _Entry.welcome),
      ),
    };
    // Gently cross-fade between launch phases. One-shot transitions only,
    // so integration-driven pumpAndSettle always completes.
    Widget resolve() => auth.when(
      // Static hold: the ident already played in _D2FAppState; re-showing it
      // here would restart its choreography and read as a flicker.
      loading: () => const _HoldFrame(),
      error: (error, stack) => signedOut(),
      data: (user) => user == null
          ? signedOut()
          : user.isStaff
          ? const StaffShell()
          : const RoleWorkspaceScreen(),
    );
    final user = auth.valueOrNull;
    final phase = auth.isLoading
        ? 'hold'
        : user == null
        ? _entry.name
        : user.isStaff
        ? 'staff'
        : 'workspace';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey('launch-$phase'), child: resolve()),
    );
  }
}

/// Cream canvas with the bare brand wordmark: shown while the stored session
/// verifies against the server, between the ident and the first real screen.
class _HoldFrame extends StatelessWidget {
  const _HoldFrame();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.cream,
    body: const Center(
      child: IgnorePointer(child: BrandWordmark(fontSize: 34)),
    ),
  );
}
