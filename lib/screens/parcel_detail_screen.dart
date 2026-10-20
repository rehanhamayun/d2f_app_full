import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'label_preview_screen.dart';
import '../widgets/timeline.dart';
import 'update_status_screen.dart';
import '../services/parcel_report.dart';

/// Parcel Details (design screen 9): header status card + segmented tabs
/// Overview / Tracking / Details + "Update Status" staff action. The
/// Tracking tab carries a "Download parcel details" PDF action.
class ParcelDetailScreen extends StatefulWidget {
  final String parcelId; // UUID or public tracking ID

  const ParcelDetailScreen({super.key, required this.parcelId});

  @override
  State<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends State<ParcelDetailScreen> {
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
      final p = await Api.I.parcelDetail(widget.parcelId);
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
    final refreshedAt = DateFormat('MMMM d, yyyy').format(parcel.updatedAt);

    return DefaultTabController(
      length: 3,
      child: RefreshIndicator(
        color: AppColors.coral,
        onRefresh: _fetch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF173F6D), Color(0xFF0D294A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFF31567D)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TRACKING NUMBER',
                    style: TextStyle(
                      color: Color(0xFFBFD0E5),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          parcel.trackingId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => copyToClipboard(
                          context,
                          parcel.trackingId,
                          message: 'Tracking number copied',
                        ),
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(status: parcel.status),
                      Text(
                        statusHeadline(parcel.status),
                        style: AppTheme.body.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                        color: Color(0xFFBFD0E5),
                      ),
                      const SizedBox(width: 5),
                      Text('Updated on $refreshedAt', style: AppTheme.caption),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Segmented tabs — navy capsule on a soft track, brand-colored icons.
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF2F9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                onTap: (index) => setState(() => _tab = index),
                indicator: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: .35),
                      offset: const Offset(0, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.navy,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
                indicatorPadding: const EdgeInsets.symmetric(vertical: 2),
                tabs: const [
                  Tab(
                    height: 48,
                    text: 'Overview',
                    icon: Icon(
                      Icons.inventory_2_rounded,
                      size: 17,
                      color: AppColors.coral,
                    ),
                  ),
                  Tab(
                    height: 48,
                    text: 'Tracking',
                    icon: Icon(
                      Icons.place_rounded,
                      size: 17,
                      color: AppColors.blue,
                    ),
                  ),
                  Tab(
                    height: 48,
                    text: 'Details',
                    icon: Icon(
                      Icons.list_alt_rounded,
                      size: 17,
                      color: AppColors.teal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

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
        const Text('Shipment Information', style: AppTheme.sectionTitle),
        const SizedBox(height: 4),
        const Text(
          'Swipe to see every record for this shipment.',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 10),
        // Six full-detail cards in one horizontal rail.
        SizedBox(
          height: 168,
          child: ListView.separated(
            physics: const BouncingScrollPhysics(
              decelerationRate: ScrollDecelerationRate.fast,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: _shipmentCards(parcel).length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _shipmentCards(parcel)[i],
          ),
        ),
        const SizedBox(height: 20),
        if (canUpdate)
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
        sub: 'Internal ref ${parcel.id.substring(0, 8)}…',
      ),
    ];
  }

  Widget _tracking(Parcel parcel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tracking Timeline', style: AppTheme.sectionTitle),
        const SizedBox(height: 4),
        Text(
          'Recorded updates from your parcel’s journey.',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 16),
        SectionCard(
          tint: AppColors.tealSoft,
          child: TrackingTimeline(
            events: parcel.events,
            currentStatus: parcel.status,
          ),
        ),
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
              _row('Method', parcel.method.label),
              _row('Package', parcel.packageTypeLabel),
              _row('Weight', '${parcel.weightKg} kg'),
              if (parcel.notes != null && parcel.notes!.isNotEmpty)
                _row('Notes', parcel.notes!),
              _row('Registered', df.format(parcel.createdAt)),
              _row('Last update', df.format(parcel.updatedAt)),
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
            width: 130,
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

/// Wide horizontal info card with its own brand tint — full text, no cuts.
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
  Widget build(BuildContext context) {
    return Container(
      width: 258,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, tint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color.lerp(tint, AppColors.blue, .16)!),
        boxShadow: [
          BoxShadow(
            color: Color.lerp(tint, AppColors.navy, .16)!,
            offset: const Offset(0, 4),
            blurRadius: 0,
          ),
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .05),
            offset: const Offset(0, 10),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: fg.withValues(alpha: .35),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, color: fg, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: fg,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Full value: wraps instead of ellipsising.
          Text(
            value,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Navy gradient download action styled like the primary CTA bar area.
class _DownloadReportButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool busy;
  const _DownloadReportButton({required this.onPressed, required this.busy});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .45),
            offset: const Offset(0, 5),
            blurRadius: 0,
          ),
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .20),
            offset: const Offset(0, 14),
            blurRadius: 26,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onPressed,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.navy, Color(0xFF16305E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(9),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.gold,
                            ),
                          )
                        : const Icon(
                            Icons.file_download_rounded,
                            color: AppColors.gold,
                            size: 23,
                          ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          busy ? 'Building PDF...' : 'Download parcel details',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Barcode, codes and full tracking history',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .72),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!busy)
                    const Icon(
                      Icons.download_done_rounded,
                      color: AppColors.gold,
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
