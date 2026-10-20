import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final TextEditingController _server;
  bool _savingServer = false;
  bool? _connected;
  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: Api.I.currentBaseUrl);
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final connected = await Api.I.connectionHealthy();
    if (mounted) setState(() => _connected = connected);
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s[0])
      .join()
      .toUpperCase();

  Future<void> _saveServer() async {
    final value = _server.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid HTTPS server address.')),
      );
      return;
    }
    setState(() => _savingServer = true);
    try {
      await Api.I.setBaseUrl(value);
      await _checkConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection settings saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingServer = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?', style: AppTheme.sectionTitle),
        content: const Text('You can sign in again with your D2F account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  Future<void> _support() async {
    final opened = await launchUrl(
      Uri(scheme: 'mailto', path: 'info@d2fshipping.com'),
    );
    if (!opened && mounted) {
      copyToClipboard(
        context,
        'info@d2fshipping.com',
        message: 'Support email copied.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const D2FHomeHeader(),
          const SizedBox(height: 20),
          const Text('Your profile', style: AppTheme.display),
          const SizedBox(height: 6),
          const Text(
            'Your people. Your workspace. Your D2F.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 20),
          SectionCard(
            dark: true,
            tint: AppColors.deepBlue,
            raised: true,
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3482CB), Color(0xFF17598C)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        _initials(user?.fullName ?? 'D2F'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'D2F Staff',
                            maxLines: 2,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                              color: Color(0xFFBCD0E7),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            user?.role == UserRole.ADMIN
                                ? 'ADMINISTRATOR'
                                : 'OPERATIONS TEAM',
                            style: const TextStyle(
                              color: Color(0xFFFFD185),
                              fontSize: 9,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: user == null
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => _EditProfile(user: user),
                          ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white30),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Edit profile'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SectionCard(
            dark: true,
            tint: AppColors.deepTeal,
            child: Column(
              children: [
                _line(
                  Icons.business_outlined,
                  'Organization',
                  user?.organizationName ?? 'D2F Shipping LLC',
                ),
                const Divider(color: Colors.white12, height: 24),
                _line(
                  Icons.warehouse_outlined,
                  'Assigned location',
                  user?.locationName ?? 'D2F Warehouse',
                ),
                if (user?.phone?.isNotEmpty ?? false) ...[
                  const Divider(color: Colors.white12, height: 24),
                  _line(Icons.phone_outlined, 'Contact phone', user!.phone!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: const ReferenceArt(
              'warehouse',
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.support_agent_rounded,
                    color: AppColors.blue,
                  ),
                  title: const Text('Contact D2F', style: AppTheme.body),
                  subtitle: const Text(
                    'info@d2fshipping.com',
                    style: AppTheme.caption,
                  ),
                  trailing: const Icon(Icons.arrow_outward_rounded, size: 18),
                  onTap: _support,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _connected == true
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_outlined,
                    color: _connected == true
                        ? AppColors.green
                        : AppColors.textGrey,
                  ),
                  title: const Text(
                    'Workspace connection',
                    style: AppTheme.body,
                  ),
                  subtitle: Text(
                    _connected == null
                        ? 'Checking connection…'
                        : _connected!
                        ? 'Connected to D2F'
                        : 'Tap to check connection',
                    style: AppTheme.caption,
                  ),
                  trailing: IconButton(
                    tooltip: 'Check connection',
                    onPressed: _checkConnection,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('Advanced connection', style: AppTheme.caption),
            children: [
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'https://your-server',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _savingServer ? null : _saveServer,
                      child: const Text('Save connection'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        await Api.I.setBaseUrl('');
                        if (mounted) {
                          setState(() => _server.text = Api.I.currentBaseUrl);
                        }
                        await _checkConnection();
                      },
                      child: const Text('Use default'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          OutlineButton2(label: 'Sign out', onPressed: _signOut),
          const SizedBox(height: 20),
          const Text(
            'D2F Global · Shipping with care.',
            textAlign: TextAlign.center,
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String title, String value) => Row(
    children: [
      Icon(icon, color: const Color(0xFFFFD185), size: 23),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Color(0xFFAFCBD9), fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EditProfile extends ConsumerStatefulWidget {
  final User user;
  const _EditProfile({required this.user});
  @override
  ConsumerState<_EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends ConsumerState<_EditProfile> {
  late final TextEditingController _name = TextEditingController(
    text: widget.user.fullName,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.user.phone ?? '',
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(_name.text.trim(), _phone.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your profile. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit profile', style: AppTheme.sectionTitle),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.coral, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
