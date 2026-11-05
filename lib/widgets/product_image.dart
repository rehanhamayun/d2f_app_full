import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api.dart';

/// Authenticated product photo with a shared in-memory cache.
/// Photos ride behind the session token, so they are fetched as bytes
/// rather than through Image.network.
class ProductImage extends StatefulWidget {
  final String productId;
  final String? imageId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final IconData placeholderIcon;

  const ProductImage({
    super.key,
    required this.productId,
    required this.imageId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(0)),
    this.placeholderIcon = Icons.shopping_bag_outlined,
  });

  /// Test hook / memory relief: drops cached bytes.
  static void clearCache() => _ProductImageState._cache.clear();

  @override
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  static const int _cacheLimit = 240;
  static final Map<String, Uint8List> _cache = {};

  late Future<Uint8List?> _future;

  String get _key => '${widget.productId}/${widget.imageId}';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(ProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId || oldWidget.productId != widget.productId) {
      _future = _load();
    }
  }

  Future<Uint8List?> _load() async {
    final imageId = widget.imageId;
    if (imageId == null) return null;
    final cached = _cache[_key];
    if (cached != null) return cached;
    try {
      final bytes = await Api.I.marketplaceProductImage(widget.productId, imageId);
      if (_cache.length >= _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      _cache[_key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.imageId == null
            ? _placeholder()
            : FutureBuilder<Uint8List?>(
                future: _future,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Container(
                      color: const Color(0xFFF4F1EA),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (bytes == null) return _placeholder();
                  return Image.memory(
                    bytes,
                    fit: widget.fit,
                    width: widget.width,
                    height: widget.height,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => _placeholder(),
                  );
                },
              ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFF4F1EA),
        alignment: Alignment.center,
        child: Icon(widget.placeholderIcon, size: 34, color: const Color(0xFFC9C4B8)),
      );
}
