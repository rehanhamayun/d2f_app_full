import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'parcel_detail_screen.dart';

/// Parcels list (design screen 8) — search, status filter chips, cards.
class ActivityScreen extends StatefulWidget {
  final Future<List<Parcel>> Function({String? q})? loadParcels;
  final Future<Map<String, int>> Function()? loadStats;
  final Future<ParcelBoardResult> Function({String? q})? loadBoard;
  const ActivityScreen({
    super.key,
    this.loadParcels,
    this.loadStats,
    this.loadBoard,
  });

  @override
  State<ActivityScreen> createState() => ActivityScreenState();
}

class ActivityScreenState extends State<ActivityScreen> {
  final _search = TextEditingController();

  static const chips = <(String, String)>[
    ('ALL', 'All'),
    ('REQUESTED', 'Requested'),
    ('PICKUP_SCHEDULED', 'Scheduled'),
    ('PICKED_UP', 'Picked Up'),
    ('RECEIVED', 'Received'),
    ('PROCESSING', 'Processing'),
    ('IN_TRANSIT', 'In Transit'),
    ('ARRIVED_LOME', 'Arrived Lomé'),
    ('ARRIVED_DESTINATION', 'Arrived'),
    ('READY_FOR_PICKUP', 'Ready'),
    ('RELEASED', 'Released'),
    ('DELIVERED', 'Delivered'),
  ];

  String _chip = 'ALL';
  String _query = '';
  List<Parcel> _parcels = [];
  Map<String, int> _counts = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    setState(() {
      _loading = _parcels.isEmpty;
      _error = null;
    });
    try {
      final q = _query.isEmpty ? null : _query;
      if (widget.loadBoard != null) {
        final board = await widget.loadBoard!(q: q);
        if (!mounted) return;
        setState(() {
          _parcels = board.parcels;
          _counts = board.counts;
          _loading = false;
        });
        return;
      }
      // Injected loaders are retained for widget tests and previews.
      if (widget.loadParcels != null || widget.loadStats != null) {
        final results = await Future.wait([
          widget.loadParcels?.call(q: q) ?? Api.I.parcels(q: q),
          widget.loadStats?.call() ?? Api.I.parcelStats(),
        ]);
        if (!mounted) return;
        setState(() {
          _parcels = results[0] as List<Parcel>;
          _counts = results[1] as Map<String, int>;
          _loading = false;
        });
        return;
      }
      // One server snapshot keeps "All (n)" and every status chip in sync with
      // the rows rendered below them.
      final board = await Api.I.parcelBoard(q: q);
      if (!mounted) return;
      setState(() {
        _parcels = board.parcels;
        _counts = board.counts;
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

  void _submitSearch([String? value]) {
    setState(() => _query = (value ?? _search.text).trim());
    _fetch();
  }

  int _countFor(String chip) {
    if (chip == 'ALL') {
      return _counts.values.fold(0, (a, b) => a + b);
    }
    return _counts[chip] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _chip == 'ALL'
        ? _parcels
        : _parcels.where((p) => p.status == _chip).toList();

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: AppColors.coral,
              onRefresh: _fetch,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  const D2FHomeHeader(),
                  const SizedBox(height: 10),
                  const ScreenIntro(
                    title: 'Parcels',
                    subtitle: 'Track and manage your shipments.',
                  ),
                  const SizedBox(height: 16),

                  D2FSearchField(
                    hint: 'Enter tracking number',
                    controller: _search,
                    onSubmit: (_) => _submitSearch(),
                  ),
                  const SizedBox(height: 14),

                  // Filter chips
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: chips.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final (key, label) = chips[i];
                        final selected = _chip == key;
                        return GestureDetector(
                          onTap: () => setState(() => _chip = key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.blue : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: selected
                                  ? null
                                  : Border.all(color: AppColors.border),
                            ),
                            child: Center(
                              child: Text(
                                '$label (${_countFor(key)})',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AppColors.navy,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.coral,
                        ),
                      ),
                    )
                  else if (_error != null)
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load parcels',
                      subtitle: _error!,
                    )
                  else if (visible.isEmpty)
                    EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: _query.isEmpty ? 'No parcels yet' : 'No matches',
                      subtitle: _query.isEmpty
                          ? 'Registered parcels will appear here. Use the Ship tab to add the first one.'
                          : 'Try a different tracking number or name.',
                    )
                  else
                    ...visible.map(_parcelCard),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _parcelCard(Parcel p) {
    final v = StatusVisual.of(p.status);
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ParcelDetailScreen(parcelId: p.id)),
        );
        _fetch();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 54,
              decoration: BoxDecoration(
                color: v.tileBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_iconFor(p), color: v.tileIcon, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.trackingId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        p.destinationFlag,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          p.destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StatusChip(
                    status: p.status,
                    short: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 10,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          DateFormat('MMM d, yyyy • h:mm a')
                              .format(p.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textGrey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(Parcel p) => switch (p.status) {
    'REQUESTED' => Icons.assignment_outlined,
    'RECEIVED' => Icons.inventory_2_outlined,
    'PROCESSING' => Icons.settings_outlined,
    'IN_TRANSIT' => Icons.local_shipping_outlined,
    'ARRIVED_LOME' => Icons.anchor_rounded,
    'READY_FOR_PICKUP' => Icons.storefront_rounded,
    'DELIVERED' => Icons.check_circle_outline_rounded,
    _ => Icons.inventory_2_outlined,
  };
}
