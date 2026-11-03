import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Floating navigation dock with persistent labels and animated active icons.
class D2FNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final bool publicWorkspace, driver;
  final ValueChanged<int> onSelected;
  const D2FNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.publicWorkspace = false,
    this.driver = false,
  });
  static const _items = [
    ('Home', 'home', Icons.home_outlined, Icons.home_rounded),
    ('Ship', 'ship', Icons.inventory_2_outlined, Icons.inventory_2_rounded),
    (
      'Activity',
      'activity',
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
    ),
    ('Account', 'profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];
  @override
  Widget build(BuildContext context) {
    final customer = publicWorkspace && !driver;
    final items = customer
        ? [
            (
              0,
              'Home',
              'home',
              Icons.home_outlined,
              Icons.home_rounded,
              AppColors.coral,
            ),
            (
              1,
              'Bookings',
              'ship',
              Icons.inventory_2_outlined,
              Icons.inventory_2_rounded,
              AppColors.blue,
            ),
            (
              2,
              'Track',
              'activity',
              Icons.location_on_outlined,
              Icons.location_on_rounded,
              AppColors.blue,
            ),
            (
              4,
              'Marketplace',
              'marketplace',
              Icons.storefront_outlined,
              Icons.storefront_rounded,
              const Color(0xFFE77D10),
            ),
            (
              5,
              'Buy For Me',
              'buy',
              Icons.shopping_bag_outlined,
              Icons.shopping_bag_rounded,
              const Color(0xFFDC3765),
            ),
          ]
        : [
            for (final e in _items.asMap().entries)
              (
                e.key,
                driver && e.key == 1
                    ? 'Dispatch'
                    : driver && e.key == 2
                    ? 'Track'
                    : e.value.$1,
                e.value.$2,
                e.value.$3,
                e.value.$4,
                AppColors.coral,
              ),
          ];
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(23),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: .8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: .12),
                    blurRadius: 22,
                    offset: const Offset(0, 7),
                  ),
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: .04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final selected = item.$1 == selectedIndex;
                  return Expanded(
                    child: Semantics(
                      selected: selected,
                      button: true,
                      child: Tooltip(
                        message: item.$2,
                        child: InkWell(
                          key: ValueKey('nav-${item.$3}'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            if (!selected) {
                              HapticFeedback.selectionClick();
                              onSelected(item.$1);
                            }
                          },
                          child: SizedBox(
                            height:
                                MediaQuery.textScalerOf(context).scale(1) > 1.15
                                ? 80
                                : 62,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration: duration,
                                  width: 40,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? item.$6.withValues(alpha: .12)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    selected ? item.$5 : item.$4,
                                    size: 23,
                                    color: selected
                                        ? item.$6
                                        : AppColors.textGrey,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  item.$2,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.navy
                                        : AppColors.textGrey,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    fontSize: customer ? 9 : 10,
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
