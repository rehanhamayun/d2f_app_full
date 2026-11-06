import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/order_timeline.dart';
import '../../widgets/product_image.dart';

/// The seller's order inbox: accept, decline, prepare, ship, complete —
/// with the buyer's contact details unlocking after acceptance.
class SellerOrdersTab extends StatefulWidget {
  final Future<void> Function() onChanged;
  const SellerOrdersTab({super.key, required this.onChanged});

  @override
  State<SellerOrdersTab> createState() => _SellerOrdersTabState();
}

enum _OrderFilter { newRequests, active, done, all }

class _SellerOrdersTabState extends State<SellerOrdersTab> {
  List<MarketplaceOrder> _orders = const [];
  bool _loading = true, _failed = false;
  _OrderFilter _filter = _OrderFilter.newRequests;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final orders = await Api.I.sellerOrders();
      if (!mounted) return;
      orders.sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
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
    _OrderFilter.newRequests =>
      _orders.where((o) => o.status == 'REQUESTED').toList(),
    _OrderFilter.active =>
      _orders
          .where(
            (o) =>
                const {'ACCEPTED', 'PROCESSING', 'SHIPPED'}.contains(o.status),
          )
          .toList(),
    _OrderFilter.done =>
      _orders
          .where((o) => const {'COMPLETED', 'CANCELLED'}.contains(o.status))
          .toList(),
    _OrderFilter.all => _orders,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.coral),
      );
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.textGrey,
            ),
            const SizedBox(height: 8),
            const Text('Orders could not be loaded.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final newCount = _orders.where((o) => o.status == 'REQUESTED').length;
    final activeCount = _orders
        .where(
          (o) => const {'ACCEPTED', 'PROCESSING', 'SHIPPED'}.contains(o.status),
        )
        .length;
    final doneCount = _orders
        .where((o) => const {'COMPLETED', 'CANCELLED'}.contains(o.status))
        .length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                label: 'New',
                count: newCount,
                selected: _filter == _OrderFilter.newRequests,
                onTap: () => setState(() => _filter = _OrderFilter.newRequests),
              ),
              _Chip(
                label: 'Active',
                count: activeCount,
                selected: _filter == _OrderFilter.active,
                onTap: () => setState(() => _filter = _OrderFilter.active),
              ),
              _Chip(
                label: 'Done',
                count: doneCount,
                selected: _filter == _OrderFilter.done,
                onTap: () => setState(() => _filter = _OrderFilter.done),
              ),
              _Chip(
                label: 'All',
                count: _orders.length,
                selected: _filter == _OrderFilter.all,
                onTap: () => setState(() => _filter = _OrderFilter.all),
              ),
            ],
          ),
        ),
        Expanded(
          child: _visible.isEmpty
              ? SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 78,
                          height: 78,
                          decoration: const BoxDecoration(
                            color: AppColors.blueSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.inbox_rounded,
                            size: 34,
                            color: AppColors.blue,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _filter == _OrderFilter.newRequests
                              ? 'No new requests'
                              : 'Nothing here yet',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Orders for your listings appear here — accept them, arrange delivery and keep buyers posted.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.6,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.coral,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
                    itemCount: _visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 11),
                    itemBuilder: (context, index) => _SellerOrderCard(
                      order: _visible[index],
                      onChanged: () async {
                        await _load();
                        await widget.onChanged();
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.navy : Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.navy,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: selected ? AppColors.gold : AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SellerOrderCard extends StatelessWidget {
  final MarketplaceOrder order;
  final Future<void> Function() onChanged;
  const _SellerOrderCard({required this.order, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final proceeds = o.amountMinor != null
        ? o.amountMinor! - (o.commissionMinor ?? 0)
        : null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              _SellerOrderSheet(initialOrder: o, onChanged: onChanged),
        ),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              ProductImage(
                productId: o.product?.id ?? '',
                imageId: o.product?.imageId,
                width: 66,
                height: 66,
                borderRadius: BorderRadius.circular(13),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        StatusPill(o.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qty ${o.quantity} · ${formatMoney(o.amountMinor, o.currency)}${o.delivery != null ? ' · ${o.delivery}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textGrey,
                      ),
                    ),
                    if (o.commissionBps != null && proceeds != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'After ${_rate(o.commissionBps!)} commission you keep ${formatMoney(proceeds, o.currency)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9A7100),
                          ),
                        ),
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

  String _rate(int bps) =>
      '${(bps / 100).toStringAsFixed(bps % 100 == 0 ? 0 : 1)}%';
}

class _SellerOrderSheet extends StatefulWidget {
  final MarketplaceOrder initialOrder;
  final Future<void> Function() onChanged;
  const _SellerOrderSheet({
    required this.initialOrder,
    required this.onChanged,
  });

  @override
  State<_SellerOrderSheet> createState() => _SellerOrderSheetState();
}

class _SellerOrderSheetState extends State<_SellerOrderSheet> {
  late MarketplaceOrder _order;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
  }

  Future<void> _act(
    String action, {
    String? reason,
    String? trackingRef,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await Api.I.sellerOrderAction(
        _order.id,
        action,
        reason: reason,
        trackingRef: trackingRef,
      );
      if (!mounted) return;
      setState(() {
        _order = updated;
        _busy = false;
      });
      await widget.onChanged();
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('That action did not go through. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    authMessage(context, message);
  }

  Future<void> _reasonDialog({
    required String title,
    required String label,
    required String confirm,
    required Future<void> Function(String reason) onConfirm,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: AppColors.cream,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    await onConfirm(result);
  }

  Future<void> _shipDialog() async {
    final controller = TextEditingController(text: _order.trackingRef ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as shipped'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Carrier reference (optional)',
            hintText: 'e.g. DHL-884421 or GX-220-001',
            filled: true,
            fillColor: AppColors.cream,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Mark shipped'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _act('ship', trackingRef: result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final accepted = o.status != 'REQUESTED';
    final proceeds = o.amountMinor != null
        ? o.amountMinor! - (o.commissionMinor ?? 0)
        : null;
    return DraggableScrollableSheet(
      initialChildSize: .78,
      minChildSize: .45,
      maxChildSize: .95,
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order ${o.reference}',
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
                  _sectionTitle('Progress'),
                  OrderTimeline(kind: o.kind, status: o.status),
                  _sectionTitle('Order'),
                  _detailRow('Quantity', '${o.quantity}'),
                  _detailRow('Total', formatMoney(o.amountMinor, o.currency)),
                  if (o.commissionBps != null)
                    _detailRow(
                      'Commission (${(o.commissionBps! / 100).toStringAsFixed(1)}%)',
                      formatMoney(o.commissionMinor, o.currency),
                    ),
                  if (proceeds != null)
                    _detailRow('You keep', formatMoney(proceeds, o.currency)),
                  if ((o.notes ?? '').isNotEmpty)
                    _detailRow('Buyer note', o.notes!),
                  const SizedBox(height: 6),
                  _sectionTitle('Delivery'),
                  if (!accepted)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.chipGrey,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: AppColors.border,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 18,
                            color: AppColors.textGrey,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Buyer contact details unlock after you accept — they’re only shared so you can arrange delivery.',
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.55,
                                color: AppColors.textGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if ((o.recipientName ?? '').isNotEmpty)
                      _detailRow('Recipient', o.recipientName!),
                    if ((o.recipientPhone ?? '').isNotEmpty)
                      _detailRow('Phone', o.recipientPhone!),
                    if ((o.deliveryAddress ?? '').isNotEmpty)
                      _detailRow('Address', o.deliveryAddress!),
                    if (o.delivery != null)
                      _detailRow('City · Country', o.delivery!),
                  ],
                  if ((o.trackingRef ?? '').isNotEmpty)
                    _detailRow('Carrier reference', o.trackingRef!),
                  const SizedBox(height: 14),
                  ..._actions(o),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(MarketplaceOrder o) {
    if (_busy) {
      return [
        const SizedBox(height: 8),
        const Center(child: CircularProgressIndicator(color: AppColors.coral)),
      ];
    }
    switch (o.status) {
      case 'REQUESTED':
        return [
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _act('accept'),
              icon: const Icon(Icons.check_rounded, color: Colors.white),
              label: const Text(
                'Accept order',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
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
              onPressed: () => _reasonDialog(
                title: 'Decline order',
                label: 'Why can’t you fulfil this?',
                confirm: 'Decline',
                onConfirm: (reason) => _act('decline', reason: reason),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.coral,
                side: const BorderSide(color: AppColors.coral),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Decline with reason'),
            ),
          ),
        ];
      case 'ACCEPTED':
        return [
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _act('advance'),
              icon: const Icon(Icons.inventory_2_outlined, color: Colors.white),
              label: const Text(
                'Start preparing',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _reasonDialog(
              title: 'Cancel order',
              label: 'Why is this order cancelled?',
              confirm: 'Cancel order',
              onConfirm: (reason) => _act('cancel', reason: reason),
            ),
            style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            child: const Text('Cancel this order'),
          ),
        ];
      case 'PROCESSING':
        return [
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _shipDialog,
              icon: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.white,
              ),
              label: const Text(
                'Mark as shipped',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _reasonDialog(
              title: 'Cancel order',
              label: 'Why is this order cancelled?',
              confirm: 'Cancel order',
              onConfirm: (reason) => _act('cancel', reason: reason),
            ),
            style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            child: const Text('Cancel this order'),
          ),
        ];
      case 'SHIPPED':
        return [
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _act('complete'),
              icon: const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              label: const Text(
                'Mark completed',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
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
}
