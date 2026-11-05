import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import 'auth_widgets.dart';

/// Autocomplete text field for country selection.
///
/// Offers every country D2F covers — the United States, the European Union
/// area and West Africa / the Sahel — as the shopper types, with a friendly
/// dropdown (and the full list when the field is empty). Used wherever a
/// country is captured: checkout delivery details, seller studio, buyer
/// signup, route planner and more.
class CountryAutocompleteField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final String label;
  final String hint;
  final IconData icon;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;

  const CountryAutocompleteField({
    super.key,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.validator,
    required this.label,
    required this.hint,
    this.icon = Icons.public_rounded,
    this.textCapitalization = TextCapitalization.words,
    this.keyboardType,
  });

  @override
  State<CountryAutocompleteField> createState() =>
      _CountryAutocompleteFieldState();
}

class _CountryAutocompleteFieldState extends State<CountryAutocompleteField> {
  late final TextEditingController _fallbackController = TextEditingController();
  late final FocusNode _fallbackFocusNode = FocusNode();

  TextEditingController get _controller => widget.controller ?? _fallbackController;
  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode;

  @override
  void dispose() {
    _fallbackController.dispose();
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final query = foldRouteText(value.text).trim();
        final options = query.isEmpty
            ? kCountryOptions
            : kCountryOptions
                .where((country) => foldRouteText(country).contains(query))
                .take(8)
                .toList();
        return options;
      },
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.white,
          elevation: 4,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: constraints.maxWidth,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.public_outlined,
                        size: 18,
                        color: authMuted,
                      ),
                      title: Text(
                        option,
                        style: const TextStyle(
                          color: authNavy,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => select(option),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      fieldViewBuilder: (context, text, node, submit) => TextFormField(
        controller: text,
        focusNode: node,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => submit(),
        onChanged: widget.onChanged == null ? null : (value) => widget.onChanged!(value),
        validator: widget.validator,
        style: const TextStyle(
          color: authNavy,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon, size: 21, color: authNavy),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: authBlue, width: 1.3),
          ),
        ),
      ),
    ),
  );
}
