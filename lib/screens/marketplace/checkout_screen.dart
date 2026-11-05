import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/country_autocomplete_field.dart';
import '../../widgets/product_image.dart';
import 'marketplace_orders_screen.dart';

/// Marketplace checkout: quantity, delivery preference and delivery details.
/// No payment is collected — D2F or the seller confirms availability and the
/// agreed terms after the order request lands.
class CheckoutScreen extends ConsumerStatefulWidget {
  final MarketplaceProduct product;
  final int quantity;
  const CheckoutScreen({super.key, required this.product, required this.quantity});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _Delivery { d2f, seller }

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  late int _quantity;
  _Delivery _delivery = _Delivery.d2f;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  MarketplaceOrder? _placed;

  @override
  void initState() {
    super.initState();
    _quantity = widget.quantity;
    final user = ref.read(authControllerProvider).valueOrNull;
    _name.text = user?.fullName ?? '';
    _phone.text = user?.phone ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _country.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _total => widget.product.priceMinor * _quantity;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final order = await Api.I.createMarketplaceOrder(
        productId: widget.product.id,
        quantity: _quantity,
        deliveryPreference: _delivery == _Delivery.d2f ? 'D2F' : 'SELLER',
        recipientName: _name.text,
        recipientPhone: _phone.text,
        deliveryAddress: _address.text,
        deliveryCity: _city.text,
        deliveryCountry: _country.text,
        notes: _note.text,
      );
      if (!mounted) return;
      setState(() {
        _placed = order;
        _busy = false;
      });
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('Something went wrong. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final placed = _placed;
    if (placed != null) return _SuccessView(order: placed);
    final p = widget.product;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text('Complete your order')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _orderSummary(p),
            const SizedBox(height: 18),
            const Text('Delivery preference', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            _DeliveryOption(
              selected: _delivery == _Delivery.d2f,
              icon: Icons.flight_takeoff_rounded,
              tint: AppColors.blueSoft,
              color: AppColors.blue,
              title: 'D2F arranges delivery',
              subtitle: 'We collect, ship by air or sea and deliver to your door. Best for international orders.',
              onTap: () => setState(() => _delivery = _Delivery.d2f),
            ),
            const SizedBox(height: 10),
            _DeliveryOption(
              selected: _delivery == _Delivery.seller,
              icon: Icons.local_shipping_outlined,
              tint: AppColors.tealSoft,
              color: AppColors.teal,
              title: 'Seller ships',
              subtitle: 'The seller arranges delivery directly — often fastest for local orders.',
              onTap: () => setState(() => _delivery = _Delivery.seller),
            ),
            const SizedBox(height: 18),
            const Text('Who receives it?', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            _field(
              controller: _name,
              label: 'Full name',
              hint: 'Recipient’s name',
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name.' : null,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _phone,
              label: 'Phone',
              hint: '+1 555 000 0000',
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 5) ? 'Enter a reachable phone number.' : null,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _address,
              label: 'Delivery address',
              hint: 'Street, house number, abbey, landmark…',
              maxLines: 2,
              validator: (v) => (v == null || v.trim().length < 5) ? 'Enter the full delivery address.' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    controller: _city,
                    label: 'City',
                    hint: 'Omaha',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'City?' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CountryAutocompleteField(
                    controller: _country,
                    label: 'Country',
                    hint: 'Togo',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Country?' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              controller: _note,
              label: 'Note for the seller (optional)',
              hint: 'Colour, size, delivery instructions…',
              maxLines: 3,
            ),
            const SizedBox(height: 18),
            _priceSummary(p),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Submit order request',
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                          SizedBox(width: 10),
                          Icon(Icons.arrow_forward_rounded, color: Colors.white),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No payment is taken now. The seller (or D2F) confirms availability, and D2F arranges delivery and the agreed payment terms with you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, height: 1.6, color: AppColors.textGrey),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _orderSummary(MarketplaceProduct p) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ProductImage(
              productId: p.id,
              imageId: p.heroImageId,
              width: 86,
              height: 86,
              borderRadius: BorderRadius.circular(16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.category.toUpperCase(),
                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textGrey),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.navy),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(p.priceMinor, p.currency),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.coral),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.subtle,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 18),
                    onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  ),
                  Text('$_quantity', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    onPressed: _quantity < 99 ? () => setState(() => _quantity++) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _priceSummary(MarketplaceProduct p) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _priceLine('Items (×$_quantity)', formatMoney(_total, p.currency)),
            const SizedBox(height: 8),
            _priceLine('Delivery', 'Arranged after confirmation', muted: true),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(color: Color(0xFF2A3A5E), height: 1),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Due today',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                const Text(
                  'Nothing — no payment now',
                  style: TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _priceLine(String label, String value, {bool muted = false}) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: muted ? const Color(0xFFB9C3DE) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: muted ? const Color(0xFFB9C3DE) : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
        ),
      );
}

class _DeliveryOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color tint, color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _DeliveryOption({
    required this.selected,
    required this.icon,
    required this.tint,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.navy : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 10, height: 1.5, color: AppColors.textGrey),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.navy : const Color(0xFFC9C4B8),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      );
}

class _SuccessView extends StatelessWidget {
  final MarketplaceOrder order;
  const _SuccessView({required this.order});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(26),
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppColors.greenSoft,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.green.withValues(alpha: .22),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.check_rounded, size: 52, color: AppColors.green),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Order requested!',
                      style: AppTheme.display,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your order reference is',
                      style: AppTheme.caption,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.reference,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        color: AppColors.coral,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _nextStep(1, 'Seller confirms', 'The seller (or D2F) checks availability and reaches out to confirm delivery details.'),
                    _nextStep(2, 'Delivery is arranged', 'D2F coordinates pickup, shipping and final delivery — or the seller ships locally.'),
                    _nextStep(3, 'Agree payment terms', 'You pay the seller or D2F on the agreed terms. Nothing is charged now.'),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(builder: (_) => const MarketplaceOrdersScreen()),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.coral,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                        ),
                        child: const Text(
                          'Track my order',
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                      child: const Text('Continue shopping'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _nextStep(int number, String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(fontSize: 11, height: 1.55, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
