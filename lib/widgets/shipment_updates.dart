import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Recorded shipment activity; this does not imply a push-notification inbox.
Future<void> showShipmentUpdates(
  BuildContext context, {
  required Future<List<Parcel>> Function() loadParcels,
  required ValueChanged<Parcel> onOpen,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.cream,
  builder: (_) => _ShipmentUpdates(loadParcels: loadParcels, onOpen: onOpen),
);

class _ShipmentUpdates extends StatefulWidget {
  final Future<List<Parcel>> Function() loadParcels;
  final ValueChanged<Parcel> onOpen;
  const _ShipmentUpdates({required this.loadParcels, required this.onOpen});
  @override
  State<_ShipmentUpdates> createState() => _ShipmentUpdatesState();
}

class _ShipmentUpdatesState extends State<_ShipmentUpdates> {
  late Future<List<Parcel>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.loadParcels();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shipment updates', style: AppTheme.heading),
                      SizedBox(height: 4),
                      Text(
                        'Your latest recorded shipment activity.',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close updates',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Parcel>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Could not load shipment updates.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => setState(() {
                              _future = widget.loadParcels();
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final parcels = [...snapshot.data ?? <Parcel>[]]
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                if (parcels.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 42,
                            color: AppColors.blue,
                          ),
                          SizedBox(height: 15),
                          Text(
                            'No shipment updates yet',
                            style: AppTheme.sectionTitle,
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Activity will appear here when you have a shipment.',
                            style: AppTheme.caption,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  itemCount: parcels.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final parcel = parcels[index];
                    final visual = StatusVisual.of(parcel.status);
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: ListTile(
                        key: ValueKey('update-${parcel.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: visual.chipBg,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: visual.chipFg,
                          ),
                        ),
                        title: Text(
                          parcel.trackingId,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            '${statusLabel(parcel.status)}\n${DateFormat('MMM d · h:mm a').format(parcel.updatedAt.toLocal())}',
                            style: const TextStyle(fontSize: 11, height: 1.6),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onOpen(parcel);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
