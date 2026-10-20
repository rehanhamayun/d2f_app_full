import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';
import 'signup_screen.dart';

/// Staff sign-in (design v4): full-bleed navy travel artwork on top,
/// "Welcome back." over the art, and a white sheet whose top corners sweep
/// up like the reference. Labels above fields, coral CTA, email-keyboard safe.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _remember = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authControllerProvider.notifier)
          .signIn(email, password, remember: _remember);
      if (!user.isStaff && mounted) {
        // Roles outside M1 scope cannot enter the staff app.
        await ref.read(authControllerProvider.notifier).signOut();
        setState(() {
          _error = 'This account does not have access to the staff workspace. Please contact D2F for assistance.';
          _loading = false;
        });
        return;
      }
      // Successful sign-in: _RootSwitch rebuilds into StaffShell automatically.
      if (mounted) setState(() => _loading = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Sign-in failed. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status-bar icons over the blue artwork.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/login_hero.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(0, .5),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x260B1B46)),
            ),
            GestureDetector(
              // Tapping empty space updates focus and reliably hides the keyboard.
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SafeArea(
                top: false,
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final keyboard =
                        MediaQuery.viewInsetsOf(context).bottom > 0;
                    final maxH = constraints.maxHeight;
                    // Give the artwork a generous, edge-to-edge portion of the
                    // viewport. The form sheet scrolls independently on short
                    // screens and yields the space back to the keyboard.
                    final heroH = keyboard
                        ? 0.0
                        : (maxH * .44).clamp(260.0, 420.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (heroH > 0)
                          _Hero(
                            height: heroH,
                            onServer: _editServerDialog,
                            onServerVisible: !keyboard,
                          ),
                        Expanded(
                          child: Container(
                            // Bright white sheet with the reference's big top curve.
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .96),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(34),
                                topRight: Radius.circular(34),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: _form(maxH),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(double maxH) {
    final dense = maxH < 760;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Field(
          fieldKey: const ValueKey('staff-email'),
          label: 'Email address',
          icon: Icons.mail_outline_rounded,
          controller: _email,
          autofillHints: const [AutofillHints.username],
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          hint: 'you@example.com',
        ),
        SizedBox(height: dense ? 10 : 14),
        _Field(
          fieldKey: const ValueKey('staff-password'),
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          controller: _password,
          autofillHints: const [AutofillHints.password],
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          hint: 'Enter your password',
          suffix: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
              color: AppColors.textGrey,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Text(
              'Remember me',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 20,
              height: 26,
              child: Checkbox(
                value: _remember,
                activeColor: AppColors.coral,
                checkColor: Colors.white,
                side: const BorderSide(color: AppColors.border, width: 1.3),
                onChanged: (v) => setState(() => _remember = v ?? true),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _forgotPasswordDialog,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.blue,
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 34),
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.coralSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFB3281D),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Sign In',
          loading: _loading,
          onPressed: _loading ? null : _submit,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: _Hairline()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'or continue with',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .1,
                ),
              ),
            ),
            const Expanded(child: _Hairline()),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _googleHintDialog,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.navy,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _GoogleG(size: 19),
              const SizedBox(width: 10),
              Text(
                'Sign in with Google',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _loading
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignupScreen(),
                    ),
                  ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textGrey,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            child: const Text.rich(
              TextSpan(
                text: 'New to D2F? ',
                children: [
                  TextSpan(
                    text: 'Create account',
                    style: TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  /// Lets the user (or a demo phone) point the app at the D2F backend before
  /// signing in — the Account tab override otherwise requires a session.
  void _editServerDialog() {
    final controller = TextEditingController(text: Api.I.currentBaseUrl);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'D2F server address',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Full base URL of the staff backend, e.g.\n'
              '- Demo Wi-Fi: http://192.168.1.20:4000\n'
              '- USB (adb reverse): http://127.0.0.1:4000',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textGrey,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.dns_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final nav = Navigator.of(dialogContext);
              await Api.I.setBaseUrl(controller.text);
              if (mounted) {
                setState(() {}); // refresh label
                nav.pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _forgotPasswordDialog() {
    _infoDialog(
      'Password reset',
      'Contact your D2F administrator at info@d2fshipping.com to reset your staff password.',
    );
  }

  void _googleHintDialog() {
    _infoDialog(
      'Google sign-in',
      'Staff workspaces sign in with email accounts today. Google sign-in arrives with the upcoming customer app.',
    );
  }

  void _infoDialog(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTheme.sectionTitle),
        content: Text(
          body,
          style: AppTheme.body.copyWith(
            color: AppColors.textGrey,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
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
}

/// Hero header: full-bleed artwork, D2F wordmark on top, headline below.
class _Hero extends StatelessWidget {
  final double height;
  final VoidCallback onServer;
  final bool onServerVisible;

  const _Hero({
    required this.height,
    required this.onServer,
    required this.onServerVisible,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bottom scrim keeps the headline legible over the sea artwork.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0x880B1B46),
                    Color(0x140B1B46),
                    Colors.transparent,
                  ],
                  stops: [0, .38, .68],
                ),
              ),
            ),
          ),
          // Top scrim for the wordmark.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x330B1B46), Colors.transparent],
                  stops: [0, .4],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 12, 0),
              child: Row(
                children: [
                  const BrandLogo(fontSize: 24, light: true),
                  const Spacer(),
                  if (onServerVisible)
                    IconButton(
                      tooltip: 'Connection settings',
                      onPressed: onServer,
                      icon: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 20,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome back.',
                  style: AppTheme.heading.copyWith(
                    color: Colors.white,
                    fontSize: 30,
                    letterSpacing: -.9,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Your shipments, one tap away.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

/// Labelled input used across the auth sheets.
class _Field extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final Key? fieldKey;
  final List<String>? autofillHints;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final Widget? suffix;

  const _Field({
    this.fieldKey,
    required this.label,
    required this.icon,
    required this.controller,
    this.autofillHints,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
    required this.hint,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: -.1,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          key: fieldKey,
          controller: controller,
          autofillHints: autofillHints,
          autocorrect: false,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          enableSuggestions: !obscureText,
          obscuringCharacter: '●',
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            prefixIconColor: AppColors.navy,
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFFBFCFE),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
      ],
    );
  }
}

/// Soft grey divider used by the "or continue with" row.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.border);
}

/// The multicolour Google "G", hand-painted (no external package).
class _GoogleG extends StatelessWidget {
  final double size;
  const _GoogleG({required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _GoogleGPainter()),
  );
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .175;
    final r = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: r,
    );
    Paint seg(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Canvas: 0° = right, 90° = bottom, sweep clockwise.
    canvas.drawArc(
      rect,
      _deg(190),
      _deg(130),
      false,
      seg(const Color(0xFF4285F4)),
    ); // left/top-left
    canvas.drawArc(
      rect,
      _deg(320),
      _deg(70),
      false,
      seg(const Color(0xFFEA4335)),
    ); // top
    canvas.drawArc(
      rect,
      _deg(30),
      _deg(60),
      false,
      seg(const Color(0xFF34A853)),
    ); // bottom-right
    canvas.drawArc(
      rect,
      _deg(90),
      _deg(100),
      false,
      seg(const Color(0xFFFBBC05)),
    ); // bottom-left
    // The blue crossbar sweeping into the centre from the ring's right side.
    final h = size.height / 2;
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
        size.width / 2 - stroke * .1,
        h - stroke / 2,
        size.width / 2 + stroke * .6,
        stroke,
      ),
      bar,
    );
  }

  static double _deg(double d) => d * 3.1415926535897932 / 180;

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}
