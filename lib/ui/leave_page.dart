import 'package:flutter/material.dart';

import '../app/workspace_controller.dart';
import '../domain/leave_rules.dart';
import '../domain/models.dart';
import 'widgets.dart';

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

class LeavePage extends StatefulWidget {
  const LeavePage({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  LeaveStatus? _filter; // null = All

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final shown = c.leaves.where((r) => _filter == null || r.status == _filter).toList();
          return Scaffold(
            appBar: AppBar(
              title: const Text('My Leave Requests'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton.filled(
                    tooltip: 'Apply for leave',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LeaveFormPage(controller: c))),
                    icon: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: c.refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                if (c.offline)
                  const InfoBanner(
                      icon: Icons.wifi_off, color: kOrange, title: 'You are offline', text: 'Showing saved requests. Submitting needs a connection.'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in [null, ...LeaveStatus.values])
                      ChoiceChip(
                        label: Text(s == null ? 'All' : _cap(s.name)),
                        selected: _filter == s,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _filter = s),
                      ),
                  ]),
                ),
                if (shown.isEmpty)
                  CenteredMessage(
                    icon: Icons.event_available_outlined,
                    title: _filter == null ? 'No leave requests yet' : 'No ${_filter!.name} requests',
                    body: 'Tap + to apply for leave.',
                  )
                else
                  for (final r in shown) _LeaveCard(r),
              ]),
            ),
          );
        },
      );
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard(this.r);
  final LeaveRequest r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = switch (r.status) {
      LeaveStatus.pending => (kOrange, Icons.schedule),
      LeaveStatus.approved => (kGreen, Icons.check_circle),
      LeaveStatus.rejected => (kRed, Icons.cancel),
    };
    final days = leaveDays(r.startDate, r.endDate);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StatusPill(_cap(r.status.name), color, icon: icon),
        const SizedBox(height: 8),
        Text('${_cap(r.type.name)} Leave', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('${longDate(r.startDate)} - ${longDate(r.endDate)}', style: theme.textTheme.bodySmall),
        Text('$days ${days == 1 ? 'Day' : 'Days'}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(r.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class LeaveFormPage extends StatefulWidget {
  const LeaveFormPage({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  State<LeaveFormPage> createState() => _LeaveFormPageState();
}

class _LeaveFormPageState extends State<LeaveFormPage> {
  final _requestId = newId(); // one id per form: a resubmit after a lost response is the same request
  final _reason = TextEditingController();
  LeaveType _type = LeaveType.casual;
  String? _start;
  String? _end;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final today = DateTime.parse(widget.controller.clock.today());
    final current = start ? _start : (_end ?? _start);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDate: current == null ? today : DateTime.parse(current),
    );
    if (picked == null) return;
    setState(() => start ? _start = _ymd(picked) : _end = _ymd(picked));
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.controller.submitLeave(requestId: _requestId, type: _type, start: _start, end: _end, reason: _reason.text);
    if (!mounted) return;
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request submitted.')));
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final balance = widget.controller.balance;
    final days = _start != null && _end != null && _end!.compareTo(_start!) >= 0 ? leaveDays(_start!, _end!) : null;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        );
    Widget dateField(String? value, bool start) => InkWell(
          onTap: () => _pick(start),
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.calendar_today_outlined, size: 20)),
            child: Text(value == null ? 'Select date' : longDate(value),
                style: value == null ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for Leave')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Panel(
          color: Color.alphaBlend(primary.withValues(alpha: 0.07), theme.cardTheme.color ?? theme.colorScheme.surface),
          child: Row(children: [
            CircleAvatar(radius: 24, backgroundColor: primary.withValues(alpha: 0.12), child: Icon(Icons.event_available, color: primary)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Available Leave Balance', style: theme.textTheme.bodySmall?.copyWith(color: primary)),
                Text('${balance.values.fold(0, (a, b) => a + b)} Days',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: primary)),
                Text(LeaveType.values.map((t) => '${_cap(t.name)} ${balance[t] ?? 0}').join('  ·  '), style: theme.textTheme.bodySmall),
              ]),
            ),
          ]),
        ),
        label('Leave Type'),
        Row(children: [
          for (final (i, t) in LeaveType.values.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                style: _type == t
                    ? OutlinedButton.styleFrom(
                        backgroundColor: primary.withValues(alpha: 0.08), side: BorderSide(color: primary, width: 1.5), foregroundColor: primary)
                    : OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.onSurface),
                onPressed: () => setState(() => _type = t),
                child: Text('${_cap(t.name)} Leave'),
              ),
            ),
          ],
        ]),
        label('Start Date'),
        dateField(_start, true),
        label('End Date'),
        dateField(_end, false),
        if (days != null) ...[
          const SizedBox(height: 16),
          Panel(
            color: Color.alphaBlend(primary.withValues(alpha: 0.07), theme.cardTheme.color ?? theme.colorScheme.surface),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(Icons.date_range, color: primary),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Requested Days', style: theme.textTheme.bodySmall?.copyWith(color: primary)),
                Text('$days ${days == 1 ? 'Day' : 'Days'}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ],
        label('Reason'),
        TextField(
          controller: _reason,
          minLines: 4,
          maxLines: 6,
          maxLength: 500,
          decoration: const InputDecoration(hintText: 'At least 10 characters'),
        ),
        if (_error != null) InfoBanner(icon: Icons.error_outline, color: kRed, title: 'Cannot submit', text: _error),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit Leave Request'),
          ),
        ),
      ]),
    );
  }
}
