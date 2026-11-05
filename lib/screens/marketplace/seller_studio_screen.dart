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
  List<Map<String, dynamic>> _adminSellers = const [];

  void _maybeLoad() {
    final role = ref.read(authControllerProvider).valueOrNull?.role;
    if (role == null) return;
    if (role == UserRole.CUSTOMER) _load();
    if (role == UserRole.ADMIN) _loadAdminSellers();
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
    setState(() { _loading = true; _failed = false; });
    try {
      final me = await Api.I.sellerMe();
      if (!mounted) return;
      setState(() { _me = me; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }

  Future<void> _openApplication([SellerProfileInfo? existing]) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => SellerApplicationScreen(existing: existing)),
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

  Future<void> _loadAdminSellers() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final sellers = await Api.I.adminSellers();
      if (!mounted) return;
      setState(() { _adminSellers = sellers; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }

  Future<void> _updateSellerStatus(String id, String action, {String? reviewNote, int? commissionBps}) async {
    try {
      await Api.I.adminUpdateSeller(id, action: action, reviewNote: reviewNote, commissionBps: commissionBps);
      await _loadAdminSellers();
    } catch (_) {
      authMessage(context, 'Could not update seller. Please try again.');
    }
  }

  Future<void> _openAdminRegisterSeller() async {
    final customerIdC = TextEditingController();
    final displayNameC = TextEditingController();
    final categoryC = TextEditingController();
    final phoneC = TextEditingController();
    String businessType = 'INDIVIDUAL';
    int commissionBps = 1000;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register Seller'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: customerIdC, decoration: const InputDecoration(labelText: 'Customer ID / email')),
              const SizedBox(height: 8),
              TextFormField(controller: displayNameC, decoration: const InputDecoration(labelText: 'Seller display name')),
              const SizedBox(height: 8),
              TextFormField(controller: categoryC, decoration: const InputDecoration(labelText: 'Main category')),
              const SizedBox(height: 8),
              TextFormField(controller: phoneC, decoration: const InputDecoration(labelText: 'Contact phone'), keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Individual', style: TextStyle(fontSize: 11)),
                Radio<String>(value: 'INDIVIDUAL', groupValue: businessType, onChanged: (v) => setState(() => businessType = v!)),
                const Text('Business', style: TextStyle(fontSize: 11)),
                Radio<String>(value: 'BUSINESS', groupValue: businessType, onChanged: (v) => setState(() => businessType = v!)),
              ]),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Commission %'), keyboardType: TextInputType.number, initialValue: '10', onChanged: (v) { final d = double.tryParse(v); if (d != null) commissionBps = (d * 100).round(); }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Register')),
        ],
      ),
    );

    if (submitted == true && customerIdC.text.isNotEmpty) {
      try {
        await Api.I.adminRegisterSeller(customerId: customerIdC.text.trim(), displayName: displayNameC.text.trim(), businessType: businessType, category: categoryC.text.trim(), phone: phoneC.text.trim(), commissionBps: commissionBps);
        await _loadAdminSellers();
        if (mounted) authMessage(context, 'Seller registered.');
      } catch (_) {
        if (mounted) authMessage(context, 'Registration failed. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).valueOrNull?.role;
    if (role == null) {
      return const Scaffold(backgroundColor: AppColors.cream, body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    if (role == UserRole.ADMIN) {
      return _AdminSellerManagement(
        loading: _loading, failed: _failed, sellers: _adminSellers,
        onLoad: _loadAdminSellers, onUpdate: _updateSellerStatus, onRegister: _openAdminRegisterSeller,
      );
    }
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.cream, body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    if (_failed) {
      return Scaffold(backgroundColor: AppColors.cream, appBar: AppBar(title: const Text('Seller Studio')), body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 38, color: AppColors.textGrey),
          const SizedBox(height: 10),
          const Text('Seller Studio could not be loaded.'),
          const SizedBox(height: 14),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      ));
    }
    final profile = _me?.profile;
    if (profile == null) return _Pitch(onApply: _openApplication);
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text('Seller Studio'), actions: [
        IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        const SizedBox(width: 4),
      ]),
      body: _buildCustomerBody(profile),
    );
  }

  Widget _buildCustomerBody(SellerProfileInfo profile) {
    switch (profile.status) {
      case 'APPROVED':
        return _ApprovedStudio(
          profile: profile,
          productCount: _me?.productCount ?? 0,
          openOrders: _me?.openOrders ?? 0,
          tabs: _tabs,
          onChanged: _load,
          onUploadBranding: _uploadBranding,
        );
      case 'PENDING':
        return _ApplicationStatus(
          icon: Icons.hourglass_top_rounded, tint: AppColors.goldSoft, color: const Color(0xFF9A7100),
          title: 'Application under review',
          body: 'D2F reviews every seller within 2 business days.',
          actionLabel: 'Update application', onAction: () => _openApplication(profile),
        );
      case 'REJECTED':
        return _ApplicationStatus(
          icon: Icons.info_outline_rounded, tint: AppColors.coralSoft, color: AppColors.coral,
          title: "We couldn't approve this yet",
          body: profile.reviewNote?.isNotEmpty == true ? 'Reason from D2F: ${profile.reviewNote}\n\nUpdate your application and resubmit.' : 'Update your application and resubmit.',
          actionLabel: 'Update and resubmit', onAction: () => _openApplication(profile),
        );
      default:
        return _ApplicationStatus(
          icon: Icons.pause_circle_outline_rounded, tint: AppColors.chipGrey, color: AppColors.textGrey,
          title: 'Selling is paused',
          body: 'D2F paused your seller account. Contact support to restore selling.',
          actionLabel: 'Contact support', onAction: null,
        );
    }
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
        ClipRRect(borderRadius: BorderRadius.circular(20), child: Container(
          color: AppColors.coralSoft, padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.storefront_rounded, size: 40, color: AppColors.coral),
            const SizedBox(height: 14),
            const Text('Become a D2F Seller', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy)),
            const SizedBox(height: 10),
            const Text('Apply to sell on the D2F Marketplace. D2F reviews every application and agrees your commission before your first sale.', style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey)),
          ]),
        )),
        const SizedBox(height: 16),
        ...benefits.map((b) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(b.$1, size: 20, color: AppColors.coral),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
              const SizedBox(height: 2),
              Text(b.$3, style: const TextStyle(fontSize: 10.5, height: 1.5, color: AppColors.textGrey)),
            ])),
          ],
        ))),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, height: 52, child: FilledButton(
          onPressed: onApply,
          style: FilledButton.styleFrom(backgroundColor: AppColors.coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('Apply to sell', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
        )),
      ],
    );
  }
}

