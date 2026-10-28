import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/common.dart';
import '../widgets/goods_gallery.dart';
import '../widgets/route_planner.dart';
import '../widgets/timeline.dart';

typedef CustomerShipmentCreator = Future<Parcel> Function({
  required String recipientName,
  required String recipientPhone,
  required String recipientAddress,
  required String packageType,
  required double weightKg,
  required String origin,
  required String destination,
  required String method,
  required String deliveryMode,
  // Truthful-declaration acknowledgment (compulsory on the request form).
  bool restrictionsAcknowledged,
  String? pickupAddress,
  DateTime? pickupScheduledAt,
  List<ParcelItem> items,
  String? notes,
  required String clientRequestId,
});

/// Injectable photo source so tests never touch device galleries.
typedef GoodsPhotoPicker = Future<PhotoDraft?> Function();

const _defaultCustomerRoute = ShipmentRoute(
  origin: 'Omaha, NE, USA',
  destination: 'Lomé, Togo',
);

const _customerPackageTypes = <(String, String)>[
  ('BOX', 'Box'),
  ('SUITCASE', 'Suitcase'),
  ('BARREL', 'Barrel'),
  ('TV', 'TV / electronics'),
  ('APPLIANCE', 'Appliance'),
  ('FURNITURE', 'Furniture'),
  ('PALLET', 'Pallet'),
  ('VEHICLE', 'Vehicle'),
  ('DOCUMENTS', 'Documents'),
  ('OTHER', 'Other'),
];

const String kGoogleMapsCheckKey = 'customer-address-map-check';

/// One goods entry in the "what are you sending" repeater. A shipment may
/// include many things — each row carries a name, quantity and optional note.
class GoodsDraft {
  final TextEditingController name = TextEditingController();
  final TextEditingController quantity = TextEditingController();
  final TextEditingController details = TextEditingController();
  final TextEditingController size = TextEditingController();
  String type = 'BOX';
  final List<PhotoDraft> photos = <PhotoDraft>[];

  int get quantityValue {
    final parsed = int.tryParse(quantity.text.trim());
    return (parsed == null || parsed < 1) ? 1 : parsed.clamp(1, 999);
  }

  String get nameValue => name.text.trim();

  String get detailsValue => details.text.trim();

  String get sizeText => size.text.trim();

  /// Parsed L×W×H centimeters; an empty field means "no dimensions".
  /// Returns null when the text exists but is not a readable measurement.
  List<double>? get dimensions {
    final text = sizeText.toLowerCase().replaceAll('×', 'x');
    if (text.isEmpty) return const <double>[];
    final parts = text.split(RegExp(r'\s*x\s*'));
    if (parts.length != 3) return null;
    final numbers = <double>[];
    for (final part in parts) {
      final value = double.tryParse(part.trim());
      if (value == null || !value.isFinite || value < 1 || value > 1000) {
        return null;
      }
      numbers.add((value * 10).round() / 10);
    }
    return numbers;
  }

  bool get sizeMalformed => sizeText.isNotEmpty && dimensions == null;

  /// Null when the row is blank (empty rows are ignored by the form, so
  /// partially filled rows cannot silently disappear).
  ParcelItem? toParcelItem(int position) {
    final label = nameValue;
    if (label.isEmpty) return null;
    final dims = dimensions ?? const <double>[];
    return ParcelItem(
      id: 'draft-$position',
      name: label,
      details: detailsValue.isEmpty ? null : detailsValue,
      quantity: quantityValue,
      position: position,
      type: type,
      lengthCm: dims.length == 3 ? dims[0] : null,
      widthCm: dims.length == 3 ? dims[1] : null,
      heightCm: dims.length == 3 ? dims[2] : null,
    );
  }

  void dispose() {
    name.dispose();
    quantity.dispose();
    details.dispose();
    size.dispose();
  }
}

/// A photo staged for upload (not attached to the shipment yet).
class PhotoDraft {
  final String fileName;
  final String contentType;
  final Uint8List bytes;

  const PhotoDraft(this.fileName, this.contentType, this.bytes);

  String get sizeLabel {
    final kb = bytes.length / 1024;
    return kb >= 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB'
        : '${kb.round()} KB';
  }
}

/// The customer's shipment workspace: list the things to send, choose how the
/// goods reach D2F (pickup at an agreed time, or a warehouse drop-off), and
/// optionally attach photos so the team sees what is being shipped.
class CustomerShipmentScreen extends ConsumerStatefulWidget {
  final ShipmentRoute? initialRoute;
  final ValueChanged<ShipmentRoute>? onRouteSelected;
  final Future<List<Parcel>> Function()? loadParcels;
  final CustomerShipmentCreator? createParcel;

  /// Optional override of the device gallery/camera so widget tests stay pure.
  final GoodsPhotoPicker? pickPhoto;
  final Future<void> Function(String parcelId, String itemId, PhotoDraft photo)?
  uploadPhoto;
  final Future<Parcel> Function(String parcelId)? loadParcel;

  /// Optional override of the date/time pickers so widget tests can schedule
  /// a pickup without driving system dialogs.
  final Future<DateTime?> Function()? selectSchedule;

  const CustomerShipmentScreen({
    super.key,
    this.initialRoute,
    this.onRouteSelected,
    this.loadParcels,
    this.createParcel,
    this.pickPhoto,
    this.uploadPhoto,
    this.loadParcel,
    this.selectSchedule,
  });

