import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/reference_widgets.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const LoginScreen({super.key, this.onBack});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _obscure = true, _loading = false;
  bool _socialPending = false, _remember = true;
  int _socialAttempt = 0;

  @override
  void dispose() {
    _socialAttempt++;
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      authMessage(context, 'Please enter a valid email address.');
      return;
    }
    if (_password.text.isEmpty) {
      authMessage(context, 'Please enter your password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(_email.text.trim(), _password.text, remember: _remember);
      if (mounted) TextInput.finishAutofillContext();
    } on ApiException catch (error) {
      if (mounted) authMessage(context, error.message);
    } catch (_) {
      if (mounted) authMessage(context, 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _social(String provider) async {
    if (_loading) return;
    final attempt = ++_socialAttempt;
    bool active() => mounted && attempt == _socialAttempt;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _socialPending = true;
    });
    try {
      final flow = await Api.I.startSocialSignIn(provider);
      if (!active()) return;
      if (!await launchUrl(
        Uri.parse(flow['url'] as String),
        mode: LaunchMode.externalApplication,
      )) {
        throw ApiException(
          'Could not open your browser. Please use email sign-in.',
        );
      }
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (active() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!active()) return;
        final user = await Api.I.completeSocialSignIn(
          flow['id'] as String,
          flow['secret'] as String,
          isActive: active,
        );
        if (user != null && active()) {
          ref.read(authControllerProvider.notifier).acceptSession(user);
          return;
        }
      }
      if (mounted && active()) {
        authMessage(context, 'Sign-in expired. Please try again.');
      }
    } on ApiException catch (error) {
      if (mounted && active()) authMessage(context, error.message);
    } catch (_) {
      if (mounted && active()) {
        authMessage(context, 'Unable to complete sign-in. Please try again.');
      }
    } finally {
      if (active()) {
        setState(() {
          _loading = false;
          _socialPending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: authCanvas,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SafeArea(
                child: AuthFit(
                  minHeight: keyboard ? 390 : 650,
                  builder: (height) {
                    final compact = keyboard || height < 730;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onLongPress: _serverDialog,
                                    child: const Align(
                                      alignment: Alignment.centerLeft,
                                      child: BrandWordmark(fontSize: 23),
                                    ),
                                  ),
                                ),
                                if (_socialPending)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _socialAttempt++;
                                      _socialPending = false;
                                      _loading = false;
                                    }),
                                    child: const Text('Cancel'),
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Back',
                                    onPressed: _loading
                                        ? null
                                        : widget.onBack ??
                                              () => Navigator.maybePop(context),
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: keyboard ? 10 : 25),
                            Text(
                              'Welcome Back',
                              style: TextStyle(
                                fontSize: keyboard ? 26 : 32,
                                letterSpacing: -1.3,
                                fontWeight: FontWeight.w800,
                                color: authNavy,
                              ),
                            ),
                            if (!keyboard) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Sign in to manage your shipments,\nbook services and track in real time.',
                                style: TextStyle(
                                  color: authMuted,
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                            ],
                            SizedBox(height: keyboard ? 15 : 25),
                            AuthInput(
                              key: const ValueKey('staff-email'),
                              controller: _email,
                              height: keyboard ? 46 : 53,
                              hint: 'Email Address',
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              enabled: !_loading,
                            ),
                            const SizedBox(height: 12),
                            AuthInput(
                              key: const ValueKey('staff-password'),
                              controller: _password,
                              height: keyboard ? 46 : 53,
                              hint: 'Password',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscure,
                              action: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              autofillHints: const [AutofillHints.password],
                              enabled: !_loading,
                              suffix: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 19,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                SizedBox(
                                  width: 26,
                                  height: 40,
                                  child: Checkbox(
                                    value: _remember,
                                    activeColor: AppColors.blue,
                                    side: const BorderSide(
                                      color: AppColors.border,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: _loading
                                        ? null
                                        : (v) => setState(
                                            () => _remember = v ?? true,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Remember me',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: authMuted,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () => showDialog<void>(
                                          context: context,
                                          builder: (_) =>
                                              PasswordRecoveryDialog(
                                                initialEmail: _email.text
                                                    .trim(),
                                              ),
                                        ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(44, 44),
                                    foregroundColor: authBlue,
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(fontSize: 10.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            GoldButton(
                              label: 'Sign In',
                              onPressed: _submit,
                              loading: _loading,
                            ),
                            if (!keyboard) ...[
                              SizedBox(height: compact ? 16 : 22),
                              const Row(
                                children: [
                                  Expanded(child: Divider()),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 13,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: authMuted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _socialButton(
                                      'Google',
                                      const GoogleMark(),
                                      () => _social('google'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _socialButton(
                                      'Apple',
                                      const Icon(
                                        Icons.apple,
                                        size: 24,
                                        color: authNavy,
                                      ),
                                      () => _social('apple'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            Center(
                              child: TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => const SignupScreen(),
                                        ),
                                      ),
                                child: const Text.rich(
                                  TextSpan(
                                    text: 'Don’t have an account?  ',
                                    style: TextStyle(
                                      color: authMuted,
                                      fontSize: 11,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Sign Up',
                                        style: TextStyle(
                                          color: authBlue,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (!keyboard)
                              Expanded(
                                child: Image.asset(
                                  'assets/images/login.jpg',
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                  excludeFromSemantics: true,
                                ),
                              )
                            else
                              const Spacer(),
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
      ),
    );
  }

  Widget _socialButton(
    String label,
    Widget icon,
    VoidCallback onTap,
  ) => SizedBox(
    height: 48,
    child: OutlinedButton(
      onPressed: _loading ? null : onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: authNavy,
        side: const BorderSide(color: Color(0xFFE0E6EF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _serverDialog() async {
    final controller = TextEditingController(text: Api.I.currentBaseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('D2F server address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://your-server.example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Dialog route finishes its reverse transition before disposing its field.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (value == null) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      if (mounted) {
        authMessage(context, 'Enter a valid http or https server address.');
      }
      return;
    }
    await Api.I.setBaseUrl(value);
    if (mounted) authMessage(context, 'Server address updated.');
  }
}

class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(21, 21), painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    for (final segment in [
      (const Color(0xFF4285F4), -.65, 1.45),
      (const Color(0xFF34A853), .8, 1.65),
      (const Color(0xFFFBBC05), 2.45, .95),
      (const Color(0xFFEA4335), 3.4, 1.65),
    ]) {
      canvas.drawArc(
        rect,
        segment.$2,
        segment.$3,
        false,
        paint..color = segment.$1,
      );
    }
    canvas.drawLine(
      Offset(size.width / 2, size.height / 2),
      Offset(size.width - 1, size.height / 2),
      paint..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PasswordRecoveryDialog extends StatefulWidget {
  final String initialEmail;
  const PasswordRecoveryDialog({super.key, this.initialEmail = ''});
  @override
  State<PasswordRecoveryDialog> createState() => _PasswordRecoveryDialogState();
}

class _PasswordRecoveryDialogState extends State<PasswordRecoveryDialog> {
  late final TextEditingController _email;
  final _code = TextEditingController(), _password = TextEditingController();
  String? _ticket, _error;
  bool _loading = false, _done = false;
  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (_ticket == null &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (_ticket != null &&
        (_code.text.length != 6 || _password.text.length < 8)) {
      setState(
        () => _error =
            'Enter the 6-digit code and a password of at least 8 characters.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_ticket == null) {
        final ticket = await Api.I.requestPasswordReset(_email.text.trim());
        if (mounted) setState(() => _ticket = ticket);
      } else {
        await Api.I.resetPassword(_ticket!, _code.text, _password.text);
        if (mounted) setState(() => _done = true);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not connect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _done ? 'Password updated' : 'Reset your password',
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _done
                ? 'You can now sign in with your new password.'
                : _ticket == null
                ? 'Enter your account email. We’ll send you a code to choose a new password.'
                : 'If an active account matches this email, a code has been sent. Check your inbox and spam folder.',
            style: const TextStyle(color: authMuted, height: 1.5),
          ),
          if (!_done) ...[
            const SizedBox(height: 18),
            if (_ticket == null)
              AuthInput(
                controller: _email,
                hint: 'Email Address',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                action: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              )
            else ...[
              AuthInput(
                controller: _code,
                hint: '6-digit code',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
              const SizedBox(height: 10),
              AuthInput(
                controller: _password,
                hint: 'New password',
                icon: Icons.lock_outline_rounded,
                obscure: true,
                action: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFBD3027), fontSize: 12),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: Text(_done ? 'Done' : 'Cancel'),
      ),
      if (!_done)
        TextButton(
          onPressed: _loading ? null : _submit,
          child: Text(
            _loading
                ? 'Please wait…'
                : _ticket == null
                ? 'Send code'
                : 'Reset password',
          ),
        ),
    ],
  );
}