class _ApplicationStatus extends StatelessWidget {
  final IconData icon; final Color tint, color; final String title, body, actionLabel; final VoidCallback? onAction;
  const _ApplicationStatus({required this.icon, required this.tint, required this.color, required this.title, required this.body, required this.actionLabel, required this.onAction});

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Container(width: 88, height: 88, decoration: BoxDecoration(color: tint, shape: BoxShape.circle), child: Icon(icon, size: 40, color: color)),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4, color: AppColors.navy)),
        const SizedBox(height: 10),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 1.65, color: AppColors.textGrey)),
        const SizedBox(height: 20),
        if (onAction != null) FilledButton(
          onPressed: onAction,
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), minimumSize: const Size(220, 50)),
          child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ],
    )),
  );
}

class _ApprovedStudio extends StatefulWidget {
  final SellerProfileInfo profile; final int productCount, openOrders; final TabController tabs;
  final Future<void> Function() onChanged; final Future<void> Function(String, Uint8List, String, String)? onUploadBranding;
  const _ApprovedStudio({required this.profile, required this.productCount, required this.openOrders, required this.tabs, required this.onChanged, this.onUploadBranding});

  @override
  State<_ApprovedStudio> createState() => _ApprovedStudioState();
}

class _ApprovedStudioState extends State<_ApprovedStudio> {
  Uint8List? _bannerBytes; Uint8List? _avatarBytes; String _busySlot = '';

