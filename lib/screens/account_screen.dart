import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Account / Profile (design screen map #21) with server URL override
/// for on-device demos and sign-out.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final TextEditingController _server;
  bool _savingServer = false;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: Api.I.currentBaseUrl);
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final second = parts.length > 1 ? parts.last[0] : '';
    return (first + second).toUpperCase();
  }

  Future<void> _saveServer() async {
    setState(() => _savingServer = true);
    try {
      await Api.I.setBaseUrl(_server.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server set to ${Api.I.currentBaseUrl}')),
      );
    } finally {
      if (mounted) setState(() => _savingServer = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign out?', style: AppTheme.sectionTitle),
        content: const Text(
          'You will need to sign in again to continue.',
          style: AppTheme.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign out',
              style: TextStyle(
                color: AppColors.coral,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).signOut();
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
          const SizedBox(height: 14),

          const ScreenIntro(
            title: 'Your account',
            subtitle: 'Your profile and workspace, in one place.',
          ),
          const SizedBox(height: 22),
          // Profile card
          SectionCard(
            tint: AppColors.blueSoft,
            raised: true,
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.navy, Color(0xFF304D7B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      _initials(user?.fullName ?? 'D2F'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.fullName ?? 'Staff',
                        style: AppTheme.sectionTitle.copyWith(fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: AppTheme.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.blueSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          user?.role.name ?? 'STAFF',
                          style: const TextStyle(
                            color: AppColors.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          SectionCard(
            tint: AppColors.tealSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _line(
                  Icons.apartment_rounded,
                  'Organization',
                  user?.organizationName ?? 'D2F Shipping LLC',
                ),
                _line(
                  Icons.warehouse_rounded,
                  'Assigned location',
                  user?.locationName ?? 'Omaha Warehouse',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Server configuration
          const Text('Server Connection', style: AppTheme.sectionTitle),
          const SizedBox(height: 4),
          Text(
            'Manage the connection to your D2F workspace. Use your server’s network address on a physical phone.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'http://10.0.2.2:4000',
              prefixIcon: Icon(Icons.dns_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _savingServer ? null : _saveServer,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text(
                    'Save Server',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Api.I.setBaseUrl('');
                    if (mounted) {
                      setState(() => _server.text = Api.I.currentBaseUrl);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Reset',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          OutlineButton2(label: 'Sign out', onPressed: _signOut),
          const SizedBox(height: 20),

          Center(
            child: Text(
              'D2F Global · Staff workspace · v1.0.0',
              style: AppTheme.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.navy, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.caption),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppTheme.body.copyWith(fontSize: 13),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
