import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Staff sign-in (design screen 2).
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
    return Scaffold(
      // Tapping empty space updates focus and reliably hides the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: BrandedBackdrop(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth.clamp(0.0, 440.0);
                  final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
                  final maxH = constraints.maxHeight;
                  // Illustration shrinks gracefully on short screens and hides
                  // entirely while the keyboard is up, without scale transforms
                  // around the form itself (field taps stay reliable).
                  final heroH = keyboard
                      ? 0.0
                      : (maxH - 568).clamp(120.0, 320.0);
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: maxH),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!keyboard) ...[
                            Row(
                              children: [
                                const BrandLogo(fontSize: 25, light: true),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Connection settings',
                                  onPressed: _editServerDialog,
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: heroH,
                              child: _illustration(height: heroH),
                            ),
                            const SizedBox(height: 18),
                          ],
                          _signInSection(width: width, keyboard: keyboard),
                          if (!keyboard) ...[
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: _contactAdminDialog,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                              ),
                              child: const Text.rich(
                                TextSpan(
                                  text: 'Need a staff account? ',
                                  children: [
                                    TextSpan(
                                      text: 'Contact D2F',
                                      style: TextStyle(
                                        color: Color(0xFFFFD075),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _illustration({required double height}) {
    final compact = height < 190;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF294A75), Color(0xFF18395F)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: FittedBox(
                // Text only — no editable text inside, so this transform is safe.
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A little closer\nto home.',
                        style: AppTheme.heading.copyWith(
                          color: Colors.white,
                          fontSize: compact ? 21 : 26,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'OMAHA  →  LOMÉ',
                        style: TextStyle(
                          color: Color(0xFFFFD075),
                          fontSize: 9,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 132,
            height: double.infinity,
            child: Image.asset(
              'assets/images/login.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.centerLeft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signInSection({required double width, required bool keyboard}) {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: width.clamp(0.0, 440.0)),
        padding: EdgeInsets.all(keyboard ? 18 : 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF183454), Color(0xFF102741)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white12),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFF07162E),
              offset: Offset(0, 6),
              blurRadius: 0,
            ),
            BoxShadow(
              color: Color(0x44000000),
              offset: Offset(0, 16),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome back.',
              style: AppTheme.heading.copyWith(
                color: Colors.white,
                fontSize: keyboard ? 23 : 29,
                letterSpacing: -.8,
              ),
            ),
            if (!keyboard) ...[
              const SizedBox(height: 6),
              const Text(
                'Sign in to your D2F workspace.',
                style: TextStyle(color: Color(0xFFB7C9DF), fontSize: 12),
              ),
            ],
            SizedBox(height: keyboard ? 14 : 22),
            const Text(
              'Email address',
              style: TextStyle(
                color: Color(0xFFC8D7E8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey('staff-email'),
              controller: _email,
              autofillHints: const [AutofillHints.username],
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Email address',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Password',
              style: TextStyle(
                color: Color(0xFFC8D7E8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey('staff-password'),
              controller: _password,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 32,
                  child: Checkbox(
                    value: _remember,
                    activeColor: AppColors.gold,
                    checkColor: AppColors.navy,
                    side: const BorderSide(color: Color(0xFFA4BAD5)),
                    onChanged: (v) => setState(() => _remember = v ?? true),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Remember me',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _forgotPasswordDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD075),
                    padding: const EdgeInsets.only(left: 4),
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
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
          ],
        ),
      ),
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

  void _contactAdminDialog() {
    _infoDialog(
      'Create an account',
      'Staff accounts are provisioned by the D2F Admin. Write to info@d2fshipping.com to request access.',
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
