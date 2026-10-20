import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Displays the server's recorded events, including their actor and location.
/// Skipped lifecycle stages are never presented as completed events.
class TrackingTimeline extends StatelessWidget {
  final List<TrackingEvent> events;
  final String currentStatus;

  const TrackingTimeline({
    super.key,
    required this.events,
    required this.currentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = [...events]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (ordered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No tracking events recorded yet.',
          style: AppTheme.caption,
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < ordered.length; i++)
          _event(
            ordered[i],
            current:
                i == ordered.length - 1 && ordered[i].status == currentStatus,
            last: i == ordered.length - 1,
          ),
      ],
    );
  }

  Widget _event(
    TrackingEvent event, {
    required bool current,
    required bool last,
  }) {
    final color = current ? AppColors.blue : AppColors.green;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: current ? AppColors.blueSoft : AppColors.greenSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    current
                        ? Icons.local_shipping_outlined
                        : Icons.check_rounded,
                    color: color,
                    size: 19,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: last ? 0 : 20),
              padding: current
                  ? const EdgeInsets.all(12)
                  : const EdgeInsets.only(top: 4, bottom: 4),
              decoration: current
                  ? BoxDecoration(
                      color: AppColors.blueSoft.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(14),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusLabel(event.status),
                    style: AppTheme.body.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DateFormat('MMM d, yyyy · h:mm a')
                        .format(event.createdAt.toLocal()),
                    style: AppTheme.caption.copyWith(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (event.note != null && event.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.note!,
                      style: AppTheme.caption.copyWith(
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (event.location != null && event.location!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location!,
                            style: AppTheme.caption.copyWith(
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (event.actorName != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      'By ${event.actorName}',
                      style: AppTheme.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
