import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

/// Register a purchase you made yourself — D2F receives it at our warehouse
/// and forwards it to you. Separate from Buy For Me where D2F buys for you.
class ShipForMeRequestFormScreen extends StatefulWidget {
  const ShipForMeRequestFormScreen({super.key});

  @override
  State<ShipForMeRequestFormScreen> createState() => _ShipForMeRequestFormScreenState();
}

class _ShipForMeRequestFormScreenState extends State<ShipForMeRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _retailer = TextEditingController();
  final _orderId = TextEditingController();
  final _trackingId = TextEditingController();
  final _description = TextEditingController();
  final _declaredValue = TextEditingController();
  String _currency = 'USD';
  bool _busy = false;

  @override
  void dispose() {
    _retailer.dispose();
    _orderId.dispose();
    _trackingId.dispose();
    _description.dispose();
    _declaredValue.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final parsedValue = _declaredValue.text.trim().isEmpty
          ? null
          : double.tryParse(_declaredValue.text.trim());
      final valueMinor = parsedValue == null
          ? null
          : (_currency == 'XOF' ? parsedValue.round() : (parsedValue * 100).round());
      await Api.I.createShipForMeRequest(
        retailerName: _retailer.text,
        itemDescription: _description.text,
        retailerOrderId: _orderId.text.trim().isEmpty ? null : _orderId.text,
        retailerTrackingId: _trackingId.text.trim().isEmpty ? null : _trackingId.text,
        declaredValueMinor: valueMinor,
        declaredCurrency: _currency,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('The request could not be sent. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text('Register your purchase')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.blueSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.blue, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tell us what you bought and where it’s shipping from. We’ll receive it at your D2F warehouse address and forward it to you.',
                      style: TextStyle(fontSize: 11, height: 1.55, color: Color(0xFF1B3A5C)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Retailer', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _retailer,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the store name (e.g. Amazon, Walmart, eBay).' : null,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: 'e.g. Amazon', filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 14),
            const Text('Your order number (optional)', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _orderId,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: 'Order #123-4567890', filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 14),
            const Text('Retailer tracking number (optional)', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _trackingId,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: '1Z999AA1234567890', filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 14),
            const Text('What did you buy?', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().length < 4) ? 'Describe the item (at least a few words).' : null,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: 'e.g. Nike Air Max, size 10, black', filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Declared value (optional)', style: AppTheme.sectionTitle),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _declaredValue,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return null;
                          final parsed = double.tryParse(value);
                          if (parsed == null || parsed < 0) return 'Enter a valid amount.';
                          return null;
                        },
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          prefixText: _currency == 'XOF' ? 'CFA ' : (_currency == 'EUR' ? '€ ' : '\$ '),
                          hintText: _currency == 'XOF' ? '50 000' : '300.00',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('For customs declaration', style: const TextStyle(fontSize: 9.5, color: AppColors.textGrey)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Currency', style: AppTheme.sectionTitle),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _currency,
                        items: const [
                          DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                          DropdownMenuItem(value: 'XOF', child: Text('XOF (CFA)')),
                        ],
                        onChanged: (value) => setState(() => _currency = value ?? 'USD'),
                        decoration: const InputDecoration(filled: true, fillColor: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
                child: _busy
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('Register purchase', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Your item will ship to your D2F warehouse address first.', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: AppColors.textGrey)),
          ],
        ),
      ),
    );
  }
}
