import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth_widgets.dart';
import 'seller_application_screen.dart';
import 'seller_orders_tab.dart';
import 'seller_products_tab.dart';

/// Seller Studio: apply to sell, track the application, then manage
/// listings, orders and the agreed commission.
class SellerStudioScreen extends ConsumerStatefulWidget {
  const SellerStudioScreen({super.key});

  @override
  ConsumerState<SellerStudioScreen> createState() => _SellerStudioScreenState();
}

class _SellerStudioScreenState extends ConsumerState<SellerStudioScreen>
    with SingleTickerProviderStateMixin {
  SellerMe? _me;
  bool _loading = true, _failed = false;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loadStarted = false;

  void _maybeLoad() {
    if (_loadStarted) return;
    final role = ref.read(authControllerProvider).valueOrNull?.role;
    if (role == null) return;
    _loadStarted = true;
    if (role == UserRole.CUSTOMER) _load();
  }

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final me = await Api.I.sellerMe();
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _openApplication([SellerProfileInfo? existing]) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => SellerApplicationScreen(existing: existing),
      ),
    );
    if (submitted == true) _load();
  }

  Future<void> _uploadBranding(String slot, Uint8List bytes, String fileName, String contentType) async {
    try {
      await Api.I.uploadSellerBrandingImage(slot, bytes, fileName: fileName, contentType: contentType);
      await _load();
    } catch (_) {
      authMessage(context, 'The shop photo could not be saved. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    _maybeLoad();
    final role = ref.watch(authControllerProvider).valueOrNull?.role;
    if (role != UserRole.CUSTOMER) {
      if (role == null) {
        return const Scaffold(
          backgroundColor: AppColors.cream,
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)),
        );
      }
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(title: const Text('Seller Studio')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined, size: 46, color: AppColors.textGrey),
                SizedBox(height: 12),
                Text(
                  'Selling is for customer accounts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
                SizedBox(height: 6),
                Text(
                  'Sign in with a customer account to apply and manage your shop.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final profile = _me?.profile;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text('Seller Studio'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(profile),
    );
  }

  Widget _body(SellerProfileInfo? profile) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.coral));
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 38, color: AppColors.textGrey),
            const SizedBox(height: 10),
            const Text('Seller Studio could not be loaded.'),
            const SizedBox(height: 14),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (profile == null) return _Pitch(onApply: () => _openApplication());
    return switch (profile.status) {
      'APPROVED' => _ApprovedStudio(profile: profile, productCount: _me?.productCount ?? 0, openOrders: _me?.openOrders ?? 0, tabs: _tabs, onChanged: _load, onUploadBranding: _uploadBranding),
      'PENDING' => _ApplicationStatus(
          icon: Icons.hourglass_top_rounded,
          tint: AppColors.goldSoft,
          color: const Color(0xFF9A7100),
          title: 'Application under review',
          body: 'D2F reviews every seller within 2 business days. We’ll contact you on ${profile.phone} to agree your commission and verify your details before your shop goes live.',
          actionLabel: 'Update application',
          onAction: () => _openApplication(profile),
        ),
      'REJECTED' => _ApplicationStatus(
          icon: Icons.info_outline_rounded,
          tint: AppColors.coralSoft,
          color: AppColors.coral,
          title: 'We couldn’t approve this yet',
          body: profile.reviewNote?.isNotEmpty == true
              ? 'Reason from D2F: ${profile.reviewNote}\n\nUpdate your application and resubmit — nothing is lost.'
              : 'Update your application and resubmit — nothing is lost.',
          actionLabel: 'Update and resubmit',
          onAction: () => _openApplication(profile),
        ),
      _ => _ApplicationStatus(
          icon: Icons.pause_circle_outline_rounded,
          tint: AppColors.chipGrey,
          color: AppColors.textGrey,
          title: 'Selling is paused',
          body: profile.reviewNote?.isNotEmpty == true
              ? 'D2F paused your seller account: ${profile.reviewNote}\n\nContact support to restore selling.'
              : 'D2F paused your seller account. Contact support to restore selling.',
          actionLabel: 'Contact support',
          onAction: null,
        ),
    };
  }
}

class _Pitch extends StatelessWidget {
  final VoidCallback onApply;
  const _Pitch({required this.onApply});

  @override
  Widget build(BuildContext context) {
    const benefits = [
      (Icons.public_rounded, 'Reach buyers everywhere', 'List once — customers in the USA, Togo, Benin, Ghana and beyond can discover you.'),
      (Icons.warehouse_rounded, 'We store & ship', 'Send stock to the Omaha warehouse. We pick, pack and ship every order for you.'),
      (Icons.request_quote_rounded, 'You set the price', 'D2F agrees your commission before your first sale — typically 8–15%.'),
      (Icons.verified_user_rounded, 'Verified & trusted', 'Every seller is reviewed by D2F. Buyers shop with confidence.'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 2.05,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/services_marketplace.jpg',
                  fit: BoxFit.cover,
                  alignment: const Alignment(.5, .22),
                  excludeFromSemantics: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF081E33).withValues(alpha: .94),
                        const Color(0xFF12365C).withValues(alpha: .55),
                        Colors.transparent,
                      ],
                      stops: const [0, .55, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'SELL ON D2F',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your storefront,\nworldwide.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        for (final benefit in benefits) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.blueSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(benefit.$1, color: AppColors.blue, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      benefit.$2,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      benefit.$3,
                      style: const TextStyle(fontSize: 11, height: 1.55, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.goldSoft,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.gold.withValues(alpha: .65)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.handshake_outlined, color: Color(0xFF9A7100), size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No surprises — your commission',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF6B4E00)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Before your first sale, D2F agrees a commission rate with you (typically 8–15%). You see it in your studio and on every order. Nothing is billed upfront.',
                      style: TextStyle(fontSize: 10.5, height: 1.6, color: Color(0xFF6B4E00)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: onApply,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
            ),
            child: const Text(
              'Apply to become a seller',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Already moving stock? Ask the D2F team to register you as a seller from the admin side.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, height: 1.5, color: AppColors.textGrey),
        ),
      ],
    );
  }
}

