import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Keeps accounts without staff permissions outside the staff workspace.
class StaffOnlyGate extends ConsumerWidget {
  const StaffOnlyGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Align(alignment: Alignment.centerLeft, child: BrandLogo()),
          const SizedBox(height: 60),
          SectionCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.blue,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Staff access only',
                  textAlign: TextAlign.center,
                  style: AppTheme.heading.copyWith(letterSpacing: -.6),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sign in with your D2F staff account to register parcels and manage tracking. Your current account does not have access to this workspace.',
                  style: AppTheme.caption.copyWith(height: 1.7),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                OutlineButton2(
                  label: 'Sign out',
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'D2F Global · Staff workspace',
            style: AppTheme.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
