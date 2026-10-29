import 'package:flutter/material.dart';

import '../app/workspace_controller.dart';
import 'attendance_page.dart';
import 'dashboard_page.dart';
import 'leave_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [
          DashboardPage(controller: widget.controller),
          AttendancePage(controller: widget.controller),
          LeavePage(controller: widget.controller),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            // Ask for location only when the user opens the attendance tab, not at launch.
            if (i == 1) widget.controller.checkLocation();
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.access_time), selectedIcon: Icon(Icons.access_time_filled), label: 'Attendance'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Leave'),
          ],
        ),
      );
}
