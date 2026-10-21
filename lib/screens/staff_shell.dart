import 'package:flutter/material.dart';

import '../widgets/d2f_navigation_bar.dart';
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
  final _homeKey = GlobalKey<HomeScreenState>();
  final _shipKey = GlobalKey<ShipScreenState>();
  final _activityKey = GlobalKey<ActivityScreenState>();

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      HomeScreen(
        key: _homeKey,
        onGoRegister: () => _select(1),
        onGoActivity: () => _select(2),
        onGoRoute: (ShipmentRoute route) {
          _shipKey.currentState?.presetRoute(route);
          _select(1);
        },
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
    if (i == 0) _homeKey.currentState?.refresh();
    if (i == 2) _activityKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.cream),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: IndexedStack(index: _index, children: _tabs),
          ),
        ),
      ),
      bottomNavigationBar: D2FNavigationBar(
        selectedIndex: _index,
        onSelected: _select,
      ),
    );
  }
}
