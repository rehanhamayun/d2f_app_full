import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Staff self-registration (design v4): the reference "Create your account"
/// sheet — artwork header, curved white sheet, country-code phone field,
/// terms checkbox. Creates the account and signs the user in immediately.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static const _countries = <String, String>{
    'Togo': '+228',
    'Ghana': '+233',
    'Benin': '+229',
    'Nigeria': '+234',
    "Côte d'Ivoire": '+225',
    'United States': '+1',
    'Canada': '+1',
  };

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _dial = '+228';
  bool _obscure = true;
  bool _agree = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (!email.contains('@') || !email.split('@').last.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (!_agree) {
      setState(
        () => _error = 'Please agree to the Terms of Service to continue.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authControllerProvider.notifier)
          .signUp(
            name,
            email,
            password,
            phone: phoneDigits.isEmpty ? null : '$_dial $phoneDigits',
          );
      debugPrint('signup: success ${user.email} role=${user.role}');
      // Success: _RootSwitch rebuilds into StaffShell underneath; drop this
      // pushed route so the workspace is visible immediately.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        debugPrint('signup: popped to workspace');
      }
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
          _error = 'Could not create the account. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // light icons over the warm artwork
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/signup_hero.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(-.35, 0),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x260B1B46)),
            ),
            GestureDetector(
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
                    // Keep the warm artwork prominent while leaving the longer
                    // registration form room to scroll below it.
                    final heroH = keyboard
                        ? 0.0
                        : (maxH * .37).clamp(230.0, 360.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (heroH > 0) _Hero(height: heroH),
                        Expanded(
                          child: Container(
                            // Same sweeping white sheet curve as the sign-in screen.
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .96),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(34),
                                topRight: Radius.circular(34),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: _form(),
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

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Input(
          fieldKey: const ValueKey('signup-name'),
          label: 'Full name',
          icon: Icons.person_outline_rounded,
          controller: _name,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          hint: 'John Doe',
        ),
        const SizedBox(height: 10),
        _Input(
          fieldKey: const ValueKey('signup-email'),
          label: 'Email address',
          icon: Icons.mail_outline_rounded,
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          hint: 'you@example.com',
        ),
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Phone number',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -.1,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBFCFE),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFDCE4F0)),
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: 'Country code',
                    onSelected: (v) => setState(() => _dial = v),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    color: Colors.white,
                    itemBuilder: (context) => [
                      for (final entry in _countries.entries)
                        PopupMenuItem(
                          value: entry.value,
                          child: Text(
                            '${entry.value}   ${entry.key}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                    ],
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 10),
                        Text(
                          _dial,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 2),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Input(
                    fieldKey: const ValueKey('signup-phone'),
                    label: null,
                    icon: null,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    hint: '90 12 34 56',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Input(
          fieldKey: const ValueKey('signup-password'),
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          controller: _password,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          hint: 'Create a password',
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
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 26,
              child: Checkbox(
                value: _agree,
                activeColor: AppColors.coral,
                checkColor: Colors.white,
                side: const BorderSide(color: AppColors.border, width: 1.3),
                onChanged: (v) => setState(() => _agree = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'I agree to the ',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  GestureDetector(
                    onTap: _termsDialog,
                    behavior: HitTestBehavior.opaque,
                    child: const Text(
                      'Terms of Service',
                      style: TextStyle(
                        color: AppColors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text(
                    ' and ',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  GestureDetector(
                    onTap: _privacyDialog,
                    behavior: HitTestBehavior.opaque,
                    child: const Text(
                      'Privacy Policy',
                      style: TextStyle(
                        color: AppColors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
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
          label: 'Create account',
          loading: _loading,
          onPressed: _loading ? null : _submit,
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textGrey,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            child: const Text.rich(
              TextSpan(
                text: 'Already have an account? ',
                children: [
                  TextSpan(
                    text: 'Sign in',
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

  void _termsDialog() => _infoDialog(
    'Terms of Service',
    'D2F staff accounts are managed by your supervisor. By creating an account you agree to handle every shipment truthfully: record scans, status changes and notes in the workspace as they happen, and keep sign-in credentials private. Contact info@d2fshipping.com with any questions.',
  );

  void _privacyDialog() => _infoDialog(
    'Privacy Policy',
    'D2F stores only the details needed to move parcels: your name, work email, optional contact phone and the workspace activity you record. Data is stored on D2F servers (EU/Africa regions) and isn\'t sold or shared outside D2F Shipping. Request changes via Account → Edit profile.',
  );

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

/// Hero header for signup: warm artwork with headline over the sunset side.
class _Hero extends StatelessWidget {
  final double height;
  const _Hero({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0x990B1B46),
                    Color(0x14101830),
                    Colors.transparent,
                  ],
                  stops: [0, .42, .78],
                ),
              ),
            ),
          ),
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
              padding: const EdgeInsets.fromLTRB(22, 6, 16, 0),
              child: Row(
                children: [
                  const BrandLogo(fontSize: 24, light: true),
                  const Spacer(),
                  // Returning to sign-in is the escape hatch from a fresh flow.
                  IconButton(
                    tooltip: 'Back to sign in',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white70,
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 20,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Create your account',
                  style: AppTheme.heading.copyWith(
                    color: Colors.white,
                    fontSize: 27,
                    letterSpacing: -.9,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Join D2F Shipping and start your global journey today.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Labelled input shared by the signup sheet.
class _Input extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final TextEditingController controller;
  final Key? fieldKey;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final Widget? suffix;

  const _Input({
    this.fieldKey,
    required this.controller,
    this.label,
    this.icon,
    this.textInputAction,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.onSubmitted,
    required this.hint,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      key: fieldKey,
      controller: controller,
      autocorrect: false,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      enableSuggestions: !obscureText,
      obscuringCharacter: '●',
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
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
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: -.1,
          ),
        ),
        const SizedBox(height: 7),
        field,
      ],
    );
  }
}
