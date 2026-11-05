import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

/// "Tell us what you want" — the Buy For Me request form.
class BuyForMeRequestFormScreen extends StatefulWidget {
  const BuyForMeRequestFormScreen({super.key});

  @override
  State<BuyForMeRequestFormScreen> createState() => _BuyForMeRequestFormScreenState();
}

class _BuyForMeRequestFormScreenState extends State<BuyForMeRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _link = TextEditingController();
  final _budget = TextEditingController();
  final _notes = TextEditingController();
  int _quantity = 1;
  String _currency = 'USD';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _budget.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final budget = _budget.text.trim();
    final parsedBudget = budget.isEmpty ? null : double.tryParse(budget);
    final budgetMinor = parsedBudget == null
        ? null
        : (_currency == 'XOF' ? parsedBudget.round() : (parsedBudget * 100).round());
    try {
      await Api.I.createBuyForMeRequest(
        title: _title.text,
        sourceUrl: _link.text,
        quantity: _quantity,
        budgetMinor: budgetMinor,
        currency: _currency,
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('The request could not be sent. Please try again.');
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
      appBar: AppBar(title: const Text('New purchase request')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.coralSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.coral, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Paste a product link or just describe the item — D2F confirms what’s possible and quotes the full price before you commit.',
                      style: TextStyle(fontSize: 11, height: 1.55, color: Color(0xFF5A1F14)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('What do you want?', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().length < 4) ? 'Describe the item (at least a few words).' : null,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'e.g. Sony WH-1000XM5, black, one pair',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            const Text('Product link (optional)', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return null;
                final parsed = Uri.tryParse(value);
                if (parsed == null || !['http', 'https'].contains(parsed.scheme)) {
                  return 'Enter a valid http(s) link.';
                }
                return null;
              },
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'https://www.amazon.com/…',
                prefixIcon: Icon(Icons.link_rounded),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quantity', style: AppTheme.sectionTitle),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            Text(
                              '$_quantity',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                            IconButton(
                              onPressed: _quantity < 1000 ? () => setState(() => _quantity++) : null,
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                      ),
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
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Your budget (optional)', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _budget,
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
            const SizedBox(height: 14),
            const Text('Notes for D2F (optional)', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Colour, size, delivery must arrive before…',
                filled: true,
                fillColor: Colors.white,
              ),
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
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Send request',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Nothing is purchased until you accept D2F’s quote in the app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppColors.textGrey),
            ),
          ],
        ),
      ),
    );
  }
}
