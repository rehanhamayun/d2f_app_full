import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/product_image.dart';
import 'seller_product_form.dart';

/// The seller's own listings: pause/resume, edit, delete.
class SellerProductsTab extends StatefulWidget {
  final Future<void> Function() onChanged;
  const SellerProductsTab({super.key, required this.onChanged});

  @override
  State<SellerProductsTab> createState() => _SellerProductsTabState();
}

class _SellerProductsTabState extends State<SellerProductsTab> {
  List<MarketplaceProduct> _products = const [];
  bool _loading = true, _failed = false;
  final Set<String> _busy = {};

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
      final products = await Api.I.sellerProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
      await widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _toggleActive(MarketplaceProduct product, bool value) async {
    setState(() => _busy.add(product.id));
    try {
      final updated = await Api.I.updateSellerProduct(product.id, isActive: value);
      if (!mounted) return;
      setState(() {
        _products = [
          for (final p in _products)
            if (p.id == product.id) updated.copyWith(isActive: updated.isActive) else p,
        ];
        _busy.remove(product.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy.remove(product.id));
      authMessage(context, 'That change did not save. Please try again.');
    }
  }

  Future<void> _openForm([MarketplaceProduct? product]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => SellerProductFormScreen(product: product)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.coral));
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 34, color: AppColors.textGrey),
            const SizedBox(height: 8),
            const Text('Your listings could not be loaded.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    return Stack(
      children: [
        if (_products.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(color: AppColors.goldSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.storefront_outlined, size: 36, color: Color(0xFF9A7100)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'List your first product',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Photos, price, stock and how D2F delivers it —\nyour shopfront goes live as soon as you save.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
          )
        else
          RefreshIndicator(
            color: AppColors.coral,
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              itemCount: _products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _productCard(_products[index]),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 22,
          child: FloatingActionButton.extended(
            onPressed: () => _openForm(),
            backgroundColor: AppColors.coral,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text(
              'New listing',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _productCard(MarketplaceProduct p) {
    final busy = _busy.contains(p.id);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _openForm(p),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              ProductImage(
                productId: p.id,
                imageId: p.heroImageId,
                width: 74,
                height: 74,
                borderRadius: BorderRadius.circular(14),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (p.featured)
                          const Padding(
                            padding: EdgeInsets.only(right: 5),
                            child: Icon(Icons.auto_awesome_rounded, size: 13, color: AppColors.gold),
                          ),
                        Expanded(
                          child: Text(
                            p.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${p.category} · ${formatMoney(p.priceMinor, p.currency)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _MiniTag(
                          label: p.stockCount == null ? 'Stock untracked' : 'Stock ${p.stockCount}',
                          color: p.soldOut ? AppColors.coral : AppColors.textGrey,
                        ),
                        const SizedBox(width: 6),
                        _MiniTag(label: '${p.ordersCount} ${p.ordersCount == 1 ? 'order' : 'orders'}', color: AppColors.blue),
                        if (p.fulfillment == 'D2F') ...[
                          const SizedBox(width: 6),
                          const Tooltip(
                            message: 'Fulfilled by D2F',
                            child: Icon(Icons.warehouse_rounded, size: 13, color: AppColors.blue),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  busy
                      ? const SizedBox(
                          width: 34,
                          height: 40,
                          child: Center(
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        )
                      : Switch(
                          value: p.isActive,
                          onChanged: (value) => _toggleActive(p, value),
                          activeThumbColor: AppColors.coral,
                        ),
                  Text(
                    p.isActive ? 'Live' : 'Paused',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: p.isActive ? AppColors.green : AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.subtle,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: color),
        ),
      );
}
