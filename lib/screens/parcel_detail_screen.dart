import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';
import '../widgets/goods_gallery.dart';
import '../widgets/reference_widgets.dart';
import 'label_preview_screen.dart';
import '../widgets/timeline.dart';
import 'update_status_screen.dart';
import 'container_detail_screen.dart';
import '../services/parcel_report.dart';

/// Parcel Details (design screen 9): header status card + segmented tabs
/// Overview / Tracking / Details + "Update Status" staff action. The
/// Tracking tab carries a "Download parcel details" PDF action.
class ParcelDetailScreen extends ConsumerStatefulWidget {
  final String parcelId; // UUID, shipment tracking ID, or package code
  final Future<Parcel> Function(String)? loadParcel;

  const ParcelDetailScreen({
    super.key,
    required this.parcelId,
    this.loadParcel,
  });

  @override
  ConsumerState<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends ConsumerState<ParcelDetailScreen> {
  int _tab = 0;
  Parcel? _parcel;
  String? _error;
  bool _loading = true;
  bool _savingReport = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = _parcel == null;
      _error = null;
    });
    try {
      final p =
          await (widget.loadParcel?.call(widget.parcelId) ??
              Api.I.parcelDetail(widget.parcelId));
      if (!mounted) return;
      setState(() {
        _parcel = p;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final parcel = _parcel;

    return Scaffold(
      appBar: D2FAppBar(
        title: const Text('Parcel Details'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (parcel != null)
            IconButton(
              tooltip: 'Shipping label',
              icon: const Icon(Icons.description_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LabelPreviewScreen(parcel: parcel),
                ),
              ),
            ),
          if (parcel != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => copyToClipboard(
                context,
                parcel.trackingId,
                message: 'Tracking number copied',
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.coral),
            )
          : _error != null
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load parcel',
              subtitle: _error!,
            )
          : parcel == null
          ? const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Not found',
              subtitle: 'This parcel does not exist.',
            )
          : _body(parcel),
    );
  }

  Widget _body(Parcel parcel) {
    return DefaultTabController(
      length: 3,
      child: RefreshIndicator(
        color: AppColors.coral,
        onRefresh: _fetch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            ParcelSummaryCard(
              trackingId: parcel.trackingId,
              status: parcel.status,
              method: parcel.method.label,
              onCopy: () => copyToClipboard(
                context,
                parcel.trackingId,
                message: 'Tracking number copied',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(13),
              ),
              child: TabBar(
                onTap: (index) => setState(() => _tab = index),
                indicator: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.navy,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                tabs: const [
                  Tab(height: 44, text: 'Overview'),
                  Tab(height: 44, text: 'Tracking'),
                  Tab(height: 44, text: 'Details'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Render the selected section in the same scroll view.
            if (_tab == 0) _overview(parcel),
            if (_tab == 1) _tracking(parcel),
            if (_tab == 2) _details(parcel),
          ],
        ),
      ),
    );
  }

  /// Each tab has a single scrolling surface with pull-to-refresh.
  Widget _overview(Parcel parcel) {
    final canUpdate = parcel.status != 'DELIVERED';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          tint: AppColors.blueSoft,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.blue,
                child: const Icon(
                  Icons.flight_takeoff_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${parcel.origin}\n→ ${parcel.destination}',
                  style: AppTheme.body.copyWith(
                    fontSize: 12.5,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _handoverCard(parcel),
        const SizedBox(height: 20),
        _shipmentGrid(parcel),
        const SizedBox(height: 20),
        if (parcel.containerManaged)
          SectionCard(
            tint: AppColors.blueSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Container: ${parcel.containerCode ?? 'Assigned'}',
                  style: AppTheme.sectionTitle,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Departure and arrival are managed together from the container.',
                  style: AppTheme.caption,
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContainerDetailScreen(
                          containerId: parcel.containerId!,
                        ),
                      ),
                    );
                    if (mounted) _fetch();
                  },
                  child: const Text('Open container'),
                ),
              ],
            ),
          )
        else if (canUpdate)
          PrimaryButton(
            label: 'Update Status',
            onPressed: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => UpdateStatusScreen(parcel: parcel),
                ),
              );
              if (updated == true) _fetch();
            },
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_rounded, color: AppColors.green),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This parcel is delivered — lifecycle complete.',
                    style: TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// How the goods arrive at D2F — visible to staff at the top of the record.
  Widget _handoverCard(Parcel parcel) {
    final isPickup = parcel.deliveryMode == DeliveryMode.PICKUP;
    final scheduled = parcel.pickupScheduledAt == null
        ? ''
        : ' · ${DateFormat('EEE, MMM d · h:mm a').format(parcel.pickupScheduledAt!.toLocal())}';
    return SectionCard(
      tint: isPickup ? AppColors.blueSoft : AppColors.greenSoft,
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white,
            child: Icon(
              isPickup
                  ? Icons.local_shipping_rounded
                  : Icons.storefront_rounded,
              color: isPickup ? AppColors.blue : AppColors.green,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPickup ? 'D2F pickup' : 'Warehouse drop-off',
                  style: AppTheme.body.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPickup
                      ? 'Scheduled collection from the customer$scheduled'
                      : 'Customer brings the goods to the intake facility',
                  style: AppTheme.caption.copyWith(
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                if (isPickup && (parcel.pickupAddress?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      parcel.pickupAddress!,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shipmentGrid(Parcel parcel) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Shipment Information', style: AppTheme.sectionTitle),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, c) {
          final columns =
              c.maxWidth < 270 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.4
              ? 1
              : 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final card in _shipmentCards(parcel))
                SizedBox(
                  width: (c.maxWidth - (columns - 1) * 10) / columns,
                  child: card,
                ),
            ],
          );
        },
      ),
    ],
  );

  /// The six shipment-information records, each on its own tinted card with
  /// full, un-truncated text.
  List<Widget> _shipmentCards(Parcel parcel) {
    final df = DateFormat('MMM d, yyyy');
    return [
      _ShipmentCard(
        label: 'From (Customer)',
        icon: Icons.person_rounded,
        tint: AppColors.coralSoft,
        fg: AppColors.coral,
        value: parcel.customer?.displayName ?? '—',
        sub: parcel.customer?.email ?? parcel.origin,
      ),
      _ShipmentCard(
        label: 'To (Recipient)',
        icon: Icons.groups_rounded,
        tint: AppColors.blueSoft,
        fg: AppColors.blue,
        value: parcel.recipientName,
        sub: parcel.recipientPhone ?? 'No phone on file',
      ),
      _ShipmentCard(
        label: 'Destination',
        icon: Icons.place_rounded,
        tint: AppColors.goldSoft,
        fg: const Color(0xFF9A7100),
        value: parcel.destination,
        sub: parcel.destinationFlag,
      ),
      _ShipmentCard(
        label: 'Shipping Method',
        icon: parcel.method.icon,
        tint: AppColors.indigoSoft,
        fg: AppColors.indigo,
        value: parcel.method.label,
        sub: parcel.method.tagline,
      ),
      _ShipmentCard(
        label: 'Package Weight',
        icon: Icons.scale_rounded,
        tint: AppColors.tealSoft,
        fg: AppColors.teal,
        value: '${parcel.weightKg} kg',
        sub: 'Gross weight at intake',
      ),
      _ShipmentCard(
        label: 'Package Type',
        icon: Icons.inventory_2_rounded,
        tint: AppColors.greenSoft,
        fg: AppColors.green,
        value: parcel.packageTypeLabel,
        sub: parcel.notes == null || parcel.notes!.isEmpty
            ? 'No notes attached'
            : 'Notes: ${parcel.notes}',
      ),
      _ShipmentCard(
        label: 'Registered On',
        icon: Icons.event_available_rounded,
        tint: AppColors.coralSoft,
        fg: AppColors.coral,
        value: df.format(parcel.createdAt),
        sub: 'Internal ref ${parcel.id}',
      ),
    ];
  }

  Widget _tracking(Parcel parcel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tracking Timeline', style: AppTheme.sectionTitle),
              const SizedBox(height: 5),
              const Text(
                'Recorded updates from your parcel’s journey.',
                style: AppTheme.caption,
              ),
              const SizedBox(height: 20),
              TrackingTimeline(
                events: parcel.events,
                currentStatus: parcel.status,
                canEditNote: _canCorrectNote,
                onEditNote: (event) => _editNote(parcel, event),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _shipmentGrid(parcel),
        const SizedBox(height: 20),
        // Download action pinned across the page width (bottom-bar spot).
        _DownloadReportButton(
          busy: _savingReport,
          onPressed: () => _downloadDetails(parcel),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Generates ${ParcelReport.filename(parcel)} — details and full history.',
            style: AppTheme.caption.copyWith(fontSize: 11.5),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  bool _canCorrectNote(TrackingEvent event) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (user == null || !user.isStaff) return false;
    return user.role == UserRole.ADMIN || event.actorId == user.id;
  }

  Future<void> _editNote(Parcel parcel, TrackingEvent event) async {
    final controller = TextEditingController(text: event.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Correct operational note',
          style: AppTheme.sectionTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The event, actor, time and location stay unchanged. The correction is recorded in the audit trail.',
                style: AppTheme.caption.copyWith(height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 1000,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Operational note',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save correction'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;
    try {
      await Api.I.correctParcelNote(parcel.id, event.id, note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Operational note corrected.')),
      );
      await _fetch();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _downloadDetails(Parcel parcel) async {
    if (_savingReport) return;
    setState(() => _savingReport = true);
    try {
      final saved = await ParcelReport.save(parcel);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Parcel details saved as ${ParcelReport.filename(parcel)}'
                : 'Download cancelled',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate the details PDF. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingReport = false);
    }
  }

  Widget _details(Parcel parcel) {
    final df = DateFormat('MMM d, yyyy • h:mm a');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Full Details', style: AppTheme.sectionTitle),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Tracking ID', parcel.trackingId),
              _row('Internal ID', parcel.id),
              _row(
                'Customer',
                parcel.customer?.displayName ?? parcel.customerId,
              ),
              if (parcel.customer?.email != null)
                _row('Customer email', parcel.customer!.email!),
              if (parcel.customer?.phone != null)
                _row('Customer phone', parcel.customer!.phone!),
              _row('Recipient', parcel.recipientName),
              if (parcel.recipientPhone != null)
                _row('Recipient phone', parcel.recipientPhone!),
              if (parcel.recipientAddress != null)
                _row('Recipient address', parcel.recipientAddress!),
              _row('Route', '${parcel.origin} → ${parcel.destination}'),
              _row(
                'Handover',
                parcel.deliveryMode == DeliveryMode.PICKUP
                    ? 'D2F pickup'
                    : 'Warehouse drop-off',
              ),
              if (parcel.deliveryMode == DeliveryMode.PICKUP) ...[
                if (parcel.pickupAddress != null &&
                    parcel.pickupAddress!.isNotEmpty)
                  _row('Collection address', parcel.pickupAddress!),
                if (parcel.pickupScheduledAt != null)
                  _row(
                    'Pickup scheduled',
                    df.format(parcel.pickupScheduledAt!.toLocal()),
                  ),
              ],
              _row('Method', parcel.method.label),
              _row('Package', parcel.packageTypeLabel),
              _row(
                'Weight',
                parcel.totalPieces > 0
                    ? '${parcel.weightKg} kg · ${parcel.totalPieces} pieces'
                    : '${parcel.weightKg} kg',
              ),
              if (parcel.notes != null && parcel.notes!.isNotEmpty)
                _row('Notes', parcel.notes!),
              _row('Registered', df.format(parcel.createdAt)),
              _row('Last update', df.format(parcel.updatedAt)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _goodsCard(parcel),
        const SizedBox(height: 20),
        _photosCard(parcel),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _goodsCard(Parcel parcel) {
    if (parcel.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              '${parcel.items.length} lines · ${parcel.totalPieces} pieces',
              style: AppTheme.caption.copyWith(fontSize: 10.5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Staff see the same collection discrepancy customers see: a package
        // the crew could not take stays visible until it reaches the hub.
        if (parcel.hasCollectionDiscrepancy)
          Container(
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
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Collected ${parcel.items.length - parcel.missedItems.length} '
                    'of ${parcel.items.length} packages at the pickup. '
                    'Missing items are marked below.',
                    style: const TextStyle(
                      color: AppColors.coral,
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in parcel.items) ...[
                if (item.packageCode == widget.parcelId)
                  const Text('Scanned package', style: AppTheme.sectionTitle),
                GoodsItemTile(
                  key: ValueKey('staff-item-${item.position}'),
                  item: item,
                  itemCount: parcel.items.length,
                ),
                if (item != parcel.items.last) const Divider(height: 18),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _photosCard(Parcel parcel) {
    if (parcel.images.isEmpty) return const SizedBox.shrink();
    // Photos grouped by the package they document; per-package shots carry
    // the package caption so staff can match photos to counted items.
    final shipmentPhotos = parcel.photosFor(null);
    final sections = <Widget>[];
    for (final item in parcel.items) {
      final photos = parcel.photosFor(item.id);
      if (photos.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.name} (${item.typeLabel} ${item.position + 1} of ${parcel.items.length})',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              GoodsPhotoGallery(
                images: photos,
                compact: true,
                loadBytes: (image) =>
                    Api.I.parcelImageBytes(parcel.id, image.id),
              ),
            ],
          ),
        ),
      );
    }
    final hasShipmentOnly = shipmentPhotos.isNotEmpty && sections.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Goods photos', style: AppTheme.sectionTitle),
            ),
            Text(
              '${parcel.images.length}',
              style: AppTheme.caption.copyWith(fontSize: 10.5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SectionCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shipmentPhotos.isNotEmpty) ...[
                if (hasShipmentOnly)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Shipment as a whole',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                GoodsPhotoGallery(
                  images: shipmentPhotos,
                  compact: sections.isNotEmpty,
                  loadBytes: (image) =>
                      Api.I.parcelImageBytes(parcel.id, image.id),
                ),
              ],
              ...sections,
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 360 ? 96 : 130,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reference-style pastel information grid, with complete wrapping values.
class _ShipmentCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color tint, fg;
  const _ShipmentCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.tint,
    required this.fg,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.navy, size: 23),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 10,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _DownloadReportButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool busy;
  const _DownloadReportButton({required this.onPressed, required this.busy});
  @override
  Widget build(BuildContext context) => PrimaryButton(
    label: busy ? 'Building PDF…' : 'Download parcel details',
    onPressed: onPressed,
    loading: busy,
  );
}
