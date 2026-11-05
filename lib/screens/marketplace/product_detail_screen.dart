import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/product_image.dart';
import 'checkout_screen.dart';
import 'marketplace_orders_screen.dart';

/// Full-screen product view. Photos load with the session token; ordering
/// routes into the checkout flow.
class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  MarketplaceProduct? _product;
  bool _loading = true, _failed = false;
  int _quantity = 1;
  int _photo = 0;
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final product = await Api.I.marketplaceProduct(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = product;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(child: CircularProgressIndicator(color: AppColors.coral)),
      );
    }
    if (_failed || _product == null) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(title: const Text('Product')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textGrey),
              const SizedBox(height: 12),
              const Text('That product could not be loaded.'),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final p = _product!;
    final total = p.priceMinor * _quantity;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(p.category, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () {
              final canShop = ref.read(authControllerProvider).valueOrNull?.role ==
                  UserRole.CUSTOMER;
              if (!canShop) {
                authMessage(context, 'Orders are tracked on customer accounts.');
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MarketplaceOrdersScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _gallery(p),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        formatMoney(p.priceMinor, p.currency),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    _FulfillmentBadge(fulfillment: p.fulfillment),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Delivery is arranged after you order — nothing is charged now.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textGrey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Text(
                  p.title,
                  style: const TextStyle(
                    fontSize: 21,
                    height: 1.22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(icon: Icons.category_outlined, label: p.category),
                    if ((p.location ?? '').isNotEmpty)
                      _Tag(icon: Icons.place_outlined, label: p.location!),
                    _StockTag(product: p),
                  ],
                ),
                const SizedBox(height: 16),
                _SellerCard(seller: p.seller),
                const SizedBox(height: 16),
                if ((p.description ?? '').trim().isNotEmpty) ...[
                  const Text('About this item', style: AppTheme.sectionTitle),
                  const SizedBox(height: 8),
                  Text(
                    p.description!.trim(),
                    style: const TextStyle(fontSize: 13.5, height: 1.65, color: Color(0xFF2B3446)),
                  ),
                  const SizedBox(height: 16),
                ],
                _DeliveryCard(fulfillment: p.fulfillment),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(p, total),
    );
  }

  Widget _gallery(MarketplaceProduct p) {
    final count = p.images.length;
    return SizedBox(
      height: 330,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: count == 0 ? 1 : count,
            onPageChanged: (index) => setState(() => _photo = index),
            itemBuilder: (context, index) => ProductImage(
              productId: p.id,
              imageId: count == 0 ? null : p.images[index].id,
              width: double.infinity,
              height: 330,
              placeholderIcon: Icons.shopping_bag_outlined,
            ),
          ),
          if (count > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_photo + 1} / $count',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          if (p.soldOut)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45)),
                child: const Center(
                  child: Text(
                    'SOLD OUT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar(MarketplaceProduct p, int total) {
    final soldOut = p.soldOut;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.subtle,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _StepButton(
                    icon: Icons.remove_rounded,
                    onTap: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '$_quantity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add_rounded,
                    onTap: _quantity < 99 ? () => setState(() => _quantity++) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: soldOut
                      ? null
                      : () {
                          final canShop = ref.read(authControllerProvider).valueOrNull?.role ==
                              UserRole.CUSTOMER;
                          if (!canShop) {
                            authMessage(context, 'Shopping is available on customer accounts.');
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => CheckoutScreen(product: p, quantity: _quantity),
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    disabledBackgroundColor: AppColors.coral.withValues(alpha: .35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        soldOut ? 'Sold out' : 'Request purchase',
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      if (!soldOut)
                        Text(
                          formatMoney(total, p.currency),
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          minimumSize: const Size(38, 44),
          disabledForegroundColor: const Color(0xFFC9C4B8),
        ),
      );
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Tag({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.textGrey),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.navy),
            ),
          ],
        ),
      );
}

class _StockTag extends StatelessWidget {
  final MarketplaceProduct product;
  const _StockTag({required this.product});
  @override
  Widget build(BuildContext context) {
    final stock = product.stockCount;
    final (label, color, bg) = product.soldOut
        ? ('Sold out', AppColors.coral, AppColors.coralSoft)
        : stock != null && stock <= 5
            ? ('Only $stock left', const Color(0xFF9A7100), AppColors.goldSoft)
            : ('In stock', AppColors.green, AppColors.greenSoft);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _FulfillmentBadge extends StatelessWidget {
  final String fulfillment;
  const _FulfillmentBadge({required this.fulfillment});
  @override
  Widget build(BuildContext context) {
    final d2f = fulfillment == 'D2F';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: d2f ? AppColors.blueSoft : AppColors.tealSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            d2f ? Icons.warehouse_rounded : Icons.local_shipping_outlined,
            size: 15,
            color: d2f ? AppColors.blue : AppColors.teal,
          ),
          const SizedBox(width: 6),
          Text(
            d2f ? 'D2F fulfils' : 'Seller ships',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: d2f ? AppColors.blue : AppColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  final SellerSummary? seller;
  const _SellerCard({required this.seller});

  @override
  Widget build(BuildContext context) {
    final s = seller;
    if (s == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.blue, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'D2F Direct — sourced and shipped by D2F Global from our warehouse network.',
                style: TextStyle(fontSize: 11.5, height: 1.55, color: Color(0xFF2B3446)),
              ),
            ),
          ],
        ),
      );
    }
    final initials = s.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
        .join();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: AppColors.navy,
            child: Text(
              initials.isEmpty ? 'S' : initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.displayName,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Tooltip(message: 'Verified D2F seller', child: Icon(Icons.verified_rounded, size: 16, color: AppColors.blue)),
                  ],
                ),
                if ((s.headline ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      s.headline!,
                      style: const TextStyle(fontSize: 11, color: AppColors.textGrey, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (s.location.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 12, color: AppColors.textGrey),
                        const SizedBox(width: 3),
                        Text(
                          s.location,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textGrey, fontWeight: FontWeight.w600),
                        ),
                      ],
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

class _DeliveryCard extends StatelessWidget {
  final String fulfillment;
  const _DeliveryCard({required this.fulfillment});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.blueSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.local_shipping_outlined, color: AppColors.blue, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How delivery works',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.blue),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fulfillment == 'D2F'
                        ? 'D2F stores this item in our warehouse. When you order, we pick, pack and ship it by air or sea — then deliver it to you. Delivery is arranged and confirmed by D2F after you place the order.'
                        : 'The seller arranges delivery — choose “D2F arranges” at checkout and we coordinate pickup, shipping and final delivery, or choose “Seller ships” for local handoff. Either way, no payment is taken now.',
                    style: const TextStyle(fontSize: 11, height: 1.6, color: Color(0xFF173F5F)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
