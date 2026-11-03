import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../screens/connect_screen.dart';
import '../screens/customer_shipment_screen.dart';
import 'common.dart';

/// The authenticated customer's complete shipment history. Public tracking
/// lookup remains available separately for a tracking number entered by hand.
class CustomerTrackingHistory extends StatefulWidget {
  final Future<List<Parcel>> Function()? loadParcels;
  const CustomerTrackingHistory({super.key, this.loadParcels});

  @override
  State<CustomerTrackingHistory> createState() =>
      _CustomerTrackingHistoryState();
}

class _CustomerTrackingHistoryState extends State<CustomerTrackingHistory>
    with WidgetsBindingObserver {
  List<Parcel> _parcels = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parcels =
          await (widget.loadParcels ?? Api.I.customerTrackingParcels)();
      if (!mounted) return;
      setState(() {
        _parcels = [...parcels]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not refresh your shipments. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Parcel parcel) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            parcel.serviceType == 'AIR_TRAVELLER' &&
                parcel.connectBookingId != null
            ? ConnectBookingScreen(
                id: parcel.connectBookingId!,
                request: Api.I.connect,
              )
            : CustomerParcelDetailsScreen(parcel: parcel),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text('Your shipments', style: AppTheme.sectionTitle),
          ),
          if (_parcels.isNotEmpty)
            Text('${_parcels.length}', style: AppTheme.caption),
          IconButton(
            key: const ValueKey('refresh-tracking-shipments'),
            tooltip: 'Refresh your shipments',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const Text(
        'Requests, shipments in progress and completed deliveries.',
        style: AppTheme.caption,
      ),
      const SizedBox(height: 16),
      if (_loading)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: LinearProgressIndicator(minHeight: 3),
        ),
      if (_error != null)
        SectionCard(
          tint: AppColors.coralSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!, style: AppTheme.caption),
              TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      if (!_loading && _error == null && _parcels.isEmpty)
        const SectionCard(
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 32,
                color: AppColors.textGrey,
              ),
              SizedBox(height: 12),
              Text('No shipments yet', style: AppTheme.sectionTitle),
              SizedBox(height: 6),
              Text(
                'Your shipment requests will appear here as soon as they are submitted.',
                textAlign: TextAlign.center,
                style: AppTheme.caption,
              ),
            ],
          ),
        ),
      for (final parcel in _parcels)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              key: ValueKey('track-shipment-${parcel.id}'),
              onTap: () => _open(parcel),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          parcel.method.icon,
                          size: 22,
                          color: AppColors.coral,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            parcel.trackingId,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.textGrey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${parcel.origin} → ${parcel.destination}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('To ${parcel.recipientName}', style: AppTheme.caption),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: StatusVisual.of(parcel.status).chipBg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            statusLabel(parcel.status),
                            style: TextStyle(
                              color: StatusVisual.of(parcel.status).chipFg,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          parcel.serviceType == 'AIR_TRAVELLER'
                              ? 'Air Traveller'
                              : parcel.method.label,
                          style: AppTheme.caption.copyWith(fontSize: 11),
                        ),
                        Text(
                          DateFormat('MMM d, yyyy')
                              .format(parcel.createdAt.toLocal()),
                          style: AppTheme.caption.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
