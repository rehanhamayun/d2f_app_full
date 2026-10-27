import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Server-recorded events only. A skipped lifecycle stage never becomes a
/// completed step, and missing dates, actors, and locations are never invented.
class TrackingTimeline extends StatelessWidget {
  final List<TrackingEvent> events;
  final String currentStatus;

  /// Lets authorized staff correct an accidental operational note without
  /// deleting the original event, actor, time, or location.
  final bool Function(TrackingEvent event)? canEditNote;
  final void Function(TrackingEvent event)? onEditNote;

  const TrackingTimeline({
    super.key,
    required this.events,
    required this.currentStatus,
    this.canEditNote,
    this.onEditNote,
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
    return Stack(
      children: [
        if (!last)
          Positioned(
            left: 15,
            top: 32,
            bottom: 0,
            child: SizedBox(
              width: 2,
              child: ColoredBox(color: AppColors.green.withValues(alpha: .5)),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: current ? AppColors.blueSoft : AppColors.greenSoft,
                shape: BoxShape.circle,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(
                  current ? Icons.local_shipping_rounded : Icons.check_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Container(
                margin: EdgeInsets.only(bottom: last ? 0 : 20),
                padding: current
                    ? const EdgeInsets.all(10)
                    : const EdgeInsets.only(top: 3, bottom: 3),
                decoration: current
                    ? BoxDecoration(
                        color: AppColors.blueSoft,
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final title = Text(
                      statusLabel(event.status),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: current ? AppColors.blue : AppColors.navy,
                      ),
                    );
                    final date = Text(
                      DateFormat('MMM d, yyyy · h:mm a')
                          .format(event.createdAt.toLocal()),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textGrey,
                        height: 1.5,
                      ),
                    );
                    final sideBySide =
                        c.maxWidth >= 230 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.2;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (sideBySide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 8),
                              SizedBox(width: 103, child: date),
                            ],
                          )
                        else ...[
                          title,
                          const SizedBox(height: 4),
                          date,
                        ],
                        if (event.note?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 7),
                          Text(
                            event.note!,
                            style: AppTheme.caption.copyWith(
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                          if (canEditNote?.call(event) ?? false)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => onEditNote?.call(event),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: AppColors.blue,
                                ),
                                icon: const Icon(
                                  Icons.edit_note_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Correct note',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                        if (event.location?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 7),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: AppColors.textGrey,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  event.location!,
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 10,
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
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
