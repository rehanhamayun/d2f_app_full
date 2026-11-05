import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../widgets/country_autocomplete_field.dart';

/// The seller application. D2F reviews every application and agrees the
/// commission rate before the shop goes live.
class SellerApplicationScreen extends StatefulWidget {
  final SellerProfileInfo? existing;
  const SellerApplicationScreen({super.key, this.existing});

  @override
  State<SellerApplicationScreen> createState() => _SellerApplicationScreenState();
}

class _SellerApplicationScreenState extends State<SellerApplicationScreen> {
  static const _countries = [
    'United States', 'Togo', 'Benin', 'Ghana', 'Nigeria', "Côte d'Ivoire",
    'France', 'Belgium', 'United Kingdom', 'Canada', 'Germany', 'Netherlands',
    'Senegal', 'Mali', 'Burkina Faso', 'Guinea', 'Other',
  ];
  static const _categories = [
    'Electronics', 'Fashion', 'Handmade & Crafts', 'Spices & Food',
    'Beauty & Care', 'Home & Living', 'African finds', 'Kids & Baby', 'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _businessName, _category, _city, _phone, _headline, _bio, _address, _otherCountry;
  final TextEditingController _countryController = TextEditingController(text: 'United States');
  final FocusNode _countryFocus = FocusNode();
  String _country = 'United States';
  String _businessType = 'INDIVIDUAL';
  bool _terms = false, _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.displayName ?? '');
    _businessName = TextEditingController(text: e?.businessName ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _city = TextEditingController(text: e?.city ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _headline = TextEditingController(text: e?.headline ?? '');
    _bio = TextEditingController(text: e?.bio ?? '');
    _address = TextEditingController(text: '');
    _otherCountry = TextEditingController();
    if (e != null) {
      _businessType = e.businessType;
      _country = _countries.contains(e.country) ? e.country : 'Other';
      _countryController.text = _country == 'Other' ? '' : _country;
      if (_country == 'Other') _otherCountry.text = e.country;
      _terms = true;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _businessName, _category, _city, _phone, _headline, _bio, _address, _otherCountry, _countryController]) {
      c.dispose();
    }
    _countryFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_terms) {
      _fail('Accept the seller terms so D2F can agree your commission.');
      return;
    }
    final country = _country == 'Other' ? _otherCountry.text.trim() : _country;
    if (country.isEmpty) {
      _fail('Tell us your country.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.I.submitSellerApplication(
        displayName: _name.text,
        businessType: _businessType,
        businessName: _businessType == 'BUSINESS' ? _businessName.text : null,
        headline: _headline.text,
        bio: _bio.text,
        category: _category.text,
        country: country,
        city: _city.text,
        address: _address.text,
        phone: _phone.text,
        terms: _terms,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('The application could not be sent. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showTerms() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seller terms'),
        content: const SingleChildScrollView(
          child: Text(
            'By selling on D2F you agree that:\n\n'
            '1. D2F lists your approved products in the D2F app and markets them to buyers in our service countries.\n\n'
            '2. D2F’s commission is agreed with you before your first sale (typically 8–15%) and is deducted from each completed order. Nothing is billed upfront.\n\n'
            '3. Where fulfilment is arranged through D2F warehouses, you send stock at your cost unless D2F agrees otherwise; D2F stores, picks, packs and ships those orders.\n\n'
            '4. You describe products accurately — condition, materials, origin and quantity. Counterfeit, stolen, restricted or prohibited goods (including undeclared hazardous items) are never allowed.\n\n'
            '5. D2F may remove listings or pause accounts that break these rules, with notice and a reason.\n\n'
            '6. Payment for completed orders is settled on the schedule D2F agrees with you, after the order is completed (and, where applicable, delivered).\n\n'
            '7. You keep buyer and order data confidential and use it only to fulfil orders placed through D2F.',
            style: TextStyle(fontSize: 12, height: 1.65),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: Text(editing ? 'Update application' : 'Become a seller')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            const Text('The basics', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            _TextField(
              controller: _name,
              label: editing ? 'Shop name' : 'Your name or shop name',
              hint: 'e.g. Mama Adjoa Spices',
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name.' : null,
            ),
            const SizedBox(height: 14),
            const Text('I am selling as…', style: AppTheme.caption),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TypeCard(
                    selected: _businessType == 'INDIVIDUAL',
                    icon: Icons.person_rounded,
                    label: 'Individual',
                    onTap: () => setState(() => _businessType = 'INDIVIDUAL'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TypeCard(
                    selected: _businessType == 'BUSINESS',
                    icon: Icons.storefront_rounded,
                    label: 'Business',
                    onTap: () => setState(() => _businessType = 'BUSINESS'),
                  ),
                ),
              ],
            ),
            if (_businessType == 'BUSINESS') ...[
              const SizedBox(height: 12),
              _TextField(
                controller: _businessName,
                label: 'Business name',
                hint: 'Registered business name',
                validator: (v) => _businessType == 'BUSINESS' && (v == null || v.trim().isEmpty)
                    ? 'Enter your business name.'
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            const Text('What do you sell?', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            _TextField(
              controller: _category,
              label: 'Main category',
              hint: 'e.g. Spices & Food',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a category.' : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final suggestion in _categories)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => setState(() => _category.text = suggestion),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Where are you based?', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            CountryAutocompleteField(
              controller: _countryController,
              focusNode: _countryFocus,
              onChanged: (value) => setState(() => _country = value),
              label: 'Country',
              hint: 'e.g. Togo',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Country?' : null,
            ),
            if (_country == 'Other') ...[
              const SizedBox(height: 12),
              _TextField(
                controller: _otherCountry,
                label: 'Your country',
                hint: 'Country name',
              ),
            ],
            const SizedBox(height: 12),
            _TextField(
              controller: _city,
              label: 'City (optional)',
              hint: 'e.g. Lomé',
            ),
            const SizedBox(height: 12),
            _TextField(
              controller: _address,
              label: 'Address (optional)',
              hint: 'Where your stock is held — helps with warehouse intake',
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            const Text('Contact', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            _TextField(
              controller: _phone,
              label: 'Phone (WhatsApp if different)',
              hint: '+228 90 00 00 00',
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 5) ? 'Enter a reachable phone number.' : null,
            ),
            const SizedBox(height: 16),
            const Text('Your story (optional)', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            _TextField(
              controller: _headline,
              label: 'One line about your shop',
              hint: 'e.g. Hand-ground spices from Lomé market',
            ),
            const SizedBox(height: 12),
            _TextField(
              controller: _bio,
              label: 'About you',
              hint: 'What you make, how it’s made, why buyers love it…',
              maxLines: 4,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _terms,
                    onChanged: (value) => setState(() => _terms = value ?? false),
                    activeColor: AppColors.coral,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showTerms,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'I accept the ',
                                style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.navy),
                              ),
                              TextSpan(
                                text: 'D2F seller terms',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: AppColors.coral,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text: ' — including D2F’s commission being agreed with me before my first sale.',
                                style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.navy),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    : Text(
                        editing ? 'Resubmit application' : 'Submit application',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  const _TextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        autocorrect: false,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
        ),
      );
}

class _TypeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TypeCard({required this.selected, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? AppColors.navy : AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: selected ? Colors.white : AppColors.textGrey),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