class _ApplicationStatus extends StatelessWidget {
  final IconData icon;
  final Color tint, color;
  final String title, body, actionLabel;
  final VoidCallback? onAction;
  const _ApplicationStatus({
    required this.icon,
    required this.tint,
    required this.color,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.65, color: AppColors.textGrey),
              ),
              const SizedBox(height: 20),
              if (onAction != null)
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    minimumSize: const Size(220, 50),
                  ),
                  child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
            ],
          ),
        ),
      );
}

class _ApprovedStudio extends StatefulWidget {
  final SellerProfileInfo profile;
  final int productCount, openOrders;
  final TabController tabs;
  final Future<void> Function() onChanged;
  final Future<void> Function(String slot, Uint8List bytes, String fileName, String contentType)? onUploadBranding;
  const _ApprovedStudio({
    required this.profile,
    required this.productCount,
    required this.openOrders,
    required this.tabs,
    required this.onChanged,
    this.onUploadBranding,
  });

  @override
  State<_ApprovedStudio> createState() => _ApprovedStudioState();
}

class _ApprovedStudioState extends State<_ApprovedStudio> {
  Uint8List? _bannerBytes;
  Uint8List? _avatarBytes;
  String _busySlot = '';

  @override
  void initState() {
    super.initState();
    _loadBranding();
  }

  Future<void> _loadBranding() async {
    try {
      final banner = await Api.I.sellerBrandingImageBytes('banner');
      final avatar = await Api.I.sellerBrandingImageBytes('profile');
      if (!mounted) return;
      setState(() {
        _bannerBytes = banner;
        _avatarBytes = avatar;
      });
    } catch (_) {
      // No branding photo yet — the monogram avatar carries the shop until a
      // photo or banner is uploaded.
    }
  }

  Future<void> _pickBranding(String slot) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 72);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final lower = picked.name.toLowerCase();
    final contentType = lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    final extension = lower.contains('png') ? 'png' : lower.contains('webp') ? 'webp' : 'jpg';
    final fileName = '$slot-${DateTime.now().millisecondsSinceEpoch}.$extension';
    setState(() => _busySlot = slot);
    try {
      await widget.onUploadBranding?.call(slot, bytes, fileName, contentType);
      await _loadBranding();
    } finally {
      if (mounted) setState(() => _busySlot = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final initials = profile.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
        .join();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Container(
            width: double.infinity,
            height: 132,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF12365C), Color(0xFF071541)],
              ),
              image: _bannerBytes == null
                  ? null
                  : DecorationImage(image: MemoryImage(_bannerBytes!), fit: BoxFit.cover),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, -30, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.gold,
                child: _avatarBytes == null
                    ? Text(
                        initials.isEmpty ? 'S' : initials,
                        style: const TextStyle(color: Color(0xFF3A2503), fontWeight: FontWeight.w900, fontSize: 16),
                      )
                    : ClipOval(
                        child: Image.memory(_avatarBytes!, width: 68, height: 68),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((profile.businessName ?? '').isNotEmpty) profile.businessName,
                        profile.category,
                        [profile.city, profile.country].where((e) => e != null && e.isNotEmpty).join(', '),
                      ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textGrey, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF159553).withValues(alpha: .28),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: .5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, size: 11, color: Color(0xFF7CFFA8)),
                          SizedBox(width: 4),
                          Text(
                            'APPROVED SELLER',
                            style: TextStyle(
                              color: Color(0xFF7CFFA8),
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              _Stat(label: 'Listings', value: '${widget.productCount}'),
              const SizedBox(width: 8),
              _Stat(label: 'Open orders', value: '${widget.openOrders}'),
              const SizedBox(width: 8),
              _CommissionStat(rate: profile.commissionLabel),
            ],
          ),
        ),
        if (widget.onUploadBranding != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busySlot.isEmpty ? () => _pickBranding('profilePicture') : null,
                    icon: _busySlot == 'profilePicture'
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coral))
                        : const Icon(Icons.photo_camera_outlined, size: 16, color: AppColors.coral),
                    label: const Text('Add profile photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busySlot.isEmpty ? () => _pickBranding('banner') : null,
                    icon: _busySlot == 'banner'
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coral))
                        : const Icon(Icons.image_outlined, size: 16, color: AppColors.coral),
                    label: const Text('Add cover banner', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        TabBar(
          controller: widget.tabs,
          labelColor: AppColors.navy,
          unselectedLabelColor: AppColors.textGrey,
          indicatorColor: AppColors.coral,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: 'Listings'),
            Tab(text: 'Orders'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: widget.tabs,
            children: [
              SellerProductsTab(onChanged: widget.onChanged),
              SellerOrdersTab(onChanged: widget.onChanged),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy, letterSpacing: -.5),
              ),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textGrey),
              ),
            ],
          ),
        ),
      );
}

class _CommissionStat extends StatelessWidget {
  final String rate;
  const _CommissionStat({required this.rate});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: AppColors.goldSoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Your commission'),
                content: Text(
                  'D2F agreed $rate of every marketplace order you fulfil. It is deducted from each order’s total — nothing is billed upfront — and it covers D2F’s delivery network, payment handling and platform services.\n\nAgreed before your first sale. Settled on D2F’s agreed schedule after orders complete.',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        rate,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF6B4E00), letterSpacing: -.5),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF9A7100)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'COMMISSION',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFF9A7100)),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
