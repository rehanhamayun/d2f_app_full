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
  final _email = TextEditingController(text: 'staff@d2fshipping.com');
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
          _error = 'This build is for Staff accounts. Customer and Driver portals arrive in later milestones.';
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              shrinkWrap: true,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BrandLogo(fontSize: 32),
                ),
                const SizedBox(height: 30),
                const ScreenIntro(
                  title: 'Welcome back.',
                  subtitle: 'Your next shipment starts here.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to manage your shipments and track parcels.',
                  style: AppTheme.body.copyWith(
                    color: AppColors.textGrey,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                const Text('Email address', style: AppTheme.caption),
                const SizedBox(height: 8),
                // Email
                TextField(
                  controller: _email,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Email address',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
                const SizedBox(height: 14),

                const Text('Password', style: AppTheme.caption),
                const SizedBox(height: 8),
                // Password
                TextField(
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
                const SizedBox(height: 12),

                Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: _remember,
                        activeColor: AppColors.navy,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        onChanged: (v) => setState(() => _remember = v ?? true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Remember me', style: AppTheme.body),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _forgotPasswordDialog(),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.coralSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.coral,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.coral,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                PrimaryButton(
                  label: 'Sign In',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),

                // Backend address (editable pre-login so a physical phone can
                // point at the demo server: LAN IP or adb reverse 127.0.0.1).
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _editServerDialog,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.dns_rounded,
                            size: 16,
                            color: AppColors.textGrey,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Server: ${Uri.tryParse(Api.I.currentBaseUrl)?.host ?? Api.I.currentBaseUrl}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.caption.copyWith(
                                color: AppColors.textGrey,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.edit_rounded,
                            size: 13,
                            color: AppColors.blue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 16),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text(
                    'Other sign-in options',
                    style: AppTheme.caption,
                  ),
                  subtitle: const Text(
                    'Planned for a future release',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 10),
                  ),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SocialButton(
                            icon: const Icon(
                              Icons.g_mobiledata_rounded,
                              size: 30,
                              color: AppColors.navy,
                            ),
                            label: 'Google',
                            onTap: () =>
                                showComingSoon(context, 'Google sign-in'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SocialButton(
                            icon: const Icon(
                              Icons.apple_rounded,
                              size: 24,
                              color: AppColors.navy,
                            ),
                            label: 'Apple',
                            onTap: () =>
                                showComingSoon(context, 'Apple sign-in'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                Center(
                  child: GestureDetector(
                    onTap: () => _contactAdminDialog(),
                    child: Text.rich(
                      TextSpan(
                        text: "Don't have an account? ",
                        style: AppTheme.body.copyWith(
                          color: AppColors.textGrey,
                          fontSize: 14,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Contact Admin.',
                            style: TextStyle(
                              color: AppColors.blue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: const ReferenceArt(
                    'login',
                    height: 210,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
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
      'For Milestone 1, ask the D2F Admin to reset your staff password. Self-service recovery arrives with the customer portal (Milestone 3).',
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

class _SocialButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
