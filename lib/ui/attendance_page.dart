import 'dart:math';

import 'package:flutter/material.dart';

import '../app/workspace_controller.dart';
import '../domain/attendance_rules.dart';
import '../domain/models.dart';
import 'actions.dart';
import 'widgets.dart';

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final emp = c.employee;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Attendance'),
              actions: [IconButton(tooltip: 'Refresh location', onPressed: c.checkLocation, icon: const Icon(Icons.my_location))],
            ),
            body: emp == null
                ? const CenteredMessage(
                    icon: Icons.cloud_download_outlined,
                    title: 'Office not configured yet',
                    body: 'Connect once from the Home tab to download your office location.')
                : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                    if (c.offline)
                      const InfoBanner(
                          icon: Icons.wifi_off,
                          color: kOrange,
                          title: 'You are offline',
                          text: 'Check-in and check-out are saved on this device and synced later.'),
                    Panel(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        SizedBox(height: 190, child: _GeofenceMap(c)),
                        ListTile(
                          leading: const Icon(Icons.location_on, color: kGreen),
                          title: const Text('Office Location'),
                          subtitle: Text(emp.office.name),
                          trailing: Text('${emp.office.radiusMeters.round()} m allowed', style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ]),
                    ),
                    _locationBanner(c),
                    Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text("Today's Status",
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          StatusPill(todayLabel(c.today.status), todayColor(c.today.status, Theme.of(context).colorScheme)),
                        ]),
                        const SizedBox(height: 12),
                        TodaySummary(c),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: c.busy || c.today.status != TodayStatus.notCheckedIn
                                ? null
                                : () => recordWithFeedback(context, c, EventType.checkIn),
                            icon: const Icon(Icons.login),
                            label: const Text('Check In'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: c.busy || c.today.status != TodayStatus.checkedIn
                                ? null
                                : () => recordWithFeedback(context, c, EventType.checkOut),
                            icon: const Icon(Icons.logout),
                            label: const Text('Check Out'),
                          ),
                        ),
                      ]),
                    ),
                    if (c.busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
                    _SyncPanel(c),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttendanceHistoryPage(controller: c))),
                      icon: const Icon(Icons.history),
                      label: const Text('View attendance history'),
                    ),
                  ]),
          );
        },
      );

  Widget _locationBanner(WorkspaceController c) {
    final d = c.distance;
    final radius = c.employee!.office.radiusMeters.round();
    if (c.locationError != null) {
      return InfoBanner(icon: Icons.location_disabled, color: kOrange, title: 'Location unavailable', text: c.locationError);
    }
    if (d == null) {
      return const InfoBanner(icon: Icons.location_searching, title: 'Location not checked yet', text: 'Tap the location button to check your distance.');
    }
    return d <= radius
        ? InfoBanner(
            icon: Icons.verified_user, color: kGreen, title: 'You are within the permitted area', text: 'Your current location is ${d.round()} metres from office.')
        : InfoBanner(
            icon: Icons.warning_amber_rounded,
            color: kRed,
            title: 'You are outside the permitted area',
            text: 'Your current location is ${d.round()} metres from office. Attendance is allowed only within $radius metres.');
  }
}

class _SyncPanel extends StatelessWidget {
  const _SyncPanel(this.c);
  final WorkspaceController c;

