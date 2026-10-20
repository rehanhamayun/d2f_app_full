import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'label_preview_screen.dart';
import '../widgets/timeline.dart';
import 'update_status_screen.dart';

/// Parcel Details (design screen 9): header status card + tabs
/// Overview / Tracking / Details + "Update Status" staff action.
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

            // Tabs
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                onTap: (index) => setState(() => _tab = index),
                indicator: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(14),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.navy,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                indicatorPadding: const EdgeInsets.all(4),
                tabs: const [
                  Tab(
                    text: 'Overview',
                    icon: Icon(Icons.inventory_2_rounded, size: 18),
                  ),
                  Tab(
                    text: 'Tracking',
                    icon: Icon(Icons.place_rounded, size: 18),
                  ),
                  Tab(
                    text: 'Details',
                    icon: Icon(Icons.list_alt_rounded, size: 18),
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
          child: Row(
            children: [
              const Icon(Icons.flight_takeoff_rounded, color: AppColors.coral),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${parcel.origin} → ${parcel.destination}',
                  style: AppTheme.body.copyWith(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Shipment Information', style: AppTheme.sectionTitle),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InfoTile(
                icon: Icons.person_rounded,
                bg: AppColors.coralSoft,
                iconColor: AppColors.coral,
                label: 'From (Customer)',
                value: parcel.customer?.displayName ?? '—',
                sub: parcel.origin,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InfoTile(
                icon: Icons.groups_rounded,
                bg: AppColors.blueSoft,
                iconColor: AppColors.blue,
                label: 'To (Recipient)',
                value: parcel.recipientName,
                sub: parcel.recipientPhone ?? '',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InfoTile(
                icon: Icons.place_rounded,
                bg: AppColors.goldSoft,
                iconColor: AppColors.gold,
                label: 'Destination',
                value: parcel.destination,
                sub: parcel.destinationFlag,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InfoTile(
                icon: parcel.method.icon,
                bg: AppColors.coralSoft,
                iconColor: AppColors.coral,
                label: 'Shipping Method',
                value: parcel.method.label,
                sub: parcel.method.tagline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InfoTile(
                icon: Icons.scale_rounded,
                bg: AppColors.blueSoft,
                iconColor: AppColors.blue,
                label: 'Package Weight',
                value: '${parcel.weightKg} kg',
                sub: parcel.packageTypeLabel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InfoTile(
                icon: Icons.inventory_2_rounded,
                bg: AppColors.greenSoft,
                iconColor: AppColors.green,
                label: 'Package Type',
                value: parcel.packageTypeLabel,
                sub: parcel.notes == null || parcel.notes!.isEmpty
                    ? 'No notes'
                    : 'Has notes',
              ),
            ),
          ],
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
      ],
    );
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
