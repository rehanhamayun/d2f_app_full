import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth_widgets.dart';
import 'ship_for_me_request_form.dart';
import 'ship_for_me_terms.dart';
import 'ship_for_me_warehouse.dart';
/// Separate from Buy For Me where D2F purchases on the customer's behalf.
class ShipForMeShop extends ConsumerStatefulWidget {
  const ShipForMeShop({super.key});

  @override
  ConsumerState<ShipForMeShop> createState() => _ShipForMeShopState();
}

class _ShipForMeShopState extends ConsumerState<ShipForMeShop> {
  List<Map<String, dynamic>> _requests = const [];
  bool _loading = true, _failed = false;
  bool _loadStarted = false;
  Map<String, dynamic>? _warehouseAddress;
  Map<String, dynamic>? _terms;
  bool _termsAccepted = false;

  void _maybeLoad() {
    if (_loadStarted) return;
    final role = ref.read(authControllerProvider).valueOrNull?.role;
    if (role == null) return;
    _loadStarted = true;
    if (role == UserRole.CUSTOMER) {
      _load();
      _loadWarehouseAddress();
      _loadTerms();
    }
  }

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final requests = await Api.I.shipForMeRequests();
      if (!mounted) return;
      requests.sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }

  Future<void> _loadWarehouseAddress() async {
    try {
      final addr = await Api.I.getShipForMeWarehouseAddress();
      if (!mounted) return;
      setState(() => _warehouseAddress = addr);
    } catch (_) {
      // Warehouse address may not be configured yet
    }
  }

  Future<void> _loadTerms() async {
    try {
      final terms = await Api.I.getShipForMeTerms();
      if (!mounted) return;
      setState(() => _terms = terms);
      // Check if customer already accepted
      final me = ref.read(authControllerProvider).valueOrNull;
      if (me != null) {
        // The acceptance is checked server-side when creating requests
        _termsAccepted = true; // Optimistic; server enforces
      }
    } catch (_) {
      // Terms may not be configured
    }
  }

  Future<void> _acceptTerms() async {
    if (_terms == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ShipForMeTermsScreen(
          agreementId: _terms!['id'],
          version: _terms!['version'],
          title: _terms!['title'],
          content: _terms!['content'],
        ),
      ),
    );
    if (result == true) {
      setState(() => _termsAccepted = true);
      _load();
    }
  }

  Future<void> _newRequest() async {
    if (!_termsAccepted) {
      _acceptTerms();
      return;
    }
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => const ShipForMeRequestFormScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).valueOrNull?.role;
    if (role != null && role != UserRole.CUSTOMER) return _staffNotice();
    final canShop = role == UserRole.CUSTOMER || role == null;

    return RefreshIndicator(
      color: AppColors.coral,
      onRefresh: () async {
        if (ref.read(authControllerProvider).valueOrNull?.role == UserRole.CUSTOMER) {
          await _load();
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 26),
        children: [
          _hero(),
          const SizedBox(height: 14),
          _howItWorks(),
          const SizedBox(height: 16),
          if (_warehouseAddress != null) ...[
            _warehouseCard(),
            const SizedBox(height: 16),
          ],
          if (!_termsAccepted) ...[
            _termsBanner(),
            const SizedBox(height: 16),
          ],
          if (canShop)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _termsAccepted ? _newRequest : _acceptTerms,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text(
                  _termsAccepted
                      ? 'Register a purchase'
                      : 'Accept terms to begin',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _termsAccepted ? AppColors.coral : AppColors.gold,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (canShop) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'My requests',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.35, color: AppColors.navy),
                  ),
                ),
                if (_requests.isNotEmpty)
                  Text(
                    '${_requests.length} ${_requests.length == 1 ? 'request' : 'requests'}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textGrey),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (canShop) _requestsBody(),
        ],
      ),
    );
  }

  Widget _staffNotice() => const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_shipping_outlined, size: 46, color: AppColors.textGrey),
              SizedBox(height: 12),
              Text(
                'Ship For Me is for customer accounts',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
              SizedBox(height: 6),
              Text(
                'Sign in with a customer account to use Ship For Me.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey),
              ),
            ],
          ),
        ),
      );

  Widget _hero() => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1.92,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.deepTeal, AppColors.deepBlue],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.coral.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'SHIP FOR ME',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.coral, letterSpacing: 1),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Shop anywhere, ship with D2F',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -.5),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Buy from Amazon, Walmart, eBay or any store. We receive your package at our US warehouse and ship it to you.',
                      style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _howItWorks() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How it works', style: AppTheme.sectionTitle),
            const SizedBox(height: 12),
            _Step(1, 'Shop', 'Buy from any US retailer with your own card.'),
            _Step(2, 'Ship to D2F', 'Send your package to your D2F warehouse address.'),
            _Step(3, 'We receive', 'D2F logs your package, measures it, and sends photos.'),
            _Step(4, 'Pay & ship', 'Accept the shipping quote and we forward it to you.'),
          ],
        ),
      );

  Widget _Step(int n, String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
              child: Center(child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 14))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.navy)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, height: 1.4, color: AppColors.textGrey)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _warehouseCard() => Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.blueSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.blue.withValues(alpha: .3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warehouse_rounded, size: 20, color: AppColors.blue),
                const SizedBox(width: 8),
                const Text('Your warehouse address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.navy)),
                const Spacer(),
                Text('ID: ${_warehouseAddress!['customerWarehouseId'] ?? '—'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.blue, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${_warehouseAddress!['addressLine1']}, ${_warehouseAddress!['city']}, ${_warehouseAddress!['stateProvince'] ?? ''} ${_warehouseAddress!['postalCode']}, ${_warehouseAddress!['country']}',
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textGrey),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShipForMeWarehouseScreen()),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.blue),
                label: const Text('Copy address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.blue)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.blue.withValues(alpha: .5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _termsBanner() => Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.goldSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: .5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_rounded, size: 20, color: AppColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Terms required', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.navy)),
                  const SizedBox(height: 2),
                  Text(
                    'Accept the Ship For Me terms before registering a purchase.',
                    style: const TextStyle(fontSize: 11, height: 1.4, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _acceptTerms,
              child: const Text('Accept terms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.coral)),
            ),
          ],
        ),
      );

  Widget _requestsBody() {
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
            const Text('Your requests could not be loaded.'),
            const SizedBox(height: 14),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_shipping_outlined, size: 48, color: AppColors.textGrey),
              SizedBox(height: 14),
              Text('No requests yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy)),
              SizedBox(height: 6),
              Text('Register your first purchase and we’ll handle the shipping.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey)),
            ],
          ),
        ),
      );
    }
    return Column(
      children: _requests.map((r) => _requestCard(r)).toList(),
    );
  }

  Widget _requestCard(Map<String, dynamic> r) {
    final status = (r['status'] as String?) ?? 'DRAFT';
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['itemDescription'] ?? 'Purchase request', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.navy)),
                      const SizedBox(height: 4),
                      Text('Retailer: ${r['retailerName'] ?? '—'}', style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                      if ((r['retailerOrderId'] ?? '').isNotEmpty)
                        Text('Order: ${r['retailerOrderId']}', style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                    ],
                  ),
                ),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: .14), borderRadius: BorderRadius.circular(8), border: Border.all(color: _statusColor(status).withValues(alpha: .5))),
                    child: Text(status, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _statusColor(status), letterSpacing: .4)),
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  if ((r['declaredValueMinor'] as int?) != null)
                    Text('Declared: \$${(r['declaredValueMinor'] as int) / 100}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textGrey)),
                  if ((r['totalQuoteMinor'] as int?) != null) ...[
                    const SizedBox(width: 12),
                    Text('Quote: \$${(r['totalQuoteMinor'] as int) / 100}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.coral)),
                  ],
                  const Spacer(),
                  if (status == 'QUOTED' || status == 'ACCEPTED')
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ShipForMePaymentScreen(request: r)),
                      ),
                      child: const Text('Pay shipping', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.coral)),
                    ),
                  if (status == 'SHIPPED' && (r['carrierTrackingId'] as String?) != null)
                    TextButton(
                      onPressed: () => {},
                      child: const Text('Track', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.blue)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Color _statusColor(String status) => switch (status) {
    'DRAFT' => AppColors.textGrey,
    'SUBMITTED' => AppColors.gold,
    'RECEIVED' => AppColors.blue,
    'QUOTED' => AppColors.gold,
    'ACCEPTED' => AppColors.blue,
    'PAID' => AppColors.green,
    'SHIPPED' => AppColors.green,
    'COMPLETED' => AppColors.green,
    'CANCELLED' => AppColors.coral,
    'BLOCKED' => AppColors.coral,
    _ => AppColors.navy,
  };
}