  @override
  Widget build(BuildContext context) {
    final rejected = c.events.where((e) => e.status == SyncStatus.rejected).length;
    final status = c.pendingCount > 0
        ? StatusPill('${c.pendingCount} pending', kOrange, icon: Icons.schedule)
        : const StatusPill('All events synced', kGreen, icon: Icons.check_circle);
    return Panel(
      child: Row(children: [
        Icon(Icons.cloud_sync_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sync Status', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            status,
            if (rejected > 0) ...[const SizedBox(height: 4), StatusPill('$rejected rejected', kRed, icon: Icons.error_outline)],
            if (c.lastUpdated != null) ...[
              const SizedBox(height: 4),
              Text('Last synced: ${hm12(c.clock.local(c.lastUpdated!))}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ]),
        ),
        OutlinedButton.icon(
          onPressed: c.syncing ? null : () => syncWithFeedback(context, c),
          icon: const Icon(Icons.sync, size: 18),
          label: Text(c.syncing ? 'Syncing…' : 'Sync Now'),
        ),
      ]),
    );
  }
}

/// Schematic geofence (no map tiles): office at the centre, the user's last
/// known position drawn to scale, clamped to the edge when far away.
class _GeofenceMap extends StatelessWidget {
  const _GeofenceMap(this.c);
  final WorkspaceController c;

  @override
  Widget build(BuildContext context) {
    final office = c.employee!.office;
    final p = c.position;
    final d = c.distance;
    final inside = d != null && d <= office.radiusMeters;
    // Metres east/north of the office; equirectangular is accurate enough at this scale.
    final offset = p == null
        ? null
        : Offset((p.lng - office.longitude) * 111320 * cos(office.latitude * pi / 180), (p.lat - office.latitude) * 111320);
    final scheme = Theme.of(context).colorScheme;
    return Stack(children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _GeofencePainter(
            radiusMeters: office.radiusMeters,
            userMeters: offset,
            fence: inside || d == null ? kGreen : kRed,
            user: scheme.primary,
            grid: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      if (d != null)
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              color: scheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(inside ? 'Within office area · ${d.round()} m away' : 'Outside office area · ${d.round()} m away',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _GeofencePainter extends CustomPainter {
  _GeofencePainter({required this.radiusMeters, required this.userMeters, required this.fence, required this.user, required this.grid});
  final double radiusMeters;
  final Offset? userMeters;
  final Color fence;
  final Color user;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final centre = size.center(Offset.zero);
    final r = size.shortestSide * 0.36;
    final scale = r / radiusMeters;
    canvas.drawCircle(centre, r, Paint()..color = fence.withValues(alpha: 0.12));
    canvas.drawCircle(
        centre,
        r,
        Paint()
          ..color = fence.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(centre, 12, Paint()..color = kGreen);
    canvas.drawCircle(centre, 4, Paint()..color = Colors.white);

    final m = userMeters;
    if (m == null) return;
    final raw = centre + Offset(m.dx * scale, -m.dy * scale);
    final pos = Offset(raw.dx.clamp(12, size.width - 12), raw.dy.clamp(12, size.height - 12));
    canvas.drawCircle(pos, 18, Paint()..color = user.withValues(alpha: 0.18));
    canvas.drawCircle(pos, 8, Paint()..color = Colors.white);
    canvas.drawCircle(pos, 6, Paint()..color = user);
  }

  @override
  bool shouldRepaint(_GeofencePainter old) =>
      old.userMeters != userMeters || old.fence != fence || old.radiusMeters != radiusMeters || old.user != user || old.grid != grid;
}

class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  late String _month = widget.controller.clock.today().substring(0, 7);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          // shortcut: only months already loaded (current + previous); fetch others via /attendance?month= if needed.
          final months = {_month, for (final r in c.records) r.date.substring(0, 7)}.toList()..sort((a, b) => b.compareTo(a));
          final rows = c.records.where((r) => r.date.startsWith(_month)).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Attendance History')),
            body: RefreshIndicator(
              onRefresh: c.syncNow,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _month,
                      icon: const Icon(Icons.expand_more),
                      items: [
                        for (final m in months)
                          DropdownMenuItem(
                            value: m,
                            child: Row(children: [const Icon(Icons.calendar_today_outlined, size: 18), const SizedBox(width: 10), Text(monthTitle(m))]),
                          ),
                      ],
                      onChanged: (m) => setState(() => _month = m!),
                    ),
                  ),
                ),
                if (rows.isEmpty)
                  const CenteredMessage(
                      icon: Icons.event_note_outlined, title: 'No attendance records', body: 'Your attendance history will appear here.')
                else
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(children: [
                      for (final (i, r) in rows.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        AttendanceRow(r, c.clock, dateBlock: true),
                      ],
                    ]),
                  ),
              ]),
            ),
          );
        },
      );
}
