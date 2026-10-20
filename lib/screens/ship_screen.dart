import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'parcel_success_screen.dart';

/// "Register New Parcel" (design screen 5). Shown as the Ship tab.
class ShipScreen extends StatefulWidget {
  final ShippingMethod? initialMethod;

  const ShipScreen({super.key, this.initialMethod});

  @override
  State<ShipScreen> createState() => ShipScreenState();
}

class ShipScreenState extends State<ShipScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientAddress = TextEditingController();
  final _weight = TextEditingController();
  final _notes = TextEditingController();

  List<Customer> _customers = [];
  Customer? _customer;
  bool _customersLoading = true;
  String? _customersError;

  String? _origin;
  String? _destination;
  ShippingMethod _method = ShippingMethod.AIR;
  String? _packageType;

  bool _saving = false;
  // Reused across retries until the parcel is registered or the form resets,
  // so a second tap / network retry cannot create a duplicate.
  String? _clientRequestId;

  @override
  void initState() {
    super.initState();
    _method = widget.initialMethod ?? ShippingMethod.AIR;
    _origin = kOriginOptions.first;
    _loadCustomers();
  }

  @override
  void dispose() {
    _recipientName.dispose();
    _recipientPhone.dispose();
    _recipientAddress.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Public so the Home screen's method cards can jump straight here with
  /// a preselected shipping method.
  void presetMethod(ShippingMethod method) => setState(() => _method = method);

  Future<void> _loadCustomers() async {
    setState(() {
      _customersLoading = true;
      _customersError = null;
    });
    try {
      final list = await Api.I.customers();
      if (!mounted) return;
      setState(() {
        _customers = list;
        _customersLoading = false;
        if (_customer != null) {
          // keep selection valid after refresh
          Customer? updated;
          for (final c in list) {
            if (c.id == _customer!.id) {
              updated = c;
              break;
            }
          }
          if (updated != null) _customer = updated;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _customersError = e.message;
        _customersLoading = false;
      });
    }
  }

  Future<void> _addCustomerDialog() async {
    final created = await showDialog<Customer>(
      context: context,
      builder: (ctx) => const _AddCustomerDialog(),
    );
    if (created == null) return;
    await _loadCustomers();
    if (!mounted) return;
    setState(() {
      // The refreshed dropdown owns fresh Customer instances. Select that exact
      // entry so creating a customer immediately associates it with this parcel.
      _customer = _customers.firstWhere(
        (c) => c.id == created.id,
        orElse: () => created,
      );
      if (!_customers.any((c) => c.id == created.id)) _customers.add(created);
    });
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (_customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer or add a new one.')),
      );
      return;
    }
    if (_destination == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a destination.')));
      return;
    }
    if (_packageType == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a package type.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final clientRequestId = _clientRequestId ??=
          '${DateTime.now().millisecondsSinceEpoch}-${_recipientName.text.hashCode.abs()}';
      final parcel = await Api.I.createParcel(
        customerId: _customer!.id,
        recipientName: _recipientName.text.trim(),
        recipientPhone: _recipientPhone.text.trim(),
        recipientAddress: _recipientAddress.text.trim(),
        packageType: _packageType!,
        weightKg: double.parse(_weight.text.trim()),
        origin: _origin!,
        destination: _destination!,
        method: _method.name,
        notes: _notes.text.trim(),
        clientRequestId: clientRequestId,
      );
      if (!mounted) return;
      await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => ParcelSuccessScreen(parcel: parcel)),
      );
      // Returning from the success screen (either action) gives a clean form.
      if (mounted) resetForm();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Called when returning from the success screen via "Register Another".
  void resetForm() {
    _recipientName.clear();
    _recipientPhone.clear();
    _recipientAddress.clear();
    _weight.clear();
    _notes.clear();
    setState(() {
      _customer = null;
      _destination = null;
      _packageType = null;
      _method = ShippingMethod.AIR;
      _origin = kOriginOptions.first;
      _clientRequestId = null; // fresh key for the next parcel
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // App bar row (tab variant, centered title)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: const D2FHomeHeader(),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  const ScreenIntro(
                    title: 'Send\nwith ease.',
                    subtitle: 'Tell us about your parcel.\nWe’ll take care of the rest.',
                    art: 'parcel',
                  ),
                  const SizedBox(height: 22),

                  // ── Customer Information ──────────────────────────────
                  SectionCard(
                    dark: true,
                    tint: AppColors.deepPurple,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          icon: Icons.groups_rounded,
                          tint: AppColors.coralSoft,
                          iconColor: AppColors.coral,
                          title: 'Customer Information',
                          subtitle:
                              'Select an existing customer or add a new one.',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _customersLoading
                                  ? const LinearProgressIndicator(
                                      minHeight: 3,
                                      color: AppColors.gold,
                                    )
                                  : DropdownButtonFormField<Customer>(
                                      key: ValueKey(
                                        'customer-${_customer?.id ?? 'none'}',
                                      ),
                                      isExpanded: true,
                                      initialValue: _customer,
                                      items: [
                                        for (final c in _customers)
                                          DropdownMenuItem(
                                            value: c,
                                            child: Text(
                                              c.displayName,
                                              style: AppTheme.body,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (c) =>
                                          setState(() => _customer = c),
                                      decoration: const InputDecoration(
                                        hintText: 'Choose a customer',
                                        prefixIcon: Icon(
                                          Icons.person_outline_rounded,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _addCustomerDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.coralSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_add_alt_rounded,
                                      color: AppColors.coral,
                                      size: 20,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Add',
                                      style: TextStyle(
                                        color: AppColors.coral,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_customersError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Could not load customers: $_customersError',
                            style: const TextStyle(
                              color: AppColors.coral,
                              fontSize: 12.5,
                            ),
                          ),
                          TextButton(
                            onPressed: _loadCustomers,
                            child: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Recipient Information ─────────────────────────────
                  SectionCard(
                    dark: true,
                    tint: AppColors.deepBlue,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          icon: Icons.person_outline_rounded,
                          tint: AppColors.blueSoft,
                          iconColor: AppColors.blue,
                          title: 'Recipient Information',
                          subtitle: 'Where should we send this parcel?',
                        ),
                        const SizedBox(height: 12),
                        FormFieldPair(
                          first: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recipient Name',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _recipientName,
                                decoration: const InputDecoration(
                                  hintText: 'Enter recipient name',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ],
                          ),
                          second: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Phone Number',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _recipientPhone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  hintText: 'Enter phone',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Address',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _recipientAddress,
                          decoration: const InputDecoration(
                            hintText: 'Enter full address',
                            prefixIcon: Icon(Icons.place_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Shipment Details ─────────────────────────────────
                  SectionCard(
                    dark: true,
                    tint: AppColors.deepTeal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          icon: Icons.inventory_2_rounded,
                          tint: AppColors.goldSoft,
                          iconColor: AppColors.gold,
                          title: 'Shipment Details',
                          subtitle: 'Tell us about the parcel.',
                        ),
                        const SizedBox(height: 12),
                        FormFieldPair(
                          first: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Origin',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _origin,
                                items: [
                                  for (final o in kOriginOptions)
                                    DropdownMenuItem(
                                      value: o,
                                      child: Text(
                                        o,
                                        style: AppTheme.body,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _origin = v),
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.place_rounded),
                                ),
                              ),
                            ],
                          ),
                          second: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Destination',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _destination,
                                items: [
                                  for (final d in kDestinationOptions)
                                    DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d,
                                        style: AppTheme.body,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _destination = v),
                                decoration: const InputDecoration(
                                  hintText: 'Select destination',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                                validator: (v) => v == null ? 'Required' : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Shipping Method',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final m in ShippingMethod.values) ...[
                              Expanded(
                                child: _MethodRadio(
                                  method: m,
                                  selected: _method == m,
                                  onSelect: () => setState(() => _method = m),
                                ),
                              ),
                              if (m != ShippingMethod.ROAD)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Package Type',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _packageType,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'BOX',
                                        child: Text(
                                          'Box',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'BARREL',
                                        child: Text(
                                          'Barrel',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'TV',
                                        child: Text(
                                          'TV / Electronics',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'APPLIANCE',
                                        child: Text(
                                          'Appliance',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'FURNITURE',
                                        child: Text(
                                          'Furniture',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'PALLET',
                                        child: Text(
                                          'Pallet',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'VEHICLE',
                                        child: Text(
                                          'Vehicle',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'DOCUMENTS',
                                        child: Text(
                                          'Documents',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'OTHER',
                                        child: Text(
                                          'Other',
                                          style: AppTheme.body,
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _packageType = v),
                                    decoration: const InputDecoration(
                                      hintText: 'Select package type',
                                      prefixIcon: Icon(Icons.category_outlined),
                                    ),
                                    validator: (v) =>
                                        v == null ? 'Required' : null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Weight (kg)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _weight,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter weight',
                                      suffixText: 'kg',
                                      prefixIcon: Icon(Icons.scale_rounded),
                                    ),
                                    validator: (v) {
                                      final w = double.tryParse(
                                        v?.trim() ?? '',
                                      );
                                      if (w == null || w <= 0) {
                                        return 'Enter a valid weight';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text.rich(
                          TextSpan(
                            text: 'Description / Notes ',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            children: const [
                              TextSpan(
                                text: '(Optional)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _notes,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText:
                                'E.g. contents, special instructions, etc.',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 22),

                        PrimaryButton(
                          label: 'Save Parcel',
                          loading: _saving,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.sectionTitle.copyWith(
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
              Text(
                subtitle,
                style: AppTheme.caption.copyWith(
                  fontSize: 11,
                  height: 1.4,
                  color: const Color(0xFFBFD0E4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MethodRadio extends StatelessWidget {
  final ShippingMethod method;
  final bool selected;
  final VoidCallback onSelect;

  const _MethodRadio({
    required this.method,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (method) {
      ShippingMethod.AIR => (AppColors.coralSoft, AppColors.coral),
      ShippingMethod.SEA => (AppColors.blueSoft, AppColors.blue),
      ShippingMethod.ROAD => (AppColors.goldSoft, Color(0xFF9A7100)),
    };
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? fg : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(method.icon, color: fg, size: 17),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    method.label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: fg,
                  size: 14,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              method.tagline,
              style: const TextStyle(color: AppColors.textGrey, fontSize: 10.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog();

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Customer name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await Api.I.createCustomer(
        displayName: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        city: _city.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, c);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Add New Customer', style: AppTheme.sectionTitle),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  hintText: 'Full name *',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email (optional)',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _city,
                decoration: const InputDecoration(
                  hintText: 'City (optional)',
                  prefixIcon: Icon(Icons.location_city_rounded),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.coral,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.coral,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }
}
