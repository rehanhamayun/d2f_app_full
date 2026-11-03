import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool isUsRoute(String? place) => RegExp(
  r'\b(USA|US|United States)\b',
  caseSensitive: false,
).hasMatch(place ?? '');
const usStates = <String, String>{
  'AL': 'Alabama',
  'AK': 'Alaska',
  'AZ': 'Arizona',
  'AR': 'Arkansas',
  'CA': 'California',
  'CO': 'Colorado',
  'CT': 'Connecticut',
  'DE': 'Delaware',
  'DC': 'District of Columbia',
  'FL': 'Florida',
  'GA': 'Georgia',
  'HI': 'Hawaii',
  'ID': 'Idaho',
  'IL': 'Illinois',
  'IN': 'Indiana',
  'IA': 'Iowa',
  'KS': 'Kansas',
  'KY': 'Kentucky',
  'LA': 'Louisiana',
  'ME': 'Maine',
  'MD': 'Maryland',
  'MA': 'Massachusetts',
  'MI': 'Michigan',
  'MN': 'Minnesota',
  'MS': 'Mississippi',
  'MO': 'Missouri',
  'MT': 'Montana',
  'NE': 'Nebraska',
  'NV': 'Nevada',
  'NH': 'New Hampshire',
  'NJ': 'New Jersey',
  'NM': 'New Mexico',
  'NY': 'New York',
  'NC': 'North Carolina',
  'ND': 'North Dakota',
  'OH': 'Ohio',
  'OK': 'Oklahoma',
  'OR': 'Oregon',
  'PA': 'Pennsylvania',
  'RI': 'Rhode Island',
  'SC': 'South Carolina',
  'SD': 'South Dakota',
  'TN': 'Tennessee',
  'TX': 'Texas',
  'UT': 'Utah',
  'VT': 'Vermont',
  'VA': 'Virginia',
  'WA': 'Washington',
  'WV': 'West Virginia',
  'WI': 'Wisconsin',
  'WY': 'Wyoming',
  'AS': 'American Samoa',
  'GU': 'Guam',
  'MP': 'Northern Mariana Islands',
  'PR': 'Puerto Rico',
  'VI': 'US Virgin Islands',
};

/// Retains the formatted address in the existing API string; incomplete US
/// fields never emit an apparently complete address. No geocoding is claimed.
class StructuredAddressField extends StatefulWidget {
  final TextEditingController controller;
  final TextEditingController? nameController, phoneController;
  final String label;
  final bool isUs, requiredField, includeContact;
  final VoidCallback? onChanged;
  const StructuredAddressField({
    super.key,
    required this.controller,
    required this.label,
    required this.isUs,
    this.nameController,
    this.phoneController,
    this.onChanged,
    this.requiredField = true,
    this.includeContact = false,
  });
  @override
  State<StructuredAddressField> createState() => _StructuredAddressFieldState();
}

class _StructuredAddressFieldState extends State<StructuredAddressField> {
  final _street = TextEditingController(),
      _unit = TextEditingController(),
      _city = TextEditingController(),
      _zip = TextEditingController();
  final _first = TextEditingController(),
      _last = TextEditingController(),
      _phone = TextEditingController();
  String? _state;
  bool _legacy = false, _writing = false;
  @override
  void initState() {
    super.initState();
    _legacy = widget.isUs && widget.controller.text.trim().isNotEmpty;
    final names =
        widget.nameController?.text.trim().split(RegExp(r'\s+')) ?? [];
    if (names.isNotEmpty) {
      _first.text = names.first;
      _last.text = names.skip(1).join(' ');
    }
    _phone.text = widget.phoneController?.text ?? '';
    widget.controller.addListener(_externalChange);
  }

