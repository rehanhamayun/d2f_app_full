import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Shared presentation for order lifecycle statuses, used by the buyer
/// orders screen, the Buy For Me flow and Seller Studio.
String statusLabel(String status) => switch (status) {
      'REQUESTED' => 'Requested',
      'ACCEPTED' => 'Confirmed',
      'QUOTED' => 'Quoted',
      'PURCHASED' => 'Purchased',
      'RECEIVED' => 'Received by D2F',
      'PROCESSING' => 'Being prepared',
      'SHIPPED' => 'Shipped',
      'COMPLETED' => 'Completed',
      'CANCELLED' => 'Cancelled',
      _ => status,
    };

({Color bg, Color fg, IconData icon}) statusVisual(String status) => switch (status) {
      'REQUESTED' => (bg: AppColors.goldSoft, fg: const Color(0xFF9A7100), icon: Icons.hourglass_top_rounded),
      'QUOTED' => (bg: AppColors.blueSoft, fg: AppColors.blue, icon: Icons.request_quote_rounded),
      'ACCEPTED' => (bg: AppColors.blueSoft, fg: AppColors.blue, icon: Icons.thumb_up_alt_rounded),
      'PURCHASED' => (bg: AppColors.indigoSoft, fg: AppColors.indigo, icon: Icons.shopping_bag_rounded),
      'RECEIVED' => (bg: AppColors.tealSoft, fg: AppColors.teal, icon: Icons.warehouse_rounded),
      'PROCESSING' => (bg: AppColors.goldSoft, fg: const Color(0xFF9A7100), icon: Icons.inventory_2_rounded),
      'SHIPPED' => (bg: AppColors.blueSoft, fg: AppColors.blue, icon: Icons.local_shipping_rounded),
      'COMPLETED' => (bg: AppColors.greenSoft, fg: AppColors.green, icon: Icons.check_circle_rounded),
      'CANCELLED' => (bg: AppColors.coralSoft, fg: AppColors.coral, icon: Icons.cancel_rounded),
      _ => (bg: AppColors.chipGrey, fg: AppColors.textGrey, icon: Icons.circle_outlined),
    };

/// Compact pill used in list cards.
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final visual = statusVisual(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: visual.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 13, color: visual.fg),
          const SizedBox(width: 6),
          Text(
            statusLabel(status),
            style: TextStyle(
              color: visual.fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical progress timeline through the order lifecycle.
class OrderTimeline extends StatelessWidget {
  final String kind; // MARKETPLACE | BUY_FOR_ME
  final String status;
  const OrderTimeline({super.key, required this.kind, required this.status});

  static List<String> stepsFor(String kind) => kind == 'BUY_FOR_ME'
      ? ['REQUESTED', 'QUOTED', 'ACCEPTED', 'PURCHASED', 'RECEIVED', 'SHIPPED', 'COMPLETED']
      : ['REQUESTED', 'ACCEPTED', 'PROCESSING', 'SHIPPED', 'COMPLETED'];

  @override
  Widget build(BuildContext context) {
    if (status == 'CANCELLED') {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.coralSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: AppColors.coral, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This order was cancelled. Contact D2F if you believe this is a mistake.',
                style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.navy),
              ),
            ),
          ],
        ),
      );
    }
    final steps = stepsFor(kind);
    final current = steps.indexOf(status);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            label: statusLabel(steps[i]),
            state: i < current ? _StepState.done : i == current ? _StepState.now : _StepState.todo,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

enum _StepState { done, now, todo }

class _StepRow extends StatelessWidget {
  final String label;
  final _StepState state;
  final bool isLast;
  const _StepRow({required this.label, required this.state, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final done = state == _StepState.done;
    final now = state == _StepState.now;
    final color = done
        ? AppColors.green
        : now
            ? AppColors.coral
            : const Color(0xFFD8D4C9);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done || now ? color : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: done ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: done ? AppColors.green : const Color(0xFFE4E0D4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14, top: 1),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: now ? FontWeight.w800 : FontWeight.w600,
                  color: done || now ? AppColors.navy : AppColors.textGrey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
