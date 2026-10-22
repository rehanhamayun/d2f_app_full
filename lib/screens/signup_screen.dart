import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';
import '../core/theme.dart';
import '../widgets/country_flag.dart';

class SignupScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const SignupScreen({super.key, this.onBack});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static const _countries = [
    ('🇹🇬', 'Togo', '+228', 8),
    ('🇬🇭', 'Ghana', '+233', 9),
    ('🇧🇯', 'Benin', '+229', 10),
    ('🇳🇬', 'Nigeria', '+234', 10),
    ('🇨🇮', 'Côte d’Ivoire', '+225', 10),
    ('🇺🇸', 'United States', '+1', 10),
    ('🇨🇦', 'Canada', '+1', 10),
    ('🇫🇷', 'France', '+33', 9),
    ('🇬🇧', 'United Kingdom', '+44', 10),
    ('🇵🇰', 'Pakistan', '+92', 10),
  ];
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _phone = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController(),
      _invite = TextEditingController();
  UserRole _role = UserRole.CUSTOMER;
  int _country = 0;
  bool _obscure = true, _obscureConfirm = true, _loading = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _password,
      _confirm,
      _invite,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final name = _name.text.trim(), email = _email.text.trim();
    var digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    // National trunk prefixes are omitted in international phone numbers.
    if ([
          'Ghana',
          'Nigeria',
          'France',
          'United Kingdom',
          'Pakistan',
        ].contains(_countries[_country].$2) &&
        digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    String? error;
    if (name.isEmpty || name.length > 120) {
      error = 'Please enter your full name (up to 120 characters).';
    } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      error = 'Please enter a valid email address.';
    } else if (digits.length != _countries[_country].$4) {
      error =
          'Enter a ${_countries[_country].$4}-digit phone number for ${_countries[_country].$2}.';
    } else if (_password.text.length < 8 ||
        utf8.encode(_password.text).length > 72) {
      error = 'Use at least 8 characters and no more than 72 bytes for your password.';
    } else if (_password.text != _confirm.text) {
      error = 'Your passwords don’t match. Please check them.';
    }
    if (error != null) {
      authMessage(context, error);
      return;
    }
    FocusScope.of(context).unfocus();
    if (_role != UserRole.CUSTOMER) {
      final approved = await _invitationDialog();
      if (approved != true || !mounted) return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signUp(
            name,
            email,
            _password.text,
            phone: '${_countries[_country].$3}$digits',
            role: _role,
            invitation: _role == UserRole.CUSTOMER ? null : _invite.text.trim(),
          );
      if (mounted) {
        TextInput.finishAutofillContext();
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on ApiException catch (error) {
      if (mounted) authMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        authMessage(
          context,
          'Could not create your account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _invitationDialog() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${_role == UserRole.STAFF ? 'Staff' : 'Driver'} invitation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the invitation provided by your D2F administrator. It must match your email and selected role.',
            style: TextStyle(color: authMuted, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('signup-invitation'),
            controller: _invite,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'Paste invitation code',
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) Navigator.pop(context, true);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_invite.text.trim().isNotEmpty) Navigator.pop(context, true);
          },
          child: const Text('Continue'),
        ),
      ],
    ),
  );

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
                top: false,
                child: AuthFit(
                  minHeight: keyboard ? 355 : 660,
                  builder: (height) {
                    final heroHeight = keyboard
                        ? 0.0
                        : (height * .32).clamp(100.0, height - 552);
                    final fieldHeight = keyboard ? 44.0 : 46.0;
                    final gap = keyboard ? 7.0 : 9.0;
                    return Column(
                      children: [
                        SizedBox(
                          height: keyboard ? 0 : heroHeight + 26,
                          child: keyboard
                              ? null
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(
                                      color: authCanvas,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Image.asset(
                                          'assets/images/login.jpg',
                                          width: 160,
                                          fit: BoxFit.contain,
                                          excludeFromSemantics: true,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top:
                                          MediaQuery.paddingOf(context).top + 6,
                                      left: 24,
                                      right: 24,
                                      child: Row(
                                        children: [
                                          const ShippingLogo(width: 155),
                                          const Spacer(),
                                          IconButton(
                                            tooltip: 'Back to sign in',
                                            onPressed: _loading
                                                ? null
                                                : widget.onBack ??
                                                      () => Navigator.maybePop(
                                                        context,
                                                      ),
                                            icon: const Icon(
                                              Icons.arrow_back_rounded,
                                              color: authNavy,
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      left: 24,
                                      right: 115,
                                      bottom: 42,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Join D2F',
                                            style: TextStyle(
                                              color: authNavy,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -.8,
                                            ),
                                          ),
                                          if (heroHeight > 150) ...[
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Create your account and\nstart shipping with ease.',
                                              style: TextStyle(
                                                color: authMuted,
                                                fontSize: 14,
                                                height: 1.45,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        Expanded(
                          child: Transform.translate(
                            offset: Offset(0, keyboard ? 0 : -26),
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              maxHeight: keyboard ? null : height - heroHeight,
                              child: Container(
                                height: keyboard ? height : height - heroHeight,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [authCanvas, authCanvas],
                                  ),
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(30),
                                  ),
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  keyboard
                                      ? MediaQuery.paddingOf(context).top + 4
                                      : 18,
                                  20,
                                  keyboard ? 8 : 12,
                                ),
                                child: AutofillGroup(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        height: keyboard ? 30 : 99,
                                        child: keyboard
                                            ? Row(
                                                children: [
                                                  IconButton(
                                                    tooltip: 'Hide keyboard',
                                                    padding: EdgeInsets.zero,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    onPressed: () =>
                                                        FocusScope.of(context)
                                                            .unfocus(),
                                                    icon: const Icon(
                                                      Icons
                                                          .keyboard_arrow_down_rounded,
                                                      color: authNavy,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Join D2F · ${_role == UserRole.CUSTOMER
                                                        ? 'Customer'
                                                        : _role == UserRole.DRIVER
                                                        ? 'Driver'
                                                        : 'Staff'}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: authNavy,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Column(
                                                children: [
                                                  _roles(),
                                                  const SizedBox(height: 17),
                                                ],
                                              ),
                                      ),
                                      AuthInput(
                                        key: const ValueKey('signup-name'),
                                        controller: _name,
                                        hint: 'Full Name',
                                        icon: Icons.person_outline_rounded,
                                        height: fieldHeight,
                                        enabled: !_loading,
                                        autofillHints: const [
                                          AutofillHints.name,
                                        ],
                                      ),
                                      SizedBox(height: gap),
                                      AuthInput(
                                        key: const ValueKey('signup-email'),
                                        controller: _email,
                                        hint: 'Email Address',
                                        icon: Icons.mail_outline_rounded,
                                        height: fieldHeight,
                                        enabled: !_loading,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autofillHints: const [
                                          AutofillHints.email,
                                        ],
                                      ),
                                      SizedBox(height: gap),
                                      AuthInput(
                                        key: const ValueKey('signup-phone'),
                                        controller: _phone,
                                        hint: 'Phone Number',
                                        icon: Icons.phone_outlined,
                                        height: fieldHeight,
                                        enabled: !_loading,
                                        keyboardType: TextInputType.phone,
                                        autofillHints: const [
                                          AutofillHints.telephoneNumberNational,
                                        ],
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9 ()-]'),
                                          ),
                                          LengthLimitingTextInputFormatter(20),
                                        ],
                                        prefix: _countryPicker(),
                                      ),
                                      SizedBox(height: gap),
                                      AuthInput(
                                        key: const ValueKey('signup-password'),
                                        controller: _password,
                                        hint: 'Password',
                                        icon: Icons.lock_outline_rounded,
                                        height: fieldHeight,
                                        enabled: !_loading,
                                        obscure: _obscure,
                                        autofillHints: const [
                                          AutofillHints.newPassword,
                                        ],
                                        suffix: IconButton(
                                          tooltip: _obscure
                                              ? 'Show password'
                                              : 'Hide password',
                                          onPressed: () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                          icon: Icon(
                                            _obscure
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: gap),
                                      AuthInput(
                                        key: const ValueKey(
                                          'signup-confirm-password',
                                        ),
                                        controller: _confirm,
                                        hint: 'Confirm Password',
                                        icon: Icons.lock_outline_rounded,
                                        height: fieldHeight,
                                        enabled: !_loading,
                                        obscure: _obscureConfirm,
                                        action: TextInputAction.done,
                                        onSubmitted: (_) => _submit(),
                                        autofillHints: const [
                                          AutofillHints.newPassword,
                                        ],
                                        suffix: IconButton(
                                          tooltip: _obscureConfirm
                                              ? 'Show confirm password'
                                              : 'Hide confirm password',
                                          onPressed: () => setState(
                                            () => _obscureConfirm =
                                                !_obscureConfirm,
                                          ),
                                          icon: Icon(
                                            _obscureConfirm
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      if (_role != UserRole.CUSTOMER &&
                                          !keyboard)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 5,
                                            bottom: 5,
                                          ),
                                          child: Text(
                                            'A D2F invitation is required for this role.',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: authMuted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      GoldButton(
                                        label: 'Create Account',
                                        onPressed: _submit,
                                        loading: _loading,
                                        height: keyboard ? 46 : 52,
                                      ),
                                      if (!keyboard) ...[
                                        const Spacer(),
                                        const Text(
                                          'By creating an account, you agree to our',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: authMuted,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _policyLink(
                                              'Terms of Service',
                                              'Use your own accurate account details and keep your sign-in information private. Staff and driver access requires an administrator invitation. Shipping prices, delivery estimates and shipment terms are confirmed by D2F before a booking. For the full service agreement, contact info@d2fshipping.com.',
                                            ),
                                            const Text(
                                              ' and ',
                                              style: TextStyle(
                                                color: authMuted,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                            _policyLink(
                                              'Privacy Policy',
                                              'Your name, email, phone and account role are used to provide your D2F account. Passwords are hashed on the server and session tokens are kept in secure device storage. Google and Apple sign-in share the profile information you authorize. Contact info@d2fshipping.com to request help with your data or obtain D2F’s full privacy notice.',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
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
    );
  }

  Widget _roles() => SizedBox(
    height: 82,
    child: Row(
      children: [
        for (final entry in [
          (UserRole.CUSTOMER, 'Customer', 'Ship & Track', Icons.person_rounded),
          (
            UserRole.DRIVER,
            'Driver',
            'Deliver Jobs',
            Icons.local_shipping_rounded,
          ),
          (UserRole.STAFF, 'Staff', 'Manage Operations', Icons.groups_rounded),
        ]) ...[
          if (entry.$1 != UserRole.CUSTOMER) const SizedBox(width: 7),
          Expanded(
            child: Semantics(
              selected: _role == entry.$1,
              button: true,
              label: '${entry.$2}: ${entry.$3}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('signup-role-${entry.$1.name.toLowerCase()}'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: _loading
                      ? null
                      : () => setState(() {
                          _role = entry.$1;
                          _invite.clear();
                        }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: _role == entry.$1
                          ? AppColors.coralSoft
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _role == entry.$1
                            ? AppColors.coral
                            : AppColors.border,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          entry.$4,
                          size: 25,
                          color: _role == entry.$1 ? AppColors.coral : authNavy,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.$2,
                          style: const TextStyle(
                            fontSize: 12,
                            color: authNavy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              entry.$3,
                              style: TextStyle(
                                fontSize: 9,
                                color: _role == entry.$1
                                    ? AppColors.coral
                                    : authMuted,
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
          ),
        ],
      ],
    ),
  );

  Widget _countryPicker() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(width: 14),
      const Icon(Icons.phone_outlined, size: 19, color: Color(0xFF53617A)),
      PopupMenuButton<int>(
        tooltip: 'Country code',
        enabled: !_loading,
        onSelected: (index) => setState(() => _country = index),
        itemBuilder: (_) => [
          for (var i = 0; i < _countries.length; i++)
            PopupMenuItem(
              value: i,
              child: Row(
                children: [
                  CountryFlag(country: _countries[i].$2),
                  const SizedBox(width: 10),
                  Text(
                    '${_countries[i].$2}  ${_countries[i].$3}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountryFlag(country: _countries[_country].$2),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: authNavy,
              ),
            ],
          ),
        ),
      ),
      Container(height: 18, width: 1, color: const Color(0xFFDDE3EE)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Text(
          _countries[_country].$3,
          style: const TextStyle(fontSize: 12, color: authNavy),
        ),
      ),
    ],
  );

  Widget _policyLink(String title, String body) => TextButton(
    onPressed: () => authInfo(context, title, body),
    style: TextButton.styleFrom(
      padding: EdgeInsets.zero,
      foregroundColor: authBlue,
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(
      title,
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
    ),
  );
}
