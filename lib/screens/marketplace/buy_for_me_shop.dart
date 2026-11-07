import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/order_timeline.dart';
import 'buy_for_me_request_form.dart';

/// Buy For Me: the customer describes an item from any store; D2F quotes the
/// total, the customer accepts, and D2F buys and ships it.
class BuyForMeShop extends ConsumerStatefulWidget {
  const BuyForMeShop({super.key});

  @override
  ConsumerState<BuyForMeShop> createState() => _BuyForMeShopState();
}

class _BuyForMeShopState extends ConsumerState<BuyForMeShop> {
  List<MarketplaceOrder> _requests = const [];
  bool _loading = true, _failed = false;

  bool _loadStarted = false;

  /// Fetch requests only once auth resolves to a CUSTOMER account.
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
    ref.listenManual(
      authControllerProvider.select((state) => state.valueOrNull?.id),
      (_, _) => _maybeLoad(),
      fireImmediately: true,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final requests = await Api.I.buyForMeRequests();
      if (!mounted) return;
      requests.sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
      setState(() {
        _requests = requests;
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

  Future<void> _newRequest() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => const BuyForMeRequestFormScreen(),
      ),
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
        if (ref.read(authControllerProvider).valueOrNull?.role ==
            UserRole.CUSTOMER) {
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
          if (canShop)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _newRequest,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text(
                  'Start a purchase request',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
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
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.35,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                if (_requests.isNotEmpty)
                  Text(
                    '${_requests.length} ${_requests.length == 1 ? 'request' : 'requests'}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGrey,
                    ),
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
          Icon(
            Icons.shopping_bag_outlined,
            size: 46,
            color: AppColors.textGrey,
          ),
          SizedBox(height: 12),
          Text(
            'Buy For Me is for customer accounts',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Sign in with a customer account to place purchase requests.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.textGrey,
            ),
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
          Image.asset(
            'assets/images/services_buy.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(.45, .2),
            excludeFromSemantics: true,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF3B0517).withValues(alpha: .93),
                  const Color(0xFF6E1230).withValues(alpha: .55),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8FA8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'BUY FOR ME',
                      style: TextStyle(
                        color: Color(0xFF40000F),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'See it. Send it.\nWe’ll get it.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      height: 1.14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Amazon, Walmart, eBay or any store —\nshare the link and D2F buys and ships it.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _howItWorks() {
    const steps = [
      (
        Icons.link_rounded,
        'Share the link',
        'Paste the product or\ndescribe what you need',
      ),
      (
        Icons.request_quote_rounded,
        'We quote the total',
        'Item + your budget —\nyou see the full price',
      ),
      (
        Icons.local_shipping_rounded,
        'Accept & we ship',
        'We buy it, then air or\nsea freight to you',
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: _StepCard(
              number: i + 1,
              icon: steps[i].$1,
              title: steps[i].$2,
              body: steps[i].$3,
            ),
          ),
          if (i < steps.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _requestsBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(34),
        child: Center(child: CircularProgressIndicator(color: AppColors.coral)),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.textGrey,
            ),
            const SizedBox(height: 8),
            const Text('Requests could not be loaded.'),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_requests.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: const BoxDecoration(
                color: AppColors.coralSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 30,
                color: AppColors.coral,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your first request is one tap away',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Send us any store link or describe the item — we’ll confirm what’s possible and quote the total, including shipping to your door.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final request in _requests) ...[
          _RequestCard(
            order: request,
            onTap: () => _openDetail(request),
            onRefresh: _load,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  void _openDetail(MarketplaceOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _RequestDetailSheet(initialOrder: order, onChanged: _load),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title, body;
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE4EC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: const Color(0xFFDC3765)),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 8,
            height: 1.45,
            color: AppColors.textGrey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _RequestCard extends StatelessWidget {
  final MarketplaceOrder order;
  final VoidCallback onTap;
  final Future<void> Function() onRefresh;
  const _RequestCard({
    required this.order,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    final quoted = o.status == 'QUOTED';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: quoted
                  ? AppColors.coral.withValues(alpha: .5)
                  : AppColors.border,
              width: quoted ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4EC),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Color(0xFFDC3765),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.32,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusPill(o.status),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Qty ${o.quantity}${o.budgetMinor != null ? ' · Budget ${formatMoney(o.budgetMinor, o.currency)}' : ''} · ${_date(o.createdAt)}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (quoted && o.amountMinor != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.coralSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.request_quote_rounded,
                              size: 14,
                              color: AppColors.coral,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'D2F quote: ${formatMoney(o.amountMinor, o.currency)} · Respond now',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppColors.coral,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _RequestDetailSheet extends StatefulWidget {
  final MarketplaceOrder initialOrder;
  final Future<void> Function() onChanged;
  const _RequestDetailSheet({
    required this.initialOrder,
    required this.onChanged,
  });

  @override
  State<_RequestDetailSheet> createState() => _RequestDetailSheetState();
}

class _RequestDetailSheetState extends State<_RequestDetailSheet> {
  late MarketplaceOrder _order;
  final _transactionId = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
  }

  @override
  void dispose() {
    _transactionId.dispose();
    super.dispose();
  }

  Future<void> _submitPaymentEvidence() async {
    final transactionId = _transactionId.text.trim();
    if (transactionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the payment transaction ID first.'),
        ),
      );
      return;
    }
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.I.submitBuyForMePaymentEvidence(
        requestId: _order.id,
        transactionId: transactionId,
        bytes: await image.readAsBytes(),
      );
      final refreshed = (await Api.I.buyForMeRequests()).firstWhere(
        (item) => item.id == _order.id,
      );
      if (!mounted) return;
      setState(() {
        _order = refreshed;
        _busy = false;
      });
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment proof sent securely to D2F for review.'),
          ),
        );
      }
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('Payment proof could not be submitted. Please try again.');
    }
  }

  Future<void> _viewUpdateImage(ServiceOrderUpdate update) async {
    try {
      final bytes = await Api.I.buyForMeUpdateImage(_order.id, update.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      );
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('The D2F update image could not be opened.');
    }
  }

  Future<void> _decide(String decision) async {
    if (decision == 'accept') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Accept the quote?'),
          content: Text(
            'D2F will purchase ${_order.title} for ${formatMoney(_order.amountMinor, _order.currency)} including the agreed terms, then ship it to you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Accept quote'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      final updated = await Api.I.buyForMeDecision(_order.id, decision);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _busy = false;
      });
      await widget.onChanged();
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('Could not update the request. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return DraggableScrollableSheet(
      initialChildSize: .74,
      minChildSize: .45,
      maxChildSize: .94,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD8D4C9),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Request ${o.reference}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.3,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      StatusPill(o.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    o.title,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if ((o.sourceUrl ?? '').isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(o.sourceUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(
                        Uri.tryParse(o.sourceUrl!)?.host ?? 'Open product page',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  _sectionTitle('Progress'),
                  OrderTimeline(kind: o.kind, status: o.status),
                  _sectionTitle('Details'),
                  _detailRow('Quantity', '${o.quantity}'),
                  if (o.budgetMinor != null)
                    _detailRow(
                      'Your budget',
                      formatMoney(o.budgetMinor, o.currency),
                    ),
                  if (o.productCostMinor != null)
                    _detailRow(
                      'Product cost',
                      formatMoney(o.productCostMinor, o.currency),
                    ),
                  if (o.shippingCostMinor != null)
                    _detailRow(
                      'Shipping cost',
                      formatMoney(o.shippingCostMinor, o.currency),
                    ),
                  if (o.amountMinor != null)
                    _detailRow(
                      'Subtotal',
                      formatMoney(o.amountMinor, o.currency),
                    ),
                  if ((o.notes ?? '').isNotEmpty)
                    _detailRow('Your note', o.notes!),
                  if ((o.deliveryAddress ?? '').isNotEmpty)
                    _detailRow(
                      'Ship to',
                      [
                            o.deliveryAddress,
                            o.deliveryCity,
                            o.deliveryStateProvince,
                            o.deliveryPostalCode,
                            o.deliveryCountry,
                          ]
                          .where(
                            (part) => part != null && part.trim().isNotEmpty,
                          )
                          .join(', '),
                    ),
                  if (o.deliveryService != null)
                    _detailRow('Delivery option', o.deliveryService!),
                  if (o.shippingCarrier != null)
                    _detailRow('Carrier', o.shippingCarrier!),
                  if ((o.shippingTrackingNumber ?? '').isNotEmpty)
                    _copyRow('Tracking number', o.shippingTrackingNumber!),
                  if ((o.trackingRef ?? '').isNotEmpty)
                    _copyRow('Carrier reference', o.trackingRef!),
                  if ((o.parcelTrackingId ?? '').isNotEmpty)
                    _copyRow('Parcel tracking number', o.parcelTrackingId!),
                  if (o.shippingLabelUrl != null)
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(o.shippingLabelUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.local_shipping_outlined, size: 16),
                      label: const Text('Open shipping label'),
                    ),
                  if (o.updates.isNotEmpty) ...[
                    _sectionTitle('D2F updates'),
                    for (final update in o.updates)
                      Container(
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (update.status != null)
                              Text(
                                update.status!.replaceAll('_', ' '),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy,
                                ),
                              ),
                            if (update.message.isNotEmpty) Text(update.message),
                            if (update.shippingTrackingNumber != null)
                              _copyRow(
                                'Tracking',
                                update.shippingTrackingNumber!,
                              ),
                            if (update.shippingLabelUrl != null)
                              TextButton(
                                onPressed: () => launchUrl(
                                  Uri.parse(update.shippingLabelUrl!),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: const Text('View shipping label'),
                              ),
                            if (update.fileName != null)
                              TextButton.icon(
                                onPressed: () => _viewUpdateImage(update),
                                icon: const Icon(
                                  Icons.image_outlined,
                                  size: 16,
                                ),
                                label: const Text('View D2F update image'),
                              ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  if (o.status == 'QUOTED') ...[
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _decide('accept'),
                        icon: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Accept quote${o.amountMinor != null ? ' · ${formatMoney(o.amountMinor, o.currency)}' : ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.coral,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _decide('decline'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.coral,
                          side: const BorderSide(color: AppColors.coral),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Decline quote'),
                      ),
                    ),
                  ] else if (o.status == 'REQUESTED')
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _decide('cancel'),
                        icon: const Icon(Icons.cancel_outlined, size: 19),
                        label: const Text('Cancel this request'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.coral,
                          side: const BorderSide(color: AppColors.coral),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  if (o.status == 'ACCEPTED') ...[
                    _sectionTitle('Pay D2F securely'),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.blueSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment instructions',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            o.paymentInstructions ??
                                'Please contact D2F to confirm payment instructions before paying.',
                          ),
                          if (o.paymentStatus == 'VERIFIED')
                            const Text(
                              'Payment verified by D2F.',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            )
                          else if (o.paymentStatus == 'PENDING')
                            const Text(
                              'Payment proof received. D2F is verifying it.',
                            )
                          else ...[
                            if ((o.paymentStatus ?? '') == 'REJECTED')
                              Text(
                                o.paymentSubmissions.isNotEmpty
                                    ? (o.paymentSubmissions.first.reviewNote ??
                                          'Please submit corrected payment proof.')
                                    : 'Please submit corrected payment proof.',
                              ),
                            const SizedBox(height: 9),
                            TextField(
                              controller: _transactionId,
                              decoration: const InputDecoration(
                                labelText: 'Transaction ID',
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : _submitPaymentEvidence,
                                icon: const Icon(Icons.attach_file_rounded),
                                label: Text(
                                  _busy
                                      ? 'Sending…'
                                      : 'Attach screenshot & send for review',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: AppColors.textGrey,
      ),
    ),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textGrey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _copyRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textGrey,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.blueSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.blue,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 17,
                    color: AppColors.blue,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard.')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
