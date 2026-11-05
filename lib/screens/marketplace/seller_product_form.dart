import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/country_autocomplete_field.dart';
import '../../widgets/product_image.dart';

/// Create or edit a marketplace listing, including photos.
class SellerProductFormScreen extends StatefulWidget {
  final MarketplaceProduct? product;
  const SellerProductFormScreen({super.key, this.product});

  @override
  State<SellerProductFormScreen> createState() => _SellerProductFormScreenState();
}

class _QueuedPhoto {
  final Uint8List bytes;
  final String fileName, contentType;
  const _QueuedPhoto(this.bytes, this.fileName, this.contentType);
}

class _SellerProductFormScreenState extends State<SellerProductFormScreen> {
  static const _categorySuggestions = [
    'Electronics', 'Fashion', 'Handmade & Crafts', 'Spices & Food',
    'Beauty & Care', 'Home & Living', 'African finds', 'Kids & Baby', 'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();

  String _currency = 'USD';
  String _fulfillment = 'SELLER';
  final List<ProductImageMeta> _images = [];
  final List<_QueuedPhoto> _queued = [];
  String? _productId; // set once created (create mode) or from widget.product

  bool _busy = false;
  String? _progress;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _productId = p.id;
      _title.text = p.title;
      _category.text = p.category;
      _description.text = p.description ?? '';
      _currency = p.currency;
      _price.text = _currency == 'XOF' ? p.priceMinor.toString() : (p.priceMinor / 100).toStringAsFixed(2);
      _fulfillment = p.fulfillment;
      _stock.text = p.stockCount?.toString() ?? '';
      _city.text = p.locationCity ?? '';
      _country.text = p.locationCountry ?? '';
      _images.addAll(p.images);
    } else {
      _prefillLocation();
    }
  }

  Future<void> _prefillLocation() async {
    try {
      final me = await Api.I.sellerMe();
      if (!mounted || me.profile == null) return;
      setState(() {
        _city.text = me.profile!.city ?? '';
        _country.text = me.profile!.country;
      });
    } catch (_) {
      // Location stays manual if the profile can't be read.
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _description, _price, _stock, _city, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalPhotos => _images.length + _queued.length;

  Future<void> _pickPhoto(ImageSource source) async {
    if (_totalPhotos >= 6) {
      authMessage(context, 'A listing can hold at most 6 photos.');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 72);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final lower = picked.name.toLowerCase();
    final contentType = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    if (_editing || _productId != null) {
      await _uploadExisting(bytes, picked.name, contentType);
    } else {
      setState(() => _queued.add(_QueuedPhoto(bytes, picked.name, contentType)));
    }
  }

  Future<void> _uploadExisting(Uint8List bytes, String name, String contentType) async {
    final id = _productId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final image = await Api.I.uploadSellerProductImage(
        id,
        bytes,
        fileName: name,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() => _images.add(image));
    } on ApiException catch (error) {
      authMessage(context, error.message);
    } catch (_) {
      authMessage(context, 'The photo could not be uploaded. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage(ProductImageMeta image) async {
    final id = _productId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await Api.I.deleteSellerProductImage(id, image.id);
      if (!mounted) return;
      setState(() => _images.removeWhere((i) => i.id == image.id));
    } catch (_) {
      authMessage(context, 'The photo could not be removed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePhotoSource() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD8D4C9), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  int? _parseMinorPrice() {
    final raw = _price.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    return _currency == 'XOF' ? value.round() : (value * 100).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final minor = _parseMinorPrice();
    if (minor == null || minor <= 0) {
      authMessage(context, 'Enter a valid price.');
      return;
    }
    final stockText = _stock.text.trim();
    int? stock;
    if (stockText.isNotEmpty) {
      stock = int.tryParse(stockText);
      if (stock == null || stock < 0) {
        authMessage(context, 'Stock must be a whole number (or empty if untracked).');
        return;
      }
    }

    setState(() {
      _busy = true;
      _progress = _editing ? 'Saving…' : 'Creating listing…';
    });
    try {
      MarketplaceProduct saved;
      if (_editing) {
        saved = await Api.I.updateSellerProduct(
          widget.product!.id,
          title: _title.text,
          category: _category.text,
          description: _description.text,
          priceMinor: minor,
          currency: _currency,
          fulfillment: _fulfillment,
          stockCount: stock,
          clearStock: stock == null && widget.product!.stockCount != null,
          locationCity: _city.text,
          locationCountry: _country.text,
        );
      } else {
        saved = await Api.I.createSellerProduct(
          title: _title.text,
          category: _category.text,
          description: _description.text,
          priceMinor: minor,
          currency: _currency,
          fulfillment: _fulfillment,
          stockCount: stock,
          locationCity: _city.text,
          locationCountry: _country.text,
        );
      }
      _productId = saved.id;
      // Upload queued photos (create mode only; edits upload immediately).
      var failures = 0;
      for (var i = 0; i < _queued.length; i++) {
        final photo = _queued[i];
        setState(() => _progress = 'Uploading photos… ${i + 1}/${_queued.length}');
        try {
          final image = await Api.I.uploadSellerProductImage(
            saved.id,
            photo.bytes,
            fileName: photo.fileName,
            contentType: photo.contentType,
          );
          _images.add(image);
        } catch (_) {
          failures++;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failures == 0
              ? (_editing ? 'Listing saved.' : 'Listing is live!')
              : 'Listing saved — $failures photo(s) failed. Edit to retry.'),
        ),
      );
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('The listing could not be saved. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });
    authMessage(context, message);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove listing?'),
        content: const Text(
          'Listings without orders are deleted. Listings with orders are paused so your sales history stays intact.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep listing')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final archived = await Api.I.deleteSellerProduct(widget.product!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archived ? 'Listing paused — it has orders.' : 'Listing deleted.')),
      );
      Navigator.pop(context, true);
    } catch (_) {
      _fail('The listing could not be removed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(_editing ? 'Edit listing' : 'New listing'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            const Text('What are you selling?', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().length < 3) ? 'Enter a title for the listing.' : null,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Smoked dried pepper, 500g',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _category,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a category.' : null,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'e.g. Spices & Food',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final suggestion in _categorySuggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => setState(() => _category.text = suggestion),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Materials, size, how it’s made, care…',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Price', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Price?' : null,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    items: const [
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      DropdownMenuItem(value: 'XOF', child: Text('XOF')),
                    ],
                    onChanged: (value) => setState(() => _currency = value ?? 'USD'),
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Who fulfils this?', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _FulfillmentCard(
                    selected: _fulfillment == 'SELLER',
                    icon: Icons.local_shipping_outlined,
                    title: 'I ship it',
                    subtitle: 'You arrange delivery',
                    onTap: () => setState(() => _fulfillment = 'SELLER'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FulfillmentCard(
                    selected: _fulfillment == 'D2F',
                    icon: Icons.warehouse_rounded,
                    title: 'D2F fulfils',
                    subtitle: 'We store, pick & pack',
                    onTap: () => setState(() => _fulfillment = 'D2F'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Stock', style: AppTheme.sectionTitle),
            const SizedBox(height: 4),
            const Text(
              'Leave empty if you don’t track stock yet. If set, we decrement it on every order and hide the listing when it runs out.',
              style: TextStyle(fontSize: 10.5, height: 1.5, color: AppColors.textGrey),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _stock,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Units available',
                hintText: 'e.g. 25',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Where is it shipped from?', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      hintText: 'Lomé',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CountryAutocompleteField(
                    controller: _country,
                    label: 'Country',
                    hint: 'Togo',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Photos', style: AppTheme.sectionTitle),
                const SizedBox(width: 8),
                Text(
                  '$_totalPhotos/6',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textGrey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'The first photo is the cover. Good light and a plain background sell.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textGrey),
            ),
            const SizedBox(height: 10),
            _photoGrid(),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
                child: _busy
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          ),
                          if (_progress != null) ...[
                            const SizedBox(width: 12),
                            Text(
                              _progress!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ],
                      )
                    : Text(
                        _editing ? 'Save changes' : 'Publish listing',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
              ),
            ),
            if (_editing) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _busy ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.coral,
                    side: const BorderSide(color: AppColors.coral),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text('Remove listing'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoGrid() {
    final cells = <Widget>[
      for (final image in _images)
        _PhotoCell(
          busy: _busy,
          onRemove: () => _removeImage(image),
          child: ProductImage(
            productId: _productId!,
            imageId: image.id,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      for (final photo in _queued)
        _PhotoCell(
          busy: _busy,
          onRemove: () => setState(() => _queued.remove(photo)),
          child: Image.memory(photo.bytes, fit: BoxFit.cover),
        ),
      if (_totalPhotos < 6)
        Material(
          color: AppColors.subtle,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: _busy ? null : _choosePhotoSource,
            borderRadius: BorderRadius.circular(16),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo_outlined, size: 26, color: AppColors.textGrey),
                SizedBox(height: 6),
                Text(
                  'Add photo',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
        ),
    ];
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: .82,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}

class _PhotoCell extends StatelessWidget {
  final Widget child;
  final bool busy;
  final VoidCallback onRemove;
  const _PhotoCell({required this.child, required this.busy, required this.onRemove});

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
          Positioned(
            top: 5,
            right: 5,
            child: Material(
              color: Colors.black.withValues(alpha: .55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      );
}

class _FulfillmentCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _FulfillmentCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? AppColors.navy : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: selected ? AppColors.gold : AppColors.textGrey),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.4,
                    color: selected ? const Color(0xFFB9C3DE) : AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
