import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../core/theme.dart';
import '../models/models.dart';
import 'account_screen.dart';
import 'activity_screen.dart';
import 'home_screen.dart';
import 'ship_screen.dart';

/// Bottom navigation shell for staff: Home / Ship / Activity / Account
/// (nav per design screens 3, 6, 8).
class StaffShell extends StatefulWidget {
  const StaffShell({super.key});

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  int _index = 0;
  final _shipKey = GlobalKey<ShipScreenState>();
  final _activityKey = GlobalKey<ActivityScreenState>();

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      HomeScreen(
        onGoRegister: () => _select(1),
        onGoActivity: () => _select(2),
        onGoMethod: (ShippingMethod method) {
          _shipKey.currentState?.presetMethod(method);
          _select(1);
        },
      ),
      ShipScreen(key: _shipKey),
      ActivityScreen(key: _activityKey),
      const AccountScreen(),
    ];
  }

  void _select(int i) {
    setState(() => _index = i);
    if (i == 2) _activityKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE9F0F9), Color(0xFFEDE9F3), Color(0xFFE8F1F3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: IndexedStack(index: _index, children: _tabs),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
            child: Row(
              children: [
                _item(0, CupertinoIcons.house, 'Home'),
                _item(1, CupertinoIcons.cube_box, 'Ship'),
                _item(2, CupertinoIcons.square_list, 'Activity'),
                _item(3, CupertinoIcons.person, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final selected = _index == i;
    final color = selected
        ? AppColors.coral
        : AppColors.navy.withValues(alpha: 0.55);
    return Expanded(
      child: InkWell(
        onTap: () => _select(i),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? AppColors.coral : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : color,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.coral : color,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