  void _externalChange() {
    if (!_writing && widget.controller.text.isEmpty) {
      for (final c in [_street, _unit, _city, _zip]) {
        c.clear();
      }
      if (mounted) {
        setState(() {
          _state = null;
          _legacy = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant StructuredAddressField old) {
    super.didUpdateWidget(old);
    if (old.isUs != widget.isUs) {
      _writing = true;
      widget.controller.clear();
      _writing = false;
      _legacy = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged?.call();
      });
    }
  }

  String? _required(String? v) =>
      widget.requiredField && (v?.trim().isEmpty ?? true) ? 'Required' : null;
  bool get _contact =>
      widget.includeContact ||
      widget.nameController != null ||
      widget.phoneController != null;
  bool get _valid =>
      _street.text.trim().isNotEmpty &&
      _city.text.trim().isNotEmpty &&
      _state != null &&
      RegExp(r'^\d{5}(-\d{4})?$').hasMatch(_zip.text.trim()) &&
      (!_contact ||
          (_first.text.trim().isNotEmpty && _last.text.trim().isNotEmpty)) &&
      (!_contact ||
          _phone.text.replaceAll(RegExp(r'\D'), '').length == 10 ||
          RegExp(r'^1\d{10}$')
              .hasMatch(_phone.text.replaceAll(RegExp(r'\D'), '')));
  void _emit() {
    _writing = true;
    widget.controller.text = _valid
        ? '${_contact ? '${_first.text.trim()} ${_last.text.trim()}\n' : ''}${_street.text.trim()}${_unit.text.trim().isEmpty ? '' : '\n${_unit.text.trim()}'}\n${_city.text.trim()}, $_state ${_zip.text.trim()}\nUnited States${_contact ? '\nPhone: ${_phone.text.trim()}' : ''}'
        : '';
    _writing = false;
    if (widget.nameController != null) {
      widget.nameController!.text = '${_first.text.trim()} ${_last.text.trim()}'
          .trim();
    }
    if (widget.phoneController != null) {
      final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
      widget.phoneController!.text = digits.length == 10
          ? '+1$digits'
          : digits.startsWith('1') && digits.length == 11
          ? '+$digits'
          : _phone.text.trim();
    }
    widget.onChanged?.call();
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    bool required = true,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? hint,
    String? Function(String?)? validator,
  }) => TextFormField(
    key: ValueKey('${widget.label}-$key'),
    controller: c,
    textCapitalization: TextCapitalization.words,
    keyboardType: keyboard,
    inputFormatters: formatters,
    autocorrect: false,
    decoration: InputDecoration(labelText: label, hintText: hint),
    onChanged: (_) => _emit(),
    validator: validator ?? (required ? _required : null),
  );
  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    for (final c in [_street, _unit, _city, _zip, _first, _last, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isUs) {
      return TextFormField(
        controller: widget.controller,
        maxLines: 2,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: (_) => widget.onChanged?.call(),
        validator: _required,
      );
    }
    if (_legacy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label),
          SelectableText(widget.controller.text),
          TextButton(
            onPressed: () {
              setState(() => _legacy = false);
              _writing = true;
              widget.controller.clear();
              _writing = false;
              widget.onChanged?.call();
            },
            child: const Text('Replace with structured US address'),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffe0e4eb)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.label} · United States',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          if (_contact) ...[
            Row(
              children: [
                Expanded(child: _field('first', 'First name *', _first)),
                const SizedBox(width: 12),
                Expanded(child: _field('last', 'Last name *', _last)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _field(
            'street',
            'Street address *',
            _street,
            hint: '1234 Main Street',
          ),
          const SizedBox(height: 12),
          _field(
            'unit',
            'Apartment, suite, unit (optional)',
            _unit,
            required: false,
            hint: 'Apt 205',
          ),
          const SizedBox(height: 12),
          _field('city', 'City *', _city, hint: 'Omaha'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('${widget.label}-state'),
            initialValue: _state,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'State *'),
            items: usStates.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      '${e.value} (${e.key})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() => _state = v);
              _emit();
            },
            validator: (v) => v == null ? 'Select a state' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field(
                  'zip',
                  'ZIP code *',
                  _zip,
                  keyboard: TextInputType.number,
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                    LengthLimitingTextInputFormatter(10),
                  ],
                  hint: '68104',
                  validator: (v) =>
                      RegExp(r'^\d{5}(-\d{4})?$').hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Use 12345 or 12345-6789',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: 'United States',
                  readOnly: true,
                  decoration: InputDecoration(labelText: 'Country'),
                ),
              ),
            ],
          ),
          if (_contact) ...[
            const SizedBox(height: 12),
            _field(
              'phone',
              'US phone number *',
              _phone,
              formatters: [_UsPhoneFormatter()],
              keyboard: TextInputType.phone,
              hint: '(402) 555-0123',
              validator: (v) {
                final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return d.length == 10 || RegExp(r'^1\d{10}$').hasMatch(d)
                    ? null
                    : 'Enter a 10-digit US phone number';
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _UsPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);
    var prefix = '';
    if (digits.length == 11 && digits.startsWith('1')) {
      digits = digits.substring(1);
      prefix = '+1 ';
    }
    final text = digits.length <= 3
        ? digits
        : digits.length <= 6
        ? '(${digits.substring(0, 3)}) ${digits.substring(3)}'
        : '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
    final result = '$prefix$text';
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
