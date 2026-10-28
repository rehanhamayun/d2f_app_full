import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Detail display for goods photos in a shipment. Tapping a photo opens a
/// full-screen viewer. Actual image bytes are delegated to the loader so
/// customer and staff callers attach the correct endpoints.
class GoodsPhotoGallery extends StatefulWidget {
  final List<ParcelImageMeta> images;
  final Future<Uint8List> Function(ParcelImageMeta image) loadBytes;
  final bool canDelete;
  final Future<void> Function(ParcelImageMeta image)? onDelete;
  final VoidCallback? onChanged;
  final bool compact;

  const GoodsPhotoGallery({
    super.key,
    required this.images,
    required this.loadBytes,
    this.canDelete = false,
    this.onDelete,
    this.onChanged,
    this.compact = false,
  });

  @override
  State<GoodsPhotoGallery> createState() => _GoodsPhotoGalleryState();
}

class _GoodsPhotoGalleryState extends State<GoodsPhotoGallery> {
  final Map<String, Uint8List> _cache = {};

  Future<Uint8List> _bytesFor(ParcelImageMeta image) async {
    final cached = _cache[image.id];
    if (cached != null) return cached;
    final bytes = await widget.loadBytes(image);
    _cache[image.id] = bytes;
    return bytes;
  }

  void _invalidate(String id) {
    _cache.remove(id);
  }

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = widget.compact ? 3 : 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.images.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final image = widget.images[index];
            return _PhotoTile(
              image: image,
              loader: _bytesFor,
              canDelete: widget.canDelete,
              onDelete: widget.canDelete && widget.onDelete != null
                  ? () => _confirmDelete(image)
                  : null,
              onOpen: () => _openViewer(image),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(ParcelImageMeta image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text(
          'The photo of the goods will be removed from the shipment request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.onDelete?.call(image);
      _invalidate(image.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Photo removed.')));
        widget.onChanged?.call();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove the photo.')),
        );
      }
    }
  }

  Future<void> _openViewer(ParcelImageMeta image) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _FullScreenPhoto(image: image, bytesLoader: () => _bytesFor(image)),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final ParcelImageMeta image;
  final Future<Uint8List> Function(ParcelImageMeta) loader;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onOpen;

  const _PhotoTile({
    required this.image,
    required this.loader,
    required this.canDelete,
    this.onDelete,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.subtle,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List>(
            future: loader(image),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (snapshot.hasError ||
                  snapshot.data == null ||
                  snapshot.data!.isEmpty) {
                return const Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: AppColors.textGrey,
                    size: 24,
                  ),
                );
              }
              return InkWell(
                onTap: onOpen,
                child: Ink.image(
                  image: MemoryImage(snapshot.data!),
                  fit: BoxFit.cover,
                ),
              );
            },
          ),
          if (canDelete && onDelete != null)
            Positioned(top: 4, right: 4, child: _DeleteBadge(onTap: onDelete!)),
        ],
      ),
    );
  }
}

class _DeleteBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteBadge({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.close_rounded, color: Colors.white, size: 14),
      ),
    ),
  );
}

class _FullScreenPhoto extends StatelessWidget {
  final ParcelImageMeta image;
  final Future<Uint8List> Function() bytesLoader;

  const _FullScreenPhoto({required this.image, required this.bytesLoader});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    image.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy file name',
                  icon: const Icon(
                    Icons.copy_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: image.fileName));
                    Navigator.pop(context);
                    copyToClipboard(
                      context,
                      image.fileName,
                      message: 'File name copied.',
                    );
                  },
                ),
              ],
            ),
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: bytesLoader(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return const Center(
                      child: Text(
                        'Photo could not be loaded.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  return InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                image.createdAt != null
                    ? DateFormat('MMM d, yyyy · h:mm a')
                          .format(image.createdAt!)
                    : image.fileName,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small tile summarizing one declared package in a shipment. Shows the
/// package type, optional L×W×H reading, the allocated sub-code ("P01") and
/// the pickup collection outcome so customers and staff see the same story.
class GoodsItemTile extends StatelessWidget {
  final ParcelItem item;
  final String? trailingNote;

  /// Total declared packages, for the "Box 2 of 6" position caption.
  final int itemCount;

  const GoodsItemTile({
    super.key,
    required this.item,
    this.trailingNote,
    this.itemCount = 0,
  });

  String _cm(double? value) {
    if (value == null) return '';
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }

  String? get _metaLine {
    final parts = <String>[
      if (itemCount > 0)
        '${item.typeLabel} ${item.position + 1} of $itemCount'
      else if (item.type != 'BOX')
        item.typeLabel,
      if (item.lengthCm != null &&
          item.widthCm != null &&
          item.heightCm != null)
        '${_cm(item.lengthCm)}×${_cm(item.widthCm)}×${_cm(item.heightCm)} cm',
      if (item.packageCode != null) _codeLabel(item.packageCode!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Only the short "P01" segment is shown in rows; the full
  /// `trackingId-P01` code travels on the printed label for scanning.
  String _codeLabel(String packageCode) {
    final separator = packageCode.lastIndexOf('-P');
    return separator >= 0 ? packageCode.substring(separator + 1) : packageCode;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: item.missed ? AppColors.coralSoft : AppColors.goldSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            item.missed ? Icons.unarchive_outlined : Icons.inventory_2_outlined,
            size: 17,
            color: item.missed ? AppColors.coral : AppColors.navy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (_metaLine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _metaLine!,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              if (item.details != null && item.details!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    item.details!,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
              if (item.missed)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Not collected · ${item.notCollectedReason}',
                    style: const TextStyle(
                      color: AppColors.coral,
                      fontSize: 10.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (trailingNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    trailingNote!,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 10.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '×${item.quantity}',
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            if (item.weightKg != null)
              Text(
                '${item.weightKg} kg',
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 10.5,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
