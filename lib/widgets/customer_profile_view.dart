import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'reference_widgets.dart';

/// Customer presentation only. All account changes and navigation are delegated
/// to the existing account controller and workspace.
class CustomerProfileView extends StatelessWidget {
  final User user;
  final VoidCallback onEdit, onSupport, onSignOut, onCheckConnection;
  final VoidCallback? onTrack, onShip, onChangePassword;
  final bool? connected;
  const CustomerProfileView({
    super.key,
    required this.user,
    required this.onEdit,
    required this.onSupport,
    required this.onSignOut,
    required this.onCheckConnection,
    this.onTrack,
    this.onShip,
    this.onChangePassword,
    this.connected,
  });
  @override
  Widget build(BuildContext context) {
    final initials = user.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    return SafeArea(
      child: ListView(
        padding: AppSpacing.pageInsets,
        children: [
          Row(
            children: [
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BrandWordmark(),
                ),
              ),
              IconButton(
                tooltip: 'Contact D2F',
                onPressed: onSupport,
                icon: const Icon(Icons.support_agent_rounded, size: 25),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Your profile', style: AppTheme.display),
          const SizedBox(height: 7),
          const Text(
            'Your details. Your next journey.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 22),
          SectionCard(
            tint: AppColors.blueSoft,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.blue.withValues(alpha: .12),
                          width: 3,
                        ),
                      ),
                      child: Text(
                        initials.isEmpty ? 'D' : initials,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: -.7,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            user.email,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textGrey,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Text(
                        'CUSTOMER',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.blue,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text(
                        'Edit profile',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Personal details', style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _detail(
                  Icons.mail_outline_rounded,
                  AppColors.coralSoft,
                  'Account email',
                  user.email,
                ),
                const Divider(height: 26),
                _detail(
                  Icons.phone_outlined,
                  AppColors.goldSoft,
                  'Contact phone',
                  user.phone?.isNotEmpty == true ? user.phone! : 'Not provided',
                ),
              ],
            ),
          ),
          if (onChangePassword != null) ...[
            const SizedBox(height: 24),
            const Text('Account security', style: AppTheme.sectionTitle),
            const SizedBox(height: 12),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: onChangePassword,
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 22,
                    color: AppColors.blue,
                  ),
                ),
                title: const Text(
                  'Change password',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Sign out other devices and keep your account secure.',
                  style: TextStyle(fontSize: 10, color: AppColors.textGrey),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ),
          ],
          if (onTrack != null || onShip != null) ...[
            const SizedBox(height: 24),
            const Text('Your shipping tools', style: AppTheme.sectionTitle),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onShip != null)
                  Expanded(
                    child: _tool(
                      'Send a package',
                      'Plan your next journey',
                      Icons.inventory_2_outlined,
                      AppColors.coralSoft,
                      onShip!,
                    ),
                  ),
                if (onShip != null && onTrack != null)
                  const SizedBox(width: 12),
                if (onTrack != null)
                  Expanded(
                    child: _tool(
                      'Track a parcel',
                      'Follow every update',
                      Icons.location_on_outlined,
                      AppColors.goldSoft,
                      onTrack!,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SectionCard(
            tint: AppColors.goldSoft,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Closer to home.\nIn both directions.',
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'USA & Europe ↔ West Africa',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.5,
                          color: AppColors.textGrey,
                        ),
                      ),
                      if (onShip != null)
                        TextButton(
                          onPressed: onShip,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: AppColors.navy,
                          ),
                          child: const Text(
                            'Arrange a shipment →',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Image.asset(
                    'assets/images/tracking_globe_reference.png',
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Here when you need us', style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: onSupport,
                  leading: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.blueSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      size: 22,
                      color: AppColors.blue,
                    ),
                  ),
                  title: const Text(
                    'Contact D2F',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'info@d2fshipping.com',
                    style: TextStyle(fontSize: 10, color: AppColors.textGrey),
                  ),
                  trailing: const Icon(Icons.arrow_outward_rounded, size: 18),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    connected == true
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_outlined,
                    color: connected == true
                        ? AppColors.green
                        : AppColors.textGrey,
                    size: 23,
                  ),
                  title: const Text(
                    'Service connection',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    connected == null
                        ? 'Checking connection…'
                        : connected!
                        ? 'Connected to D2F'
                        : 'Tap to check connection',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textGrey,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Check connection',
                    onPressed: onCheckConnection,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlineButton2(label: 'Sign out', onPressed: onSignOut),
          ),
          const SizedBox(height: 22),
          const Text(
            'D2F Global · Shipping with care.',
            textAlign: TextAlign.center,
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, Color tint, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textGrey),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _tool(
    String title,
    String subtitle,
    IconData icon,
    Color tint,
    VoidCallback onTap,
  ) => Material(
    color: tint,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 27),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                height: 1.4,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
