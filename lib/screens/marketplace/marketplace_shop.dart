import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/product_image.dart';
import 'marketplace_orders_screen.dart';
import 'product_detail_screen.dart';
import 'seller_studio_screen.dart';

/// The D2F Marketplace storefront: search, category and location browsing,
/// featured listings and the product grid. Rendered inside the customer
/// workspace (embedded) and as a full screen.
class MarketplaceShop extends ConsumerStatefulWidget {
  const MarketplaceShop({super.key});
  @override
  ConsumerState<MarketplaceShop> createState() => _MarketplaceShopState();
}

class _MarketplaceShopState extends ConsumerState<MarketplaceShop> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _category;
  String? _country;
  bool _canAct = false;

  final List<MarketplaceProduct> _products = [];
  List<CategoryCount> _categories = const [];
  List<CategoryCount> _countries = const [];
  int _page = 1, _total = 0;
  bool _loading = true, _loadingMore = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
      _page = 1;
    });
    try {
      final browse = await Api.I.marketplaceProducts(
        q: _query,
        category: _category,
        country: _country,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(browse.products);
        _total = browse.total;
        _categories = browse.categories;
        _countries = browse.countries;
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

  Future<void> _loadMore() async {
    if (_loadingMore || _products.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final browse = await Api.I.marketplaceProducts(
        q: _query,
        category: _category,
        country: _country,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _page = browse.page;
        _products.addAll(browse.products);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      if (_query == value.trim()) return;
      setState(() => _query = value.trim());
      _reload();
    });
  }

  void _setCategory(String? category) {
    setState(() => _category = _category == category ? null : category);
    _reload();
  }

  void _setCountry(String? country) {
    setState(() => _country = _country == country ? null : country);
    _reload();
  }

  bool get _browsing => _query.isNotEmpty || _category != null || _country != null;

  void _gated(VoidCallback action) {
    if (_canAct) {
      action();
    } else {
      authMessage(context, 'Shopping and selling are available on customer accounts.');
    }
  }

  @override
  Widget build(BuildContext context) {
    _canAct = ref.watch(authControllerProvider).valueOrNull?.role == UserRole.CUSTOMER;
    return RefreshIndicator(
      color: AppColors.coral,
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _hero()),
          SliverToBoxAdapter(child: _actionRow()),
          SliverToBoxAdapter(child: _searchBar()),
          SliverToBoxAdapter(child: _categoryRow()),
          if (_countries.isNotEmpty) SliverToBoxAdapter(child: _countryRow()),
          if (!_browsing && !_loading && _products.any((p) => p.featured))
            SliverToBoxAdapter(child: _featuredStrip()),
          SliverToBoxAdapter(child: _gridHeader()),
          if (_loading)
            const SliverFillRemaining(hasScrollBody: false, child: _LoadingGrid())
          else if (_failed)
            SliverFillRemaining(hasScrollBody: false, child: _ErrorState(onRetry: _reload))
          else if (_products.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                browsing: _browsing,
                onReset: _resetFilters,
                onSell: () => _gated(() => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const SellerStudioScreen()),
                    )),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: .66,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ProductCard(product: _products[index]),
                  childCount: _products.length,
                ),
              ),
            ),
          if (!_loading && !_failed && _products.length < _total)
            SliverToBoxAdapter(child: _loadMoreButton()),
          SliverToBoxAdapter(child: _sellerBanner()),
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ],
      ),
    );
  }

  void _resetFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _category = null;
      _country = null;
    });
    _reload();
  }

  // ── Pieces ───────────────────────────────────────────────────────────────

  Widget _hero() => Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 1.92,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/services_marketplace.jpg',
                  fit: BoxFit.cover,
                  alignment: const Alignment(.42, .18),
                  excludeFromSemantics: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF3A1D05).withValues(alpha: .92),
                        const Color(0xFF6B3B10).withValues(alpha: .55),
                        Colors.transparent,
                      ],
                      stops: const [0, .52, 1],
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
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'D2F MARKETPLACE',
                            style: TextStyle(
                              color: Color(0xFF3A2503),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Local treasures.\nGlobal favourites.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25.5,
                            height: 1.16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.7,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Shop verified sellers in the USA and Africa.\nD2F arranges delivery to your door.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
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
        ),
      );

  Widget _actionRow() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.receipt_long_rounded,
                label: 'My orders',
                tint: AppColors.blueSoft,
                color: AppColors.blue,
                onTap: () => _gated(() => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const MarketplaceOrdersScreen()),
                    )),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionTile(
                icon: Icons.storefront_rounded,
                label: 'Sell on D2F',
                tint: AppColors.goldSoft,
                color: const Color(0xFF9A7100),
                onTap: () => _gated(() => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const SellerStudioScreen()),
                    )),
              ),
            ),
          ],
        ),
      );

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _search,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search the marketplace',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _resetFilters,
                  ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      );

  Widget _categoryRow() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _FilterChip(
              label: 'All',
              selected: _category == null,
              onTap: () => _setCategory(null),
            );
          }
          final category = _categories[index - 1];
          return _FilterChip(
            label: category.name,
            selected: _category == category.name,
            onTap: () => _setCategory(category.name),
          );
        },
      ),
    );
  }

  Widget _countryRow() => SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(top: 6),
          itemCount: _countries.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _FilterChip(
                icon: Icons.public_rounded,
                label: 'All locations',
                selected: _country == null,
                compact: true,
                onTap: () => _setCountry(null),
              );
            }
            final country = _countries[index - 1];
            return _FilterChip(
              icon: Icons.place_rounded,
              label: country.name,
              selected: _country == country.name,
              compact: true,
              onTap: () => _setCountry(country.name),
            );
          },
        ),
      );

  Widget _featuredStrip() {
    final featured = _products.where((p) => p.featured).take(6).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 2, 2, 10),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 17, color: AppColors.gold),
                SizedBox(width: 6),
                Text(
                  'Featured this week',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.3),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: featured.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _FeaturedCard(product: featured[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridHeader() {
    final label = _query.isNotEmpty
        ? 'Results for “$_query”'
        : _category ?? (_country != null ? 'From $_country' : 'New & noteworthy');
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.35),
            ),
          ),
          if (!_loading && _total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.chipGrey,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '$_total ${_total == 1 ? 'item' : 'items'}',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textGrey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _loadMoreButton() => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
        child: OutlinedButton(
          onPressed: _loadingMore ? null : _loadMore,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: const BorderSide(color: AppColors.border),
          ),
          child: _loadingMore
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Show more', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      );

  Widget _sellerBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
        child: Material(
          color: const Color(0xFF1E2A47),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _gated(() => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const SellerStudioScreen()),
                )),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Color(0xFF3A2503)),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Turn what you make into a global storefront',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.2,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Sell to buyers in the USA and Africa. D2F stores, picks and ships for you.',
                          style: TextStyle(
                            color: Color(0xFFB9C3DE),
                            fontSize: 10.5,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint, color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textGrey, size: 20),
              ],
            ),
          ),
        ),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool compact;
  final IconData? icon;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 15, vertical: compact ? 7 : 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: selected ? AppColors.navy : AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: selected ? Colors.white : AppColors.textGrey),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  final MarketplaceProduct product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => ProductDetailScreen(productId: p.id)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    productId: p.id,
                    imageId: p.heroImageId,
                    borderRadius: BorderRadius.zero,
                  ),
                  if (p.featured)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 11, color: Color(0xFF3A2503)),
                            SizedBox(width: 4),
                            Text(
                              'FEATURED',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .8,
                                color: Color(0xFF3A2503),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (p.soldOut)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .42),
                        ),
                        child: const Center(
                          child: Text(
                            'SOLD OUT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.category,
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.textGrey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatMoney(p.priceMinor, p.currency),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                            letterSpacing: -.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (p.fulfillment == 'D2F')
                        const Tooltip(
                          message: 'Fulfilled by D2F',
                          child: Icon(Icons.warehouse_rounded, size: 15, color: AppColors.blue),
                        ),
                    ],
                  ),
                  if (p.seller != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_rounded, size: 10.5, color: AppColors.textGrey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [p.seller!.displayName, p.seller!.country]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' · '),
                              style: const TextStyle(fontSize: 9.5, color: AppColors.textGrey, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final MarketplaceProduct product;
  const _FeaturedCard({required this.product});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => ProductDetailScreen(productId: product.id)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: SizedBox(
            width: 228,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProductImage(productId: product.id, imageId: product.heroImageId),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: .72)],
                      stops: const [.42, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.category.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(product.priceMinor, product.currency),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
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

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: AppColors.coral),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: AppColors.chipGrey,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 34, color: AppColors.textGrey),
              ),
              const SizedBox(height: 16),
              const Text(
                'We couldn’t load the marketplace',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              const Text(
                'Check your connection and try again.',
                style: AppTheme.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  minimumSize: const Size(160, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final bool browsing;
  final VoidCallback onReset;
  final VoidCallback onSell;
  const _EmptyState({required this.browsing, required this.onReset, required this.onSell});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: const BoxDecoration(
                  color: AppColors.goldSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_rounded, size: 38, color: Color(0xFF9A7100)),
              ),
              const SizedBox(height: 16),
              Text(
                browsing ? 'Nothing matches that yet' : 'The shelves are filling up…',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                browsing
                    ? 'Try a different search, category or location.'
                    : 'Approved sellers list here soon. Be the first —\nopen your own D2F storefront.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey),
              ),
              const SizedBox(height: 16),
              if (browsing)
                TextButton(
                  onPressed: onReset,
                  child: const Text('Clear search & filters'),
                )
              else
                FilledButton.icon(
                  onPressed: onSell,
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Sell on D2F'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    minimumSize: const Size(180, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
            ],
          ),
        ),
      );
}