  @override
  void initState() { super.initState(); _loadBranding(); }

  Future<void> _loadBranding() async {
    try {
      final results = await Future.wait([
        Api.I.sellerBrandingImageBytes('banner'),
        Api.I.sellerBrandingImageBytes('profile'),
      ]);
      if (!mounted) return;
      setState(() { _bannerBytes = results[0]; _avatarBytes = results[1]; });
    } catch (_) {}
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
    } finally { if (mounted) setState(() => _busySlot = ''); }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final initials = profile.displayName.trim().split(RegExp(r'\s+')).take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 12), child: Container(
        width: double.infinity, height: 132,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF12365C), Color(0xFF071541)]), image: _bannerBytes == null ? null : DecorationImage(image: MemoryImage(_bannerBytes!), fit: BoxFit.cover)),
      )),
      Padding(padding: const EdgeInsets.fromLTRB(16, -30, 16, 12), child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, children: [
          CircleAvatar(radius: 34, backgroundColor: AppColors.gold, child: _avatarBytes == null ? Text(initials.isEmpty ? 'S' : initials, style: const TextStyle(color: Color(0xFF3A2503), fontWeight: FontWeight.w900, fontSize: 16)) : ClipOval(child: Image.memory(_avatarBytes!, width: 68, height: 68))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.3)),
            const SizedBox(height: 2),
            Text([if ((profile.businessName ?? '').isNotEmpty) profile.businessName, profile.category, [profile.city, profile.country].where((e) => e != null && e.isNotEmpty).join(', ')].whereType<String>().where((e) => e.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textGrey, fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF159553).withValues(alpha: .28), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: .5))), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.verified_rounded, size: 11, color: Color(0xFF7CFFA8)), SizedBox(width: 4), Text('APPROVED SELLER', style: TextStyle(color: Color(0xFF7CFFA8), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.1))])),
          ])),
        ],
      )),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: Row(children: [
        _Stat(label: 'Listings', value: '${widget.productCount}'), const SizedBox(width: 8),
        _Stat(label: 'Open orders', value: '${widget.openOrders}'), const SizedBox(width: 8),
        _CommissionStat(rate: profile.commissionLabel),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: widget.onUploadBranding != null && _busySlot.isEmpty ? () => _pickBranding('profilePicture') : null,
          icon: _busySlot == 'profilePicture' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coral)) : const Icon(Icons.photo_camera_outlined, size: 16, color: AppColors.coral),
          label: const Text('Add profile photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: widget.onUploadBranding != null && _busySlot.isEmpty ? () => _pickBranding('banner') : null,
          icon: _busySlot == 'banner' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coral)) : const Icon(Icons.image_outlined, size: 16, color: AppColors.coral),
          label: const Text('Add cover banner', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        )),
      ])),
      TabBar(controller: widget.tabs, labelColor: AppColors.navy, unselectedLabelColor: AppColors.textGrey, indicatorColor: AppColors.coral, indicatorWeight: 3, labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800), tabs: const [Tab(text: 'Listings'), Tab(text: 'Orders')]),
      Expanded(child: TabBarView(controller: widget.tabs, children: [SellerProductsTab(onChanged: widget.onChanged), SellerOrdersTab(onChanged: widget.onChanged)])),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(children: [
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy, letterSpacing: -.5)),
      const SizedBox(height: 2),
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textGrey)),
    ]),
  ));
}

class _CommissionStat extends StatelessWidget {
  final String rate;
  const _CommissionStat({required this.rate});

