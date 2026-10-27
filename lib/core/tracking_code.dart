/// Normalizes barcode/QR payloads into a D2F tracking number.
///
/// Labels normally contain the tracking ID alone, but printed URLs, JSON
/// wrappers, scanner prefixes, spaces and lower-case values are common. The
/// API expects one canonical value, so every scan and manual lookup passes
/// through this function before a request is made.
String? normalizeTrackingCode(String? input) {
  if (input == null) return null;
  var value = input.trim();
  if (value.isEmpty) return null;

  // QR payloads are sometimes percent-encoded URLs or JSON strings.
  try {
    value = Uri.decodeFull(value);
  } catch (_) {
    // Keep the original text when it is not valid percent-encoding.
  }

  // Legacy D2F-2026-000101 identities.
  final dashed = RegExp(
    r'(D2F)\s*-\s*(\d{4})\s*-\s*(\d{6})',
    caseSensitive: false,
  ).firstMatch(value);
  if (dashed != null) {
    return 'D2F-${dashed.group(2)}-${dashed.group(3)}';
  }

  // Printed labels often group the digits ("D2F 0000 0000 0005") or separate
  // the prefix with a dash, so normalize the separators before matching.
  final compact = value.replaceAll(RegExp(r'[\s_-]+'), '');

  // A Code 128 label may contain only the numeric sequence. Check this before
  // the prefixed pattern, otherwise the first digits are mistaken for a prefix.
  final digits = RegExp(r'^(\d{12}|\d{15})$').firstMatch(compact);
  if (digits != null) return 'D2F${digits.group(1)}';

  // Current organization-prefixed identities, e.g. D2F000000000005. The
  // prefix must start with a letter so numeric-only barcodes cannot match.
  final prefixed = RegExp(
    r'([A-Z][A-Z0-9]{2,4})(\d{12}|\d{15})',
    caseSensitive: false,
  ).firstMatch(compact);
  if (prefixed != null) {
    return '${prefixed.group(1)!.toUpperCase()}${prefixed.group(2)}';
  }

  return null;
}