  @override
  ConsumerState<CustomerShipmentScreen> createState() =>
      _CustomerShipmentScreenState();
}

class _CustomerShipmentScreenState
    extends ConsumerState<CustomerShipmentScreen> {
  static const _maxPhotos = 8;
  static const _maxItems = 20;

  final _formKey = GlobalKey<FormState>();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientAddress = TextEditingController();
  final _pickupAddress = TextEditingController();
  final _weight = TextEditingController();
  final _notes = TextEditingController();
  final List<GoodsDraft> _goods = [GoodsDraft()];
  bool _restrictionsAck = false;

  ShipmentRoute _route = _defaultCustomerRoute;
  String? _packageType;
  DeliveryMode _deliveryMode = DeliveryMode.DROP_OFF;
  DateTime? _pickupWhen;
  bool _pickupMissingSchedule = false;
  String? _requestId;
  List<Parcel> _parcels = const [];
  String? _parcelsError;
  bool _loadingParcels = true;
  bool _saving = false;
  // Mirrors build()'s profile-phone check so the create action, which lives
  // inside _handoverSection(), can disable itself until the number exists.
  bool _hasPhone = true;

  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute ?? _defaultCustomerRoute;
    _loadParcels();
  }

  @override
  void didUpdateWidget(covariant CustomerShipmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRoute != widget.initialRoute &&
        widget.initialRoute != null) {
      _route = widget.initialRoute!;
    }
  }

  @override
  void dispose() {
    _recipientName.dispose();
    _recipientPhone.dispose();
    _recipientAddress.dispose();
    _pickupAddress.dispose();
    _weight.dispose();
    _notes.dispose();
    for (final draft in _goods.toList()) {
      draft.dispose();
    }
    super.dispose();
  }

  void _invalidateRequest() => _requestId = null;

  Future<void> _editRoute() async {
    final route = await showRoutePlanner(context, _route);
    if (route == null || !mounted) return;
    setState(() {
      _route = route;
      _invalidateRequest();
    });
    widget.onRouteSelected?.call(route);
  }

  Future<void> _loadParcels() async {
    setState(() {
      _loadingParcels = true;
      _parcelsError = null;
    });
    try {
      final parcels = await (widget.loadParcels ?? Api.I.customerParcels)();
      if (!mounted) return;
      setState(() {
        _parcels = parcels;
        _loadingParcels = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _parcelsError = error.message;
        _loadingParcels = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _parcelsError = 'Could not load your shipments. Please try again.';
        _loadingParcels = false;
      });
    }
  }

  void _addGoods() {
    if (_goods.length >= _maxItems) return;
    setState(() => _goods.add(GoodsDraft()));
    _invalidateRequest();
  }

  void _removeGoods(int index) {
    setState(() => _goods.removeAt(index).dispose());
    _invalidateRequest();
  }

  /// Non-blank rows. Blank rows are ignored; a shipment must name at least
  /// one thing being sent.
  List<ParcelItem> _collectGoods() {
    final items = <ParcelItem>[];
    for (var index = 0; index < _goods.length; index += 1) {
      final item = _goods[index].toParcelItem(index);
      if (item != null) items.add(item);
    }
    return items;
  }

  Future<void> _contactSupport() async {
    try {
      if (await launchUrl(
        Uri(scheme: 'mailto', path: 'info@d2fshipping.com'),
      )) {
        return;
      }
    } catch (_) {
      // Copy the address when no email app is available.
    }
    if (mounted) {
      copyToClipboard(
        context,
        'info@d2fshipping.com',
        message: 'Support email copied.',
      );
    }
  }

  /// Opens Google Maps on the typed address so the customer can verify the
  /// pin before our team relies on it.
  Future<void> _checkAddress(String address) async {
    final encoded = Uri.encodeQueryComponent(address);
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$encoded',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        copyToClipboard(
          context,
          'https://www.google.com/maps/search/?api=1&query=$encoded',
          message: 'Map link copied — open it in your browser.',
        );
      }
    }
  }

  Future<void> _pickDateTime() async {
    if (widget.selectSchedule != null) {
      final when = await widget.selectSchedule!();
      if (when == null || !mounted) return;
      setState(() {
        _pickupWhen = when;
        _pickupMissingSchedule = false;
        _invalidateRequest();
      });
      return;
    }
    final now = DateTime.now();
    final base = _pickupWhen ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: now.isAfter(base) ? now.add(const Duration(days: 1)) : base,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Pickup date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: 'Pickup time',
    );
    if (time == null) return;
    setState(() {
      _pickupWhen = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _pickupMissingSchedule = false;
      _invalidateRequest();
    });
  }

  /// Total staged photos across all goods rows.
  int get _stagedPhotoCount =>
      _goods.fold(0, (total, draft) => total + draft.photos.length);

  /// Opens the gallery/camera and stages the photo on one goods row. Photos
  /// are optional per package (functional workflow §2) and upload after the
  /// shipment exists so they can be linked to that row's package record.
  Future<void> _addRowPhoto(int index) async {
    if (_stagedPhotoCount >= _maxPhotos) {
      authMessage(
        context,
        'A shipment can hold at most $_maxPhotos photos of the goods.',
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final picked = widget.pickPhoto != null
          ? await widget.pickPhoto!()
          : await _pickFromDevice(source);
      if (picked == null || !mounted) return;
      setState(() {
        _goods[index].photos.add(picked);
        _invalidateRequest();
      });
    } catch (_) {
      if (mounted) {
        authMessage(context, 'Could not add that photo. Please try again.');
      }
    }
  }

  Future<PhotoDraft?> _pickFromDevice(ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 1600,
    );
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    final contentType = _contentTypeFor(xfile.name);
    return PhotoDraft(xfile.name, contentType, bytes);
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _removeRowPhoto(int rowIndex, int photoIndex) => setState(() {
    _goods[rowIndex].photos.removeAt(photoIndex);
    _invalidateRequest();
  });

  Future<void> _createShipment() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Rows with photos must describe the package, and a size reading must be
    // a full L×W×H measurement — individual photos can never be orphaned.
    for (var index = 0; index < _goods.length; index += 1) {
      final draft = _goods[index];
      if (draft.nameValue.isEmpty && draft.photos.isNotEmpty) {
        authMessage(
          context,
          'Item ${index + 1} has photos but no description — name it so our team knows which package they document.',
        );
        return;
      }
      if (draft.sizeMalformed) {
        authMessage(
          context,
          'Item ${index + 1}: enter the size as L×W×H centimetres, e.g. 60×40×45, or leave it empty.',
        );
        return;
      }
    }
    final goods = _collectGoods();
    if (goods.isEmpty) {
      authMessage(
        context,
        'List at least one thing you are sending. Describe each item in your own words.',
      );
      return;
    }
    final weight = double.tryParse(_weight.text.trim());
    if (weight == null || !weight.isFinite || weight <= 0) return;
    if (_deliveryMode == DeliveryMode.PICKUP && _pickupWhen == null) {
      // The schedule is compulsory for pickups; point at the field and stop.
      setState(() => _pickupMissingSchedule = true);
      return;
    }
    if (!_restrictionsAck) {
      authMessage(
        context,
        'Confirm that your goods list is accurate and complies with shipping restrictions.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    _requestId ??=
        'customer-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    try {
      // (rowIndex, photos) pairs survive create; the response items keep the
      // declared order, so link each row's photos to its package record.
      final photoUploads = <int, List<PhotoDraft>>{
        for (var index = 0; index < _goods.length; index += 1)
          if (_goods[index].photos.isNotEmpty)
            index: List<PhotoDraft>.of(_goods[index].photos),
      };
      var parcel = await (widget.createParcel ?? Api.I.createCustomerParcel)(
        recipientName: _recipientName.text.trim(),
        recipientPhone: _recipientPhone.text.trim(),
        recipientAddress: _recipientAddress.text.trim(),
        packageType: _packageType!,
        weightKg: weight,
        origin: _route.origin,
        destination: _route.destination,
        method: _route.method.name,
        deliveryMode: _deliveryMode.apiName,
        restrictionsAcknowledged: true,
        pickupAddress: _deliveryMode == DeliveryMode.PICKUP
            ? _pickupAddress.text.trim()
            : null,
        pickupScheduledAt: _deliveryMode == DeliveryMode.PICKUP
            ? _pickupWhen
            : null,
        items: goods,
        notes: _notes.text.trim(),
        clientRequestId: _requestId!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      var uploadFailures = 0;
      // Attach only to the saved physical package. Keep the saved request
      // visible even if a photo cannot be uploaded.
      for (final entry in photoUploads.entries) {
        final item = parcel.items
            .where(
              (item) =>
                  item.position ==
                  goods.indexWhere((item) => item.id == 'draft-${entry.key}'),
            )
            .firstOrNull;
        for (final photo in entry.value) {
          try {
            if (item == null) {
              throw StateError('Package missing from saved request');
            }
            if (widget.uploadPhoto != null) {
              await widget.uploadPhoto!(parcel.id, item.id, photo);
            } else {
              await Api.I.addParcelImage(
                parcel.id,
                photo.bytes,
                fileName: photo.fileName,
                contentType: photo.contentType,
                itemId: item.id,
              );
            }
          } catch (_) {
            uploadFailures += 1;
          }
        }
      }

      if (photoUploads.isNotEmpty) {
        try {
          parcel = await (widget.loadParcel ?? Api.I.customerParcelDetail)(
            parcel.id,
          );
        } catch (_) {
          // A preview refresh must never turn a saved request into a failure.
        }
      }
      if (!mounted) return;
      if (uploadFailures > 0) {
        authMessage(
          context,
          'Request saved. $uploadFailures photo(s) did not upload. Keep the originals and contact D2F with your tracking ID.',
        );
      }
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CustomerParcelDetailsScreen(parcel: parcel, justCreated: true),
        ),
      );
      if (!mounted) return;
      _resetForm();
      await _loadParcels();
    } on ApiException catch (error) {
      if (mounted) authMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        authMessage(
          context,
          'Could not create your shipment. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _recipientName.clear();
    _recipientPhone.clear();
    _recipientAddress.clear();
    _pickupAddress.clear();
    _weight.clear();
    _notes.clear();
    setState(() {
      _packageType = null;
      _requestId = null;
      _pickupWhen = null;
      _restrictionsAck = false;
      for (final draft in _goods) {
        draft.dispose();
      }
      _goods
        ..clear()
        ..add(GoodsDraft());
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final hasPhone = user?.phone?.trim().isNotEmpty ?? false;
    _hasPhone = hasPhone;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BrandLogo(fontSize: 24),
                  ),
                ),
                IconButton(
                  tooltip: 'Contact D2F',
                  onPressed: _contactSupport,
                  icon: const Icon(
                    Icons.support_agent_rounded,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            // One Form spans goods, recipient, handover and photos, so the
            // create action validates the entire request in a single pass.
            child: Form(
              key: _formKey,
              onChanged: () {
                if (mounted) setState(() {});
              },
              child: ListView(
                padding: AppSpacing.pageInsets,
                children: [
                  _requestIntro(),
                  const SizedBox(height: 6),
                  const Text(
                    'List everything you are sending. Pick a route, tell us '
                    'where your goods should be collected from, and the D2F '
                    'team confirms the rest.',
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 18),
                  _contactCard(user, hasPhone),
                  const SizedBox(height: 18),
                  _formStep(
                    '01',
                    'Choose your route',
                    'Air Cargo, sea or road · your destination comes first.',
                  ),
                  _routeCard(),
                  const SizedBox(height: 18),
                  _formStep(
                    '02',
                    'Tell us what’s inside',
                    'One physical package per row. Photos help our team prepare.',
                  ),
                  _goodsSection(),
                  const SizedBox(height: 18),
                  _formStep(
                    '03',
                    'Recipient & shipment',
                    'Contact details that help your parcel arrive safely.',
                  ),
                  _shipmentForm(),
                  const SizedBox(height: 18),
                  _formStep(
                    '04',
                    'Handover & review',
                    'Choose how your goods reach D2F, then check your request.',
                  ),
                  _handoverSection(),
                  const SizedBox(height: 22),
                  SectionCard(
                    tint: AppColors.goldSoft,
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.navy,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your tracking ID is created right away. Our team '
                            'confirms your goods before the shipment moves to '
                            'Received.',
                            style: AppTheme.caption.copyWith(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your shipments',
                          style: AppTheme.sectionTitle,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh shipments',
                        onPressed: _loadingParcels ? null : _loadParcels,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _shipmentList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestIntro() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.navy, Color(0xff234d70)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.gold),
            SizedBox(width: 8),
            Text(
              'D2F SHIPPING',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'New shipment request',
          style: AppTheme.display.copyWith(color: Colors.white, fontSize: 27),
        ),
        const SizedBox(height: 8),
        const Text(
          'A little care. A smooth journey.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 18),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text('Itemized goods'),
              avatar: Icon(Icons.check, size: 15),
            ),
            Chip(
              label: Text('D2F tracking'),
              avatar: Icon(Icons.qr_code_2, size: 15),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _formStep(String number, String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.navy,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.sectionTitle),
              const SizedBox(height: 3),
              Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _reviewSummary() => SectionCard(
    tint: AppColors.blueSoft,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your request at a glance', style: AppTheme.sectionTitle),
        const SizedBox(height: 12),
        Text(
          '${_route.origin} → ${_route.destination}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_collectGoods().length} packages · ${_weight.text.isEmpty ? 'Weight to add' : '${_weight.text} kg'} · ${_route.method.label}',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 6),
        Text(
          'To: ${_recipientName.text.trim().isEmpty ? 'Add your recipient above' : _recipientName.text.trim()}',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 6),
        Text(
          _deliveryMode == DeliveryMode.PICKUP
              ? 'D2F pickup · ${_pickupWhen == null ? 'Choose your preferred time' : DateFormat('EEE, MMM d · h:mm a').format(_pickupWhen!)}'
              : 'Drop off at a D2F warehouse',
          style: AppTheme.caption,
        ),
        const Divider(height: 24),
        const Text(
          'Submitting registers your request and tracking number. D2F reviews the goods and confirms collection before transport.',
          style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.navy),
        ),
      ],
    ),
  );

  Widget _contactCard(User? user, bool hasPhone) {
    return SectionCard(
      tint: AppColors.blueSoft,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_circle_outlined,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.fullName ?? 'Your details',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPhone ? user?.phone ?? '' : 'Add your phone number in Account — our team needs it to reach you.',
                  style: TextStyle(
                    color: hasPhone ? AppColors.navy : AppColors.coral,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                Text(
                  user?.email ?? '',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeCard() => Material(
    color: AppColors.blueSoft,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      key: const ValueKey('customer-route'),
      onTap: _editRoute,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public_rounded, color: AppColors.blue),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'YOUR ROUTE',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  'Edit',
                  style: TextStyle(
                    color: AppColors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.blue),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _routePoint('FROM', _route.origin)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.flight_takeoff_rounded,
                    color: AppColors.coral,
                  ),
                ),
                Expanded(
                  child: _routePoint('TO', _route.destination, alignEnd: true),
                ),
              ],
            ),
            const Divider(height: 25),
            Row(
              children: [
                Icon(_route.method.icon, size: 18, color: AppColors.navy),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${_route.method.label} · ${_route.method.tagline}',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _routePoint(String label, String value, {bool alignEnd = false}) =>
      Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
      );

  Widget _goodsSection() => SectionCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'What are you sending?',
                style: AppTheme.sectionTitle,
              ),
            ),
            Text(
              '${_goods.length} / $_maxItems items',
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Add one row for each physical package, such as a box, suitcase or '
          'barrel. Use quantity for the contents inside that package.',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 14),
        FormField<bool>(
          key: const ValueKey('customer-goods'),
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < _goods.length; index += 1) ...[
                _GoodsRow(
                  key: ValueKey('goods-row-$index'),
                  index: index,
                  draft: _goods[index],
                  onInvalidate: _invalidateRequest,
                  onTypeChanged: (type) => setState(() {
                    _goods[index].type = type;
                    _invalidateRequest();
                  }),
                  onPickPhoto: () => _addRowPhoto(index),
                  onRemovePhoto: (photoIndex) =>
                      _removeRowPhoto(index, photoIndex),
                  onRemove: _goods.length > 1
                      ? () => _removeGoods(index)
                      : null,
                ),
                const SizedBox(height: 10),
              ],
              if (state.hasError)
                Text(
                  state.errorText ?? '',
                  style: const TextStyle(
                    color: AppColors.coral,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
          validator: (_) => _collectGoods().isEmpty
              ? 'List the goods you are sending — at least one item.'
              : null,
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const ValueKey('customer-add-item'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _goods.length >= _maxItems ? null : _addGoods,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: const Text("Add another item"),
        ),
      ],
    ),
  );

  Widget _shipmentForm() => SectionCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Recipient & delivery', style: AppTheme.sectionTitle),
        const SizedBox(height: 5),
        const Text(
          'Who receives this shipment at the destination?',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const ValueKey('customer-recipient-name'),
          controller: _recipientName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _invalidateRequest(),
          decoration: const InputDecoration(
            labelText: 'Recipient name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 11),
        TextFormField(
          key: const ValueKey('customer-recipient-phone'),
          controller: _recipientPhone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _invalidateRequest(),
          decoration: const InputDecoration(
            labelText: 'Recipient phone',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) {
              return 'Required — we contact them at delivery.';
            }
            if (trimmed.length < 6 || trimmed.length > 40) {
              return 'Enter a phone number (6 – 40 characters).';
            }
            return null;
          },
        ),
        const SizedBox(height: 11),
        TextFormField(
          key: const ValueKey('customer-recipient-address'),
          controller: _recipientAddress,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _invalidateRequest(),
          decoration: const InputDecoration(
            labelText: 'Delivery address',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          maxLines: 2,
          minLines: 1,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Required — tell us where the shipment goes.'
              : null,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey(kGoogleMapsCheckKey),
            onPressed: _recipientAddress.text.trim().isEmpty
                ? null
                : () => _checkAddress(_recipientAddress.text.trim()),
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('Verify on Google Maps'),
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          key: const ValueKey('customer-package-type'),
          initialValue: _packageType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Overall packing',
            prefixIcon: Icon(Icons.inventory_2_outlined),
            helperText: 'How the goods travel — e.g. one barrel plus boxes.',
          ),
          items: [
            for (final type in _customerPackageTypes)
              DropdownMenuItem(value: type.$1, child: Text(type.$2)),
          ],
          onChanged: (value) => setState(() {
            _packageType = value;
            _invalidateRequest();
          }),
          validator: (value) =>
              value == null ? 'Choose the packing type' : null,
        ),
        const SizedBox(height: 11),
        TextFormField(
          key: const ValueKey('customer-package-weight'),
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          textInputAction: TextInputAction.next,
          onChanged: (_) => _invalidateRequest(),
          decoration: const InputDecoration(
            labelText: 'Total weight (kg)',
            prefixIcon: Icon(Icons.scale_outlined),
            helperText: 'Best estimate across all items.',
          ),
          validator: (value) {
            final weight = double.tryParse(value?.trim() ?? '');
            if (weight == null || !weight.isFinite || weight <= 0) {
              return 'Enter a weight greater than 0 kg';
            }
            return null;
          },
        ),
        const SizedBox(height: 11),
        TextFormField(
          key: const ValueKey('customer-shipment-notes'),
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _invalidateRequest(),
          decoration: const InputDecoration(
            labelText: 'Notes for D2F (optional)',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
          maxLines: 3,
          minLines: 1,
        ),
      ],
    ),
  );

  Widget _handoverSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          'How do your goods reach D2F?',
          style: AppTheme.sectionTitle,
        ),
      ),
      _HandoverChoice(
        key: const ValueKey('handover-pickup'),
        title: 'Request pickup',
        tagline: 'Our team collects the goods from your address.',
        icon: Icons.local_shipping_outlined,
        selected: _deliveryMode == DeliveryMode.PICKUP,
        onSelect: () => setState(() {
          _deliveryMode = DeliveryMode.PICKUP;
          _pickupMissingSchedule = false;
          _invalidateRequest();
        }),
      ),
      const SizedBox(height: 10),
      _HandoverChoice(
        key: const ValueKey('handover-dropoff'),
        title: 'Drop off at warehouse',
        tagline: 'Bring the goods to our warehouse — no appointment.',
        icon: Icons.storefront_outlined,
        selected: _deliveryMode == DeliveryMode.DROP_OFF,
        onSelect: () => setState(() {
          _deliveryMode = DeliveryMode.DROP_OFF;
          _invalidateRequest();
        }),
      ),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _deliveryMode == DeliveryMode.PICKUP
            ? _pickupDetails()
            : _dropOffDetails(),
      ),
      const SizedBox(height: 18),
      _reviewSummary(),
      const SizedBox(height: 16),
      _restrictionsSection(),
      const SizedBox(height: 14),
      PrimaryButton(
        key: const ValueKey('customer-create-shipment'),
        label: 'Create shipment request',
        loading: _saving,
        onPressed: _saving || !_hasPhone ? null : _createShipment,
      ),
      if (!_hasPhone) ...[
        const SizedBox(height: 10),
        const Text(
          'Add your phone number in Account — our team needs it to reach '
          'you before submitting the request.',
          style: TextStyle(color: AppColors.coral, fontSize: 11, height: 1.5),
        ),
      ],
    ],
  );

  Widget _pickupDetails() => SectionCard(
    key: const ValueKey('pickup-details'),
    tint: AppColors.coralSoft.withValues(alpha: .45),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              color: AppColors.coral,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Pickup by our team',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
            Text(
              'Pickup notice goes to D2F staff',
              style: AppTheme.caption.copyWith(fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('customer-pickup-address'),
          controller: _pickupAddress,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _invalidateRequest(),
          decoration: const InputDecoration(
            labelText: 'Collection address',
            prefixIcon: Icon(Icons.home_outlined),
            helperText:
                'Street address where our team should collect the goods.',
          ),
          maxLines: 2,
          minLines: 1,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Required for a pickup request.'
              : null,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _pickupAddress.text.trim().isEmpty
                ? null
                : () => _checkAddress(_pickupAddress.text.trim()),
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('Verify on Google Maps'),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          key: const ValueKey('customer-pickup-schedule'),
          onTap: _pickDateTime,
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Preferred pickup date & time',
              prefixIcon: const Icon(Icons.event_available_rounded),
              suffixIcon: const Icon(Icons.edit_calendar_rounded, size: 19),
              errorText: _pickupMissingSchedule
                  ? 'Choose the collection date and time.'
                  : null,
            ),
            child: Text(
              _pickupWhen == null
                  ? 'Choose date & time'
                  : DateFormat('EEE, MMM d · h:mm a').format(_pickupWhen!),
              style: TextStyle(
                color: _pickupWhen == null
                    ? AppColors.textGrey
                    : AppColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Our staff see your request right away, confirm the collection, and '
          'update the status once your items are picked up.',
          style: AppTheme.caption.copyWith(fontSize: 10.5),
        ),
      ],
    ),
  );

  Widget _dropOffDetails() => SectionCard(
    key: const ValueKey('dropoff-details'),
    tint: AppColors.greenSoft.withValues(alpha: .45),
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.storefront_rounded, color: AppColors.green, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Warehouse drop-off',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bring your items to our D2F warehouse in '
                '${_route.origin.split(',').first}. Bring this tracking ID; our '
                'team verifies the goods and updates the status to Received.',
                style: AppTheme.caption.copyWith(fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _restrictionsSection() {
    return Column(
      key: const ValueKey('customer-restrictions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Before you submit', style: AppTheme.sectionTitle),
        ),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: InkWell(
            key: const ValueKey('customer-restrictions-check'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _restrictionsAck = !_restrictionsAck),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  width: 22,
                  child: Checkbox(
                    value: _restrictionsAck,
                    onChanged: (value) =>
                        setState(() => _restrictionsAck = value ?? false),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'I confirm my goods are truthfully described and comply '
                    'with D2F shipping restrictions. Our team verifies the '
                    'packages against this list at collection.',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _shipmentList() {
    if (_loadingParcels) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_parcelsError != null) {
      return SectionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_parcelsError!, style: AppTheme.caption),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadParcels,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_parcels.isEmpty) {
      return SectionCard(
        tint: Colors.white,
        padding: const EdgeInsets.all(18),
        child: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.textGrey),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your shipment requests and tracking IDs will appear here.',
                style: AppTheme.caption,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final parcel in _parcels) ...[
          _CustomerParcelTile(
            parcel: parcel,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CustomerParcelDetailsScreen(parcel: parcel),
              ),
            ),
          ),
          if (parcel != _parcels.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _HandoverChoice extends StatelessWidget {
  final String title;
  final String tagline;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelect;

  const _HandoverChoice({
    super.key,
    required this.title,
    required this.tagline,
    required this.icon,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.blueSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? AppColors.blue : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.subtle,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected ? AppColors.blue : AppColors.textGrey,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tagline,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.blue : AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoodsRow extends StatelessWidget {
  final int index;
  final GoodsDraft draft;
  final VoidCallback onInvalidate;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onPickPhoto;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback? onRemove;

  const _GoodsRow({
    super.key,
    required this.index,
    required this.draft,
    required this.onInvalidate,
    required this.onTypeChanged,
    required this.onPickPhoto,
    required this.onRemovePhoto,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: .8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  key: ValueKey('goods-name-$index'),
                  controller: draft.name,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onInvalidate(),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'Describe package (e.g. clothing box, TV)...',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  key: ValueKey('goods-qty-$index'),
                  controller: draft.quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}')),
                  ],
                  textAlign: TextAlign.end,
                  onChanged: (_) => onInvalidate(),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'Qty',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              if (onRemove != null)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    tooltip: 'Remove item',
                    key: ValueKey('goods-remove-$index'),
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.coral,
                      size: 20,
                    ),
                    onPressed: onRemove,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // What kind of physical package is this, and how large? Staff count
          // and label each one, so the type and L×W×H reading travel with it.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('goods-type-$index'),
                isExpanded: true,
                initialValue: draft.type,
                isDense: true,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  hintText: 'Type',
                  hintStyle: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGrey,
                  ),
                ),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: AppColors.navy,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                items: [
                  for (final (value, label) in _customerPackageTypes)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (value) {
                  if (value != null && value != draft.type) {
                    onTypeChanged(value);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('goods-size-$index'),
                controller: draft.size,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.×x ]')),
                ],
                onChanged: (_) => onInvalidate(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  hintText: 'Size L×W×H cm — e.g. 60×40×45',
                  hintStyle: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textGrey,
                  ),
                ),
                style: const TextStyle(color: AppColors.navy, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('goods-details-$index'),
            controller: draft.details,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => onInvalidate(),
            decoration: const InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'Optional short description for our team...',
              hintStyle: TextStyle(fontSize: 11.5, color: AppColors.textGrey),
            ),
            style: const TextStyle(fontSize: 11.5, color: AppColors.textGrey),
          ),
          const SizedBox(height: 10),
          // Optional photos of this package, compressed automatically and
          // linked to exactly this package at upload time.
          _rowPhotoStrip(context, index: index, photos: draft.photos),
        ],
      ),
    );
  }

  Widget _rowPhotoStrip(
    BuildContext context, {
    required int index,
    required List<PhotoDraft> photos,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (
          var photoIndex = 0;
          photoIndex < photos.length;
          photoIndex += 1
        ) ...[
          Stack(
            children: [
              Container(
                key: ValueKey('goods-photo-$index-$photoIndex'),
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    photos[photoIndex].bytes,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    tooltip: 'Remove photo',
                    key: ValueKey('goods-photo-remove-$index-$photoIndex'),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.cancel_rounded,
                      color: AppColors.coral.withValues(alpha: .9),
                      size: 20,
                    ),
                    onPressed: () => onRemovePhoto(photoIndex),
                  ),
                ),
              ),
            ],
          ),
        ],
        InkWell(
          key: ValueKey('goods-photo-add-$index'),
          borderRadius: BorderRadius.circular(12),
          onTap: onPickPhoto,
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.border,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.surface,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_a_photo_outlined,
                  size: 17,
                  color: AppColors.navy,
                ),
                SizedBox(width: 6),
                Text(
                  'Photo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomerParcelTile extends StatelessWidget {
  final Parcel parcel;
  final VoidCallback onTap;
  const _CustomerParcelTile({required this.parcel, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      key: ValueKey('customer-parcel-${parcel.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: parcel.deliveryMode == DeliveryMode.PICKUP
                  ? const Icon(
                      Icons.local_shipping_outlined,
                      color: AppColors.navy,
                    )
                  : const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.navy,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parcel.trackingId,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${parcel.origin} → ${parcel.destination}'
                    ' · ${parcel.deliveryMode.shortLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontSize: 10),
                  ),
                  const SizedBox(height: 7),
                  StatusChip(status: parcel.status, short: true),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textGrey),
          ],
        ),
      ),
    ),
  );
}

