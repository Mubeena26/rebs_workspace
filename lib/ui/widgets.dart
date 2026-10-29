import 'dart:async';

import 'package:flutter/material.dart';

import '../app/workspace_controller.dart';
import '../domain/attendance_rules.dart';
import '../domain/company_clock.dart';
import '../domain/models.dart';

const kGreen = Color(0xFF16A34A);
const kOrange = Color(0xFFE5850B);
const kRed = Color(0xFFDC2626);

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// 09:15 AM
String hm12(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String formatDuration(Duration d) => '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

/// 2026-10-28 -> 28 Oct 2026
String longDate(String ymd) {
  final d = DateTime.parse(ymd);
  return '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';
}

String monthShort(String ymd) => _months[DateTime.parse(ymd).month - 1].substring(0, 3);

String weekdayOf(String ymd) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][DateTime.parse(ymd).weekday - 1];

/// 2026-10 -> October 2026
String monthTitle(String ym) => '${_months[int.parse(ym.substring(5, 7)) - 1]} ${ym.substring(0, 4)}';

String todayLabel(TodayStatus s) => switch (s) {
      TodayStatus.notCheckedIn => 'Not Checked In',
      TodayStatus.checkedIn => 'Checked In',
      TodayStatus.checkedOut => 'Checked Out',
    };

Color todayColor(TodayStatus s, ColorScheme cs) => switch (s) {
      TodayStatus.notCheckedIn => cs.outline,
      TodayStatus.checkedIn => kGreen,
      TodayStatus.checkedOut => cs.primary,
    };

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.color, {super.key, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

class SyncChip extends StatelessWidget {
  const SyncChip(this.status, {super.key});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        SyncStatus.pending => const StatusPill('Pending sync', kOrange),
        SyncStatus.synced => const StatusPill('Synced', kGreen),
        SyncStatus.rejected => const StatusPill('Rejected', kRed),
      };
}

/// White rounded card with the app's standard padding and spacing.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.title, this.text, this.color = Colors.blueGrey, this.action});
  final IconData icon;
  final String title;
  final String? text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              if (text != null) Text(text!, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          ?action,
        ]),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          ?action,
        ]),
      );
}

/// Re-renders every 30 s so the elapsed duration stays current.
class Ticking extends StatefulWidget {
  const Ticking({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Full-area state (loading, empty, error, offline). [color] puts the icon in a filled circle.
class CenteredMessage extends StatelessWidget {
  const CenteredMessage({super.key, this.icon, this.leading, required this.title, this.body, this.action, this.color});
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? body;
  final Widget? action;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = leading ??
        (color == null
            ? Icon(icon, size: 56, color: theme.colorScheme.outline)
            : CircleAvatar(radius: 26, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 30)));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          iconWidget,
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Today's check-in/out times, their sync state and the running duration.
class TodaySummary extends StatelessWidget {
  const TodaySummary(this.c, {super.key, this.large = false});
  final WorkspaceController c;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = c.today;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String time(DateTime? x) => x == null ? '--:--' : hm12(c.clock.local(x));
    Widget slot(String label, DateTime? x, SyncStatus? s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(time(x), style: (large ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: muted),
          if (s != null && s != SyncStatus.synced) Padding(padding: const EdgeInsets.only(top: 4), child: SyncChip(s)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: slot('Check-in Time', t.checkIn, t.checkInSync)),
        Expanded(child: slot('Check-out Time', t.checkOut, t.checkOutSync)),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Icon(Icons.schedule_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        const Expanded(child: Text('Working Duration')),
        Ticking(builder: (_) {
          final w = t.worked(c.clock.nowUtc());
          return Text(w == null ? '--' : formatDuration(w),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: todayColor(t.status, theme.colorScheme)));
        }),
      ]),
      for (final e in t.rejected)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const SyncChip(SyncStatus.rejected),
            const SizedBox(width: 8),
            Expanded(child: Text('${e.type == EventType.checkIn ? 'Check-in' : 'Check-out'}: ${e.error}', style: muted)),
          ]),
        ),
    ]);
  }
}

/// One day of attendance. [dateBlock] shows the big day number used in history.
class AttendanceRow extends StatelessWidget {
  const AttendanceRow(this.r, this.clock, {super.key, this.dateBlock = false});
  final DayRecord r;
  final CompanyClock clock;
  final bool dateBlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String time(DateTime? x) => x == null ? '--:--' : hm12(clock.local(x));
    final duration = r.checkIn == null
        ? '—'
        : r.checkOut == null
            ? 'In progress'
            : formatDuration(r.worked(r.checkOut!)!);
    final sync = {r.checkInSync, r.checkOutSync}.contains(SyncStatus.pending)
        ? SyncStatus.pending
        : r.rejected.isNotEmpty
            ? SyncStatus.rejected
            : r.checkIn != null
                ? SyncStatus.synced
                : null;
    final date = dateBlock
        ? SizedBox(
            width: 40,
            child: Column(children: [
              Text('${DateTime.parse(r.date).day}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(monthShort(r.date), style: muted),
              Text(weekdayOf(r.date), style: muted),
            ]),
          )
        : SizedBox(
            width: 92,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(longDate(r.date), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              Text(weekdayOf(r.date), style: muted),
            ]),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        date,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${time(r.checkIn)} - ${time(r.checkOut)}', style: theme.textTheme.bodyMedium),
            Text(duration, style: muted),
          ]),
        ),
        if (sync != null) SyncChip(sync),
      ]),
    );
  }
}
