import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/order_timeline.dart';
import '../../widgets/product_image.dart';

/// The buyer's marketplace orders with live status, cancellation and a
/// full detail sheet (timeline, delivery, tracking).
class MarketplaceOrdersScreen extends ConsumerStatefulWidget {
  const MarketplaceOrdersScreen({super.key});

  @override
  ConsumerState<MarketplaceOrdersScreen> createState() => _MarketplaceOrdersScreenState();
}

enum _Filter { all, active, closed }

class _MarketplaceOrdersScreenState extends ConsumerState<MarketplaceOrdersScreen> {
  List<MarketplaceOrder> _orders = const [];
  bool _loading = true, _failed = false;
  _Filter _filter = _Filter.all;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final orders = await Api.I.marketplaceOrders();
      if (!mounted) return;
      orders.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      setState(() {
        _orders = orders;
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

  List<MarketplaceOrder> get _visible => switch (_filter) {
        _Filter.all => _orders,
        _Filter.active => _orders.where((o) => o.isActive).toList(),
        _Filter.closed => _orders.where((o) => !o.isActive).toList(),
      };

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
        appBar: AppBar(title: const Text('My orders')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined, size: 46, color: AppColors.textGrey),
                SizedBox(height: 12),
                Text(
                  'Orders are for customer accounts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
                SizedBox(height: 6),
                Text(
                  'Sign in with a customer account to track marketplace orders.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text('My orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  count: _orders.length,
                  selected: _filter == _Filter.all,
                  onTap: () => setState(() => _filter = _Filter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'In progress',
                  count: _orders.where((o) => o.isActive).length,
                  selected: _filter == _Filter.active,
                  onTap: () => setState(() => _filter = _Filter.active),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Closed',
                  count: _orders.where((o) => !o.isActive).length,
                  selected: _filter == _Filter.closed,
                  onTap: () => setState(() => _filter = _Filter.closed),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
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
            const Text('Orders could not be loaded.'),
            const SizedBox(height: 14),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: const BoxDecoration(color: AppColors.blueSoft, shape: BoxShape.circle),
                child: const Icon(Icons.receipt_long_rounded, size: 36, color: AppColors.blue),
              ),
              const SizedBox(height: 14),
              const Text(
                'No orders here yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              Text(
                _filter == _Filter.all
                    ? 'When you request a product, it shows up here with live updates.'
                    : 'Nothing in this view right now.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.coral,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 26),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _OrderCard(
          order: visible[index],
          onTap: () => _openDetail(visible[index]),
        ),
      ),
    );
  }

  void _openDetail(MarketplaceOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailSheet(
        initialOrder: order,
        onChanged: _load,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? AppColors.navy : AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.navy,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: .22) : AppColors.chipGrey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : AppColors.textGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OrderCard extends StatelessWidget {
  final MarketplaceOrder order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              ProductImage(
                productId: o.product?.id ?? '',
                imageId: o.product?.imageId,
                width: 78,
                height: 78,
                borderRadius: BorderRadius.circular(15),
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
                              height: 1.3,
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
                      'Qty ${o.quantity} · ${formatMoney(o.amountMinor, o.currency)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (o.seller?.displayName != null) o.seller!.displayName,
                        _date(o.createdAt),
                      ].join(' · '),
                      style: const TextStyle(fontSize: 9.5, color: AppColors.textGrey, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

class _OrderDetailSheet extends StatefulWidget {
  final MarketplaceOrder initialOrder;
  final Future<void> Function() onChanged;
  const _OrderDetailSheet({required this.initialOrder, required this.onChanged});

  @override
  State<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends State<_OrderDetailSheet> {
  late MarketplaceOrder _order;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text('The seller will be notified and any reserved stock is released.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final updated = await Api.I.cancelMarketplaceOrder(_order.id);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _busy = false;
      });
      await widget.onChanged();
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('Could not cancel the order. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .4,
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
                          'Order ${o.reference}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -.3, color: AppColors.navy),
                        ),
                      ),
                      StatusPill(o.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(o.title, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textGrey)),
                  const SizedBox(height: 16),
                  _sectionTitle('Progress'),
                  OrderTimeline(kind: o.kind, status: o.status),
                  _sectionTitle('Details'),
                  _detailRow('Seller', o.seller?.displayName ?? 'D2F Direct'),
                  _detailRow('Quantity', '${o.quantity}'),
                  _detailRow('Total', formatMoney(o.amountMinor, o.currency)),
                  if (o.delivery != null) _detailRow('Deliver to', o.delivery!),
                  if ((o.deliveryAddress ?? '').isNotEmpty) _detailRow('Address', o.deliveryAddress!),
                  if ((o.notes ?? '').isNotEmpty) _detailRow('Your note', o.notes!),
                  if ((o.trackingRef ?? '').isNotEmpty)
                    _copyRow('Carrier reference', o.trackingRef!),
                  if ((o.parcelTrackingId ?? '').isNotEmpty)
                    _copyRow('Parcel tracking number', o.parcelTrackingId!),
                  const SizedBox(height: 8),
                  if (o.status == 'REQUESTED')
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _cancel,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cancel_outlined, size: 19),
                        label: const Text('Cancel this order'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.coral,
                          side: const BorderSide(color: AppColors.coral),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                    )
                  else if (o.status == 'QUOTED')
                    const SizedBox.shrink()
                  else
                    const _SupportNote(),
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
        padding: const EdgeInsets.only(top: 14, bottom: 10),
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
              width: 132,
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textGrey),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.45),
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
              width: 132,
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textGrey),
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
                      icon: const Icon(Icons.copy_rounded, size: 17, color: AppColors.blue),
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

class _SupportNote extends StatelessWidget {
  const _SupportNote();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.support_agent_rounded, size: 20, color: AppColors.textGrey),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Need to change or cancel now? Contact D2F support — accepted orders can’t be cancelled in-app.',
                style: TextStyle(fontSize: 10.5, height: 1.55, color: AppColors.textGrey),
              ),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('mailto:info@d2fshipping.com'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Email'),
            ),
          ],
        ),
      );
}