class ShipForMePaymentScreen extends StatelessWidget {
  final Map<String, dynamic> request;
  const ShipForMePaymentScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final total = (request['totalQuoteMinor'] as int?) ?? 0;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text('Pay shipping quote')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Shipping quote', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Shipping fee', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                    Text('\$${((request['shippingFeeMinor'] as int?) ?? 0) / 100}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Handling fee', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                    Text('\$${((request['handlingFeeMinor'] as int?) ?? 0) / 100}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Insurance', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                    Text('\$${((request['insuranceFeeMinor'] as int?) ?? 0) / 100}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)),
                    Text('\$${total / 100}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.coral)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Payment method', style: AppTheme.sectionTitle),
                const SizedBox(height: 12),
                _PaymentOption(Icons.credit_card, 'Credit / Debit Card', 'Pay with your card'),
                const SizedBox(height: 10),
                _PaymentOption(Icons.account_balance, 'Bank Transfer / ACH', 'Bank transfer details'),
                const SizedBox(height: 10),
                _PaymentOption(Icons.phone_android, 'Mobile Money (Togo)', 'Flooz / T-Money'),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: AppColors.coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                    child: const Text('Pay now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PaymentOption(this.icon, this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: Row(
      children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(10)), child: Center(child: Icon(icon, size: 20, color: AppColors.blue))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(fontSize: 10.5, color: AppColors.textGrey))])),
        const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textGrey),
      ],
    ),
  );
}
