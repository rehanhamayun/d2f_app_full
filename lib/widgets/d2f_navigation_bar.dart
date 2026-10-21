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
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
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
                children: List.generate(_items.length, (index) {
                  final base = _items[index];
                  final item = (
                    publicWorkspace && index == 1 && driver
                        ? 'Dispatch'
                        : publicWorkspace && index == 2
                        ? 'Track'
                        : base.$1,
                    base.$2,
                    base.$3,
                    base.$4,
                  );
                  final selected = index == selectedIndex;
                  return Expanded(
                    child: Semantics(
                      selected: selected,
                      button: true,
                      child: Tooltip(
                        message: item.$1,
                        child: InkWell(
                          key: ValueKey('nav-${item.$2}'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            if (!selected) {
                              HapticFeedback.selectionClick();
                              onSelected(index);
                            }
                          },
                          child: SizedBox(
                            height: 58,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration: duration,
                                  width: 44,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.coralSoft
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    selected ? item.$4 : item.$3,
                                    size: 23,
                                    color: selected
                                        ? AppColors.coral
                                        : AppColors.textGrey,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  item.$1,
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.navy
                                        : AppColors.textGrey,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    fontSize: 10,
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
