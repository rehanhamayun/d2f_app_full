import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../widgets/product_image.dart';
import 'product_detail_screen.dart';

class MarketplaceStorefronts extends StatefulWidget {
  const MarketplaceStorefronts({super.key});

  @override
  State<MarketplaceStorefronts> createState() => _MarketplaceStorefrontsState();
}

class _MarketplaceStorefrontsState extends State<MarketplaceStorefronts> {
  late var _shops = Api.I.marketplaceStorefronts();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local Marketplace storefronts')),
    body: FutureBuilder(
      future: _shops,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return Center(child: OutlinedButton(
          onPressed: () => setState(() => _shops = Api.I.marketplaceStorefronts()), child: const Text('Retry storefronts')));
        }
        final shops = snapshot.data ?? [];
        if (shops.isEmpty) return const Center(child: Text('No storefronts are listed yet.'));
        return ListView(
          children: [
            for (final shop in shops)
              ListTile(
                leading: StorefrontLogo(shop: shop),
                title: Text(shop['displayName'] as String),
                subtitle: Text([shop['city'], shop['country'], shop['category']].whereType<String>().where((value) => value.isNotEmpty).join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MarketplaceStorefront(id: shop['id'] as String))),
              ),
          ],
        );
      },
    ),
  );
}

class StorefrontLogo extends StatefulWidget {
  final Map<String, dynamic> shop;
  const StorefrontLogo({super.key, required this.shop});

  @override
  State<StorefrontLogo> createState() => _StorefrontLogoState();
}

class _StorefrontLogoState extends State<StorefrontLogo> {
  late final Future<Uint8List>? _logo = (widget.shop['profilePictureName'] as String? ?? '').isEmpty
      ? null : Api.I.marketplaceStorefrontLogo(widget.shop['id'] as String);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _logo,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      return CircleAvatar(
        backgroundColor: AppColors.goldSoft,
        child: bytes == null
            ? const Icon(Icons.storefront_outlined)
            : ClipOval(child: Image.memory(bytes, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.storefront_outlined))),
      );
    },
  );
}

class MarketplaceStorefront extends StatefulWidget {
  final String id;
  const MarketplaceStorefront({super.key, required this.id});

  @override
  State<MarketplaceStorefront> createState() => _MarketplaceStorefrontState();
}

class _MarketplaceStorefrontState extends State<MarketplaceStorefront> {
  late var _shop = Api.I.marketplaceStorefront(widget.id);

  Future<void> _openWhatsApp(String number) async {
    final uri = Uri.https('wa.me', number.replaceAll('+', ''));
    if (await launchUrl(uri, mode: LaunchMode.externalApplication) || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Marketplace storefront')),
    body: FutureBuilder(
      future: _shop,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return Center(child: OutlinedButton(
          onPressed: () => setState(() => _shop = Api.I.marketplaceStorefront(widget.id)), child: const Text('Retry storefront')));
        }
        final shop = snapshot.data!;
        final products = (shop['products'] as List).cast<Map<String, dynamic>>().map(MarketplaceProduct.fromJson);
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            ListTile(leading: StorefrontLogo(shop: shop), title: Text(shop['displayName'] as String, style: AppTheme.sectionTitle),
              subtitle: Text([shop['city'], shop['country'], shop['category']].whereType<String>().where((value) => value.isNotEmpty).join(' · ')),
              trailing: const Tooltip(message: 'Approved D2F seller', child: Icon(Icons.verified_outlined))),
            for (final field in ['businessName', 'headline', 'bio'])
              if ((shop[field] as String? ?? '').isNotEmpty) Text(shop[field] as String),
            if (shop['localDeliveryEnabled'] == true) const Text('D2F local delivery available at eligible addresses.'),
            if ((shop['whatsappNumber'] as String? ?? '').isNotEmpty)
              OutlinedButton.icon(onPressed: () => _openWhatsApp(shop['whatsappNumber'] as String), icon: const Icon(Icons.chat_outlined), label: const Text('Contact on WhatsApp')),
            const SizedBox(height: 12),
            const Text('Products', style: AppTheme.sectionTitle),
            if (products.isEmpty) const Text('No products are listed yet.'),
            for (final product in products)
              ListTile(
                leading: ProductImage(productId: product.id, imageId: product.images.firstOrNull?.id, width: 54, height: 54, borderRadius: BorderRadius.circular(8)),
                title: Text(product.title),
                subtitle: Text(formatMoney(product.priceMinor, product.currency)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product.id))),
              ),
          ],
        );
      },
    ),
  );
}