class CustomerParcelDetailsScreen extends StatelessWidget {
  final Parcel parcel;
  final bool justCreated;
  const CustomerParcelDetailsScreen({
    super.key,
    required this.parcel,
    this.justCreated = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = justCreated ? 'Request submitted' : 'Shipment details';
    return Scaffold(
      backgroundColor: authCanvas,
      appBar: AppBar(
        backgroundColor: authCanvas,
        foregroundColor: AppColors.navy,
        title: Text(title, style: AppTheme.sectionTitle),
        centerTitle: false,
      ),
      body: ListView(
        padding: AppSpacing.pageInsets,
        children: [
          if (justCreated) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Request created.',
                          style: AppTheme.display.copyWith(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your tracking ID is ready. Our team reviews your goods and updates the status.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.flight_takeoff_rounded,
                    color: AppColors.gold,
                    size: 56,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          SectionCard(
            tint: AppColors.blueSoft,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TRACKING ID',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy tracking ID',
                      onPressed: () =>
                          copyToClipboard(context, parcel.trackingId),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
                Text(
                  parcel.trackingId,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 12),
                QrImageView(
                  data: parcel.trackingId,
                  version: QrVersions.auto,
                  size: 150,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.navy,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    color: AppColors.navy,
                    dataModuleShape: QrDataModuleShape.square,
                  ),
                ),
                const SizedBox(height: 8),
                StatusChip(status: parcel.status),
                const SizedBox(height: 10),
                Text(
                  statusHeadline(parcel.status),
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _goodsCard(),
          const SizedBox(height: 18),
          _pickupCard(),
          const SizedBox(height: 18),
          const Text('Shipment route', style: AppTheme.sectionTitle),
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _detailRow('From', parcel.origin),
                const Divider(height: 22),
                _detailRow('To', parcel.destination),
                const Divider(height: 22),
                _detailRow(
                  'Method',
                  '${parcel.method.label} · ${parcel.method.tagline}',
                ),
                const Divider(height: 22),
                if (parcel.awbNumber != null) ...[
                  _detailRow('Air Waybill', parcel.awbNumber!),
                  const Divider(height: 22),
                ],
                if (parcel.airline != null) ...[
                  _detailRow('Airline', parcel.airline!),
                  const Divider(height: 22),
                ],
                _detailRow('Packing', parcel.packageTypeLabel),
                const Divider(height: 22),
                _detailRow('Total weight', '${parcel.weightKg} kg'),
                const Divider(height: 22),
                _detailRow('Recipient', parcel.recipientName),
                if (parcel.recipientPhone?.isNotEmpty ?? false) ...[
                  const Divider(height: 22),
                  _detailRow('Recipient phone', parcel.recipientPhone!),
                ],
                if (parcel.recipientAddress?.isNotEmpty ?? false) ...[
                  const Divider(height: 22),
                  _detailRow('Delivery address', parcel.recipientAddress!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _photosCard(context),
          const SizedBox(height: 18),
          const Text('Progress', style: AppTheme.sectionTitle),
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: TrackingTimeline(
              events: parcel.events,
              currentStatus: parcel.status,
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'View my shipments',
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 10),
          OutlineButton2(
            label: justCreated ? 'Done' : 'Back',
            onPressed: () => Navigator.pop(context, false),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _goodsCard() {
    if (parcel.items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Goods in this shipment',
                style: AppTheme.sectionTitle,
              ),
            ),
            Text(
              parcel.totalPieces > 0
                  ? '${parcel.items.length} lines · ${parcel.totalPieces} pieces'
                  : '${parcel.items.length} lines',
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // A partial collection is always called out — the customer sees
        // exactly which declared packages the crew did not take.
        if (parcel.hasCollectionDiscrepancy)
          Container(
            key: const ValueKey('customer-collection-note'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.coralSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.report_problem_rounded,
                  color: AppColors.coral,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Collected ${parcel.items.length - parcel.missedItems.length} '
                    'of ${parcel.items.length} packages. The packages listed '
                    'below are recorded as not collected.',
                    style: const TextStyle(
                      color: AppColors.coral,
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (final item in parcel.items) ...[
                GoodsItemTile(
                  key: ValueKey('customer-item-${item.position}'),
                  item: item,
                  itemCount: parcel.items.length,
                ),
                if (item != parcel.items.last) const Divider(height: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pickupCard() {
    final isPickup = parcel.deliveryMode == DeliveryMode.PICKUP;
    final style = TextStyle(
      color: isPickup ? AppColors.blue : AppColors.green,
      fontSize: 15,
      height: 1.2,
    );
    return SectionCard(
      padding: const EdgeInsets.all(14),
      tint: isPickup ? AppColors.blueSoft : AppColors.greenSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPickup ? Icons.local_shipping_rounded : Icons.storefront_rounded,
            color: isPickup ? AppColors.blue : AppColors.green,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPickup ? 'D2F pickup' : 'Warehouse drop-off',
                  style: style.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                if (isPickup) ...[
                  if (parcel.pickupAddress?.isNotEmpty ?? false)
                    Text(
                      'Collection · ${parcel.pickupAddress}',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (parcel.pickupScheduledAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Preferred time: ${DateFormat('EEE, MMM d · h:mm a').format(parcel.pickupScheduledAt!)}',
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Our team will confirm the collection and keep the status '
                      'updated here.',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                ] else
                  const Text(
                    'Bring your items to the D2F warehouse. Our team verifies '
                    'them on arrival.',
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photosCard(BuildContext context) {
    if (parcel.images.isEmpty) return const SizedBox.shrink();
    // Photos either document the whole shipment or one declared package;
    // per-package shots are captioned with that package so the crew can
    // match the photo to the item they counted.
    final shipmentPhotos = parcel.photosFor(null);
    final sections = <Widget>[];
    for (final item in parcel.items) {
      final photos = parcel.photosFor(item.id);
      if (photos.isEmpty) continue;
      sections.add(
        Padding(
          key: ValueKey('customer-item-photos-${item.position}'),
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.typeLabel} ${item.position + 1} of ${parcel.items.length} — photos',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              GoodsPhotoGallery(
                images: photos,
                compact: true,
                loadBytes: (image) =>
                    Api.I.customerParcelImageBytes(parcel.id, image.id),
              ),
            ],
          ),
        ),
      );
    }
    final hasShipmentOnly = shipmentPhotos.isNotEmpty && sections.isNotEmpty;
    final hasPackagePhotos = sections.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Your goods photos', style: AppTheme.sectionTitle),
            ),
            Text(
              '${parcel.images.length}',
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SectionCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            key: const ValueKey('customer-detail-photos'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shipmentPhotos.isNotEmpty) ...[
                if (hasShipmentOnly)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Whole shipment',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                GoodsPhotoGallery(
                  images: shipmentPhotos,
                  compact: !hasShipmentOnly && hasPackagePhotos,
                  loadBytes: (image) =>
                      Api.I.customerParcelImageBytes(parcel.id, image.id),
                ),
              ],
              ...sections,
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 78,
        child: Text(label, style: AppTheme.caption.copyWith(fontSize: 11)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}
