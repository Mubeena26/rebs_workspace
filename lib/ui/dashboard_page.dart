import 'package:flutter/material.dart';

import '../app/workspace_controller.dart';
import '../data/location_service.dart';
import '../domain/attendance_rules.dart';
import '../domain/models.dart';
import 'actions.dart';
import 'attendance_page.dart';
import 'widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Scaffold(
          body: SafeArea(
            child: Column(children: [
              _Header(controller),
              Expanded(child: _body(context)),
            ]),
          ),
        ),
      );

  Widget _body(BuildContext context) {
    final c = controller;
    if (!c.hasData && c.loading) {
      return const CenteredMessage(leading: CircularProgressIndicator(), title: 'Loading your data…');
    }
    if (!c.hasData) {
      return CenteredMessage(
        icon: c.offline ? Icons.wifi_off : Icons.priority_high,
        color: c.offline ? kOrange : kRed,
        title: c.offline ? 'You are offline' : 'Failed to load data',
        body: '${c.loadError ?? ''}\nPlease check your connection and try again.',
        action: FilledButton(onPressed: c.refresh, child: const Text('Retry')),
      );
    }
    final updated = c.lastUpdated == null ? '' : ' Last updated ${hm12(c.clock.local(c.lastUpdated!))}.';
    final totalBalance = c.balance.isEmpty ? '-' : '${c.balance.values.fold(0, (a, b) => a + b)}';
    return RefreshIndicator(
      onRefresh: c.syncNow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (c.staleReason != null)
            c.offline
                ? InfoBanner(
                    icon: Icons.wifi_off,
                    color: kOrange,
                    title: 'You are offline',
                    text: 'Showing cached data. Some features may be limited.$updated')
                : InfoBanner(icon: Icons.cloud_off, color: kRed, title: 'Could not refresh', text: '${c.staleReason} Showing saved data.$updated'),
          _TodayCard(c),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: _Tile(icon: Icons.calendar_month_outlined, color: Theme.of(context).colorScheme.primary,
                    label: 'Leave Balance', value: totalBalance, caption: 'Days Left'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Tile(
                  icon: Icons.cloud_upload_outlined,
                  color: c.pendingCount > 0 ? kOrange : kGreen,
                  label: 'Pending Sync',
                  value: '${c.pendingCount}',
                  caption: c.pendingCount == 1 ? 'Event' : 'Events',
                  onTap: c.syncing ? null : () => syncWithFeedback(context, c),
                ),
              ),
            ]),
          ),
          SectionHeader('Recent Attendance',
              action: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttendanceHistoryPage(controller: c))),
                child: const Text('View All'),
              )),
          if (c.recent.isEmpty)
            const CenteredMessage(icon: Icons.event_note_outlined, title: 'No attendance records', body: 'Your attendance history will appear here.')
          else
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (final (i, r) in c.recent.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  AttendanceRow(r, c.clock),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.c);
  final WorkspaceController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = c.employee;
    final hour = c.clock.local(c.clock.nowUtc()).hour;
    final greeting = hour < 12 ? 'Good Morning' : (hour < 17 ? 'Good Afternoon' : 'Good Evening');
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
          child: Text(e?.name.characters.first ?? '·',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, style: muted),
            Text(e?.name ?? 'My Workspace', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (e != null) Text('${e.id}  |  ${e.department}', style: muted, overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(
          tooltip: 'Sync Now',
          onPressed: c.syncing ? null : () => syncWithFeedback(context, c),
          icon: Badge(isLabelVisible: c.pendingCount > 0, label: Text('${c.pendingCount}'), child: const Icon(Icons.sync)),
        ),
        IconButton(tooltip: 'Developer options', onPressed: () => showDevSheet(context, c), icon: const Icon(Icons.tune)),
      ]),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard(this.c);
  final WorkspaceController c;

  @override
  Widget build(BuildContext context) {
    final t = c.today;
    final theme = Theme.of(context);
    final color = todayColor(t.status, theme.colorScheme);
    final (label, icon, type) = switch (t.status) {
      TodayStatus.notCheckedIn => ('Check In', Icons.login, EventType.checkIn),
      TodayStatus.checkedIn => ('Check Out', Icons.logout, EventType.checkOut),
      TodayStatus.checkedOut => ('Completed for today', Icons.check_circle_outline, null),
    };
    return Panel(
      color: Color.alphaBlend(color.withValues(alpha: 0.07), theme.cardTheme.color ?? theme.colorScheme.surface),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Today's Attendance", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (c.location.mode != LocationMode.gps)
                const Padding(padding: EdgeInsets.only(top: 4), child: StatusPill('Simulated GPS', Colors.blueGrey)),
            ]),
          ),
          StatusPill(todayLabel(t.status), color),
        ]),
        const SizedBox(height: 14),
        TodaySummary(c, large: true),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: c.busy || type == null ? null : () => recordWithFeedback(context, c, type),
            icon: c.busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
            label: Text(label),
          ),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.label, required this.value, required this.caption, this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodySmall),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
            Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}