  @override
  Widget build(BuildContext context) {
    return Expanded(
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
                'D2F agreed $rate of every marketplace order you fulfil. It is deducted from each order\u2019s total — nothing is billed upfront — and it covers D2F\u2019s delivery network, payment handling and platform services.\n\nAgreed before your first sale. Settled on D2F\u2019s agreed schedule after orders complete.',
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
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF6B4E00),
                        letterSpacing: -.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Commission',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _sellerStatusColor(String status) => switch (status) {
  'PENDING' => AppColors.gold, 'APPROVED' => AppColors.green, 'REJECTED' => AppColors.coral, 'SUSPENDED' => AppColors.textGrey, _ => AppColors.navy,
};

class _SellerRow extends StatelessWidget {
  final Map<String, dynamic> seller;
  final Future<void> Function(String, String, {String? reviewNote, int? commissionBps}) onUpdate;
  const _SellerRow({required this.seller, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final user = seller['user'] as Map? ?? {};
    final status = (seller['status'] as String?) ?? 'PENDING';
    final commission = (seller['commissionBps'] as num?) ?? 1000;
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(14), child: InkWell(
      borderRadius: BorderRadius.circular(14), child: Padding(
      padding: const EdgeInsets.all(12), child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: AppColors.gold, child: Text(((user['fullName'] as String?) ?? 'Seller').trim().split(RegExp(r'\s+')).take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF3A2503)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((user['fullName'] as String?) ?? 'Seller', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 2),
          Text([(seller['businessName'] as String?), (seller['category'] as String?), (seller['country'] as String?)].whereType<String>().where((e) => e.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 10, color: AppColors.textGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _sellerStatusColor(status).withValues(alpha: .14), borderRadius: BorderRadius.circular(8), border: Border.all(color: _sellerStatusColor(status).withValues(alpha: .5))), child: Text(status, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _sellerStatusColor(status), letterSpacing: .4))),
            const SizedBox(width: 8),
            Text('${(commission / 100).toStringAsFixed(commission % 100 == 0 ? 0 : 1)}% commission', style: const TextStyle(fontSize: 9, color: AppColors.textGrey)),
          ]),
        ])),
        const SizedBox(width: 8),
        _ActionButtons(sellerId: seller['id'] as String, status: status, onUpdate: onUpdate),
      ])),
    ));
  }
}

class _ActionButtons extends StatefulWidget {
  final String sellerId, status;
  final Future<void> Function(String, String, {String? reviewNote, int? commissionBps}) onUpdate;
  const _ActionButtons({required this.sellerId, required this.status, required this.onUpdate});

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _busy = false;

  Future<void> _act(String action) async {
    setState(() => _busy = true);
    try {
      String? note; int? bps;
      if (action == 'reject' || action == 'suspend') {
        note = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
          title: Text('${action[0].toUpperCase()}${action.substring(1)} Seller'),
          content: const TextField(decoration: InputDecoration(labelText: 'Reason / note'), maxLines: 2),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, 'note'), child: const Text('OK'))],
        ));
        if (note == null) { setState(() => _busy = false); return; }
      }
      if (action == 'approve' || action == 'reinstate') {
        bps = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Agree Commission'),
          content: const TextField(decoration: InputDecoration(labelText: 'Commission % (e.g. 10)'), keyboardType: TextInputType.number),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, 1000), child: const Text('OK'))],
        ));
        if (bps == null) { setState(() => _busy = false); return; }
        bps = bps * 100;
      }
      await widget.onUpdate(widget.sellerId, action, reviewNote: note, commissionBps: bps);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _adminActionButton(String label, IconData icon, Color color, VoidCallback onPressed) => Tooltip(
    message: label, child: Material(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(8), child: InkWell(
      borderRadius: BorderRadius.circular(8), onTap: onPressed, child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 16, color: color)),
    )),
  );

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    if (widget.status == 'PENDING') ...[
      _adminActionButton('Approve', Icons.check_rounded, AppColors.green, () => _act('approve')), const SizedBox(height: 4),
      _adminActionButton('Reject', Icons.close_rounded, AppColors.coral, () => _act('reject')),
    ],
    if (widget.status == 'APPROVED') ...[
      _adminActionButton('Suspend', Icons.block_rounded, AppColors.coral, () => _act('suspend')),
    ],
    if (widget.status == 'SUSPENDED') ...[
      _adminActionButton('Reinstate', Icons.restore_rounded, AppColors.green, () => _act('reinstate')),
    ],
    if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coral)),
  ]);
}

