import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import 'reference_widgets.dart';
import 'common.dart' show PrimaryButton;

const authNavy = AppColors.navy;
const authBlue = AppColors.blue;
const authCanvas = AppColors.cream;
const authMuted = AppColors.textGrey;

class AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class ShippingLogo extends StatelessWidget {
  final double width;
  const ShippingLogo({super.key, this.width = 150});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: BrandWordmark(fontSize: width * .15),
  );
}

/// Compatibility wrapper for existing forms; styling comes from the shared CTA.
class GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.height = 52,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: PrimaryButton(label: label, onPressed: onPressed, loading: loading),
  );
}

class AuthInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix, prefix;
  final TextInputType? keyboardType;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final double height;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  const AuthInput({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.prefix,
    this.keyboardType,
    this.action = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.height = 49,
    this.focusNode,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        obscureText: obscure,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: action,
        onSubmitted: onSubmitted,
        autofillHints: autofillHints,
        autocorrect: false,
        enableSuggestions: !obscure,
        textCapitalization: hint == 'Full Name'
            ? TextCapitalization.words
            : TextCapitalization.none,
        style: const TextStyle(color: authNavy, fontSize: 13),
        cursorColor: authBlue,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 13),
          prefixIcon: prefix ?? Icon(icon, size: 20, color: authNavy),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 46,
            minHeight: 40,
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 14,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          enabledBorder: OutlineInputBorder(
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

/// Native-size fields on phones; extreme short/landscape viewports scale down.
/// There is deliberately no vertical scrolling surface on an auth page.
class AuthFit extends StatelessWidget {
  final Widget Function(double height) builder;
  final double minHeight;
  const AuthFit({super.key, required this.builder, required this.minHeight});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight < minHeight
          ? minHeight
          : constraints.maxHeight;
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: builder(height),
        ),
      );
    },
  );
}

void authMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> authInfo(BuildContext context, String title, String body) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(color: authNavy, fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Text(body, style: const TextStyle(height: 1.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