class _AdminSellerManagement extends StatelessWidget {
  final bool loading, failed; final List<Map<String, dynamic>> sellers;
  final Future<void> Function() onLoad;
  final Future<void> Function(String, String, {String? reviewNote, int? commissionBps}) onUpdate;
  final Future<void> Function() onRegister;
  const _AdminSellerManagement({required this.loading, required this.failed, required this.sellers, required this.onLoad, required this.onUpdate, required this.onRegister});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.cream,
    appBar: AppBar(title: const Text('Seller Management'), actions: [
      IconButton(tooltip: 'Refresh', onPressed: loading ? null : onLoad, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: _AdminSellerBody(loading: loading, failed: failed, sellers: sellers, onLoad: onLoad, onUpdate: onUpdate, onRegister: onRegister),
  );
}

class _AdminSellerBody extends StatefulWidget {
  final bool loading, failed; final List<Map<String, dynamic>> sellers;
  final Future<void> Function() onLoad;
  final Future<void> Function(String, String, {String? reviewNote, int? commissionBps}) onUpdate;
  final Future<void> Function() onRegister;
  const _AdminSellerBody({required this.loading, required this.failed, required this.sellers, required this.onLoad, required this.onUpdate, required this.onRegister});

  @override
  State<_AdminSellerBody> createState() => _AdminSellerBodyState();
}

class _AdminSellerBodyState extends State<_AdminSellerBody> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator(color: AppColors.coral));
    if (widget.failed) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_rounded, size: 38, color: AppColors.textGrey),
      const SizedBox(height: 10), const Text('Seller list could not be loaded.'),
      const SizedBox(height: 14), FilledButton(onPressed: widget.onLoad, child: const Text('Try again')),
    ]));
    final filtered = widget.sellers.where((s) { if (_filter == 'ALL') return true; return (s['status'] as String?) == _filter; }).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Row(children: [
        Expanded(child: Text('Seller Accounts (${widget.sellers.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy))),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: widget.onRegister, icon: const Icon(Icons.person_add_rounded, size: 16), label: const Text('Register', style: TextStyle(fontSize: 11)), style: FilledButton.styleFrom(backgroundColor: AppColors.coral, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), minimumSize: Size.zero)),
      ])),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(
        spacing: 6, runSpacing: 6,
        children: [
          ChoiceChip(label: const Text('All', style: TextStyle(fontSize: 9)), selected: _filter == 'ALL', onSelected: (v) => setState(() => _filter = v ? 'ALL' : 'ALL')),
          ChoiceChip(label: const Text('Pending', style: TextStyle(fontSize: 9)), selected: _filter == 'PENDING', onSelected: (v) => setState(() => _filter = v ? 'PENDING' : 'ALL')),
          ChoiceChip(label: const Text('Approved', style: TextStyle(fontSize: 9)), selected: _filter == 'APPROVED', onSelected: (v) => setState(() => _filter = v ? 'APPROVED' : 'ALL')),
          ChoiceChip(label: const Text('Rejected', style: TextStyle(fontSize: 9)), selected: _filter == 'REJECTED', onSelected: (v) => setState(() => _filter = v ? 'REJECTED' : 'ALL')),
          ChoiceChip(label: const Text('Suspended', style: TextStyle(fontSize: 9)), selected: _filter == 'SUSPENDED', onSelected: (v) => setState(() => _filter = v ? 'SUSPENDED' : 'ALL')),
        ],
      )),
      const SizedBox(height: 8),
      Expanded(child: filtered.isEmpty ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.group_off_rounded, size: 48, color: AppColors.textGrey), const SizedBox(height: 10), Text('No sellers found.', style: TextStyle(color: AppColors.textGrey))])) : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) => _SellerRow(seller: filtered[index], onUpdate: widget.onUpdate),
      )),
    ]);
  }
}
