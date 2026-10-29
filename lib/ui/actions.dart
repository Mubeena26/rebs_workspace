import 'package:flutter/material.dart';

import '../app/workspace_controller.dart';
import '../data/location_service.dart';
import '../domain/models.dart';

const _scenarios = {
  'ok': 'Success',
  'slow': 'Slow (3 s)',
  'timeout': 'Timeout (accepted, reply lost)',
  'error': 'Server error 500',
  'conflict': 'Duplicate attendance conflict',
  'leave_reject': 'Leave validation rejection',
};

void snack(BuildContext context, String msg, {SnackBarAction? action}) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg), action: action));

Future<void> syncWithFeedback(BuildContext context, WorkspaceController c) async {
  final r = await c.syncNow();
  if (!context.mounted) return;
  snack(context, r.error != null ? 'Sync paused: ${r.error} ${r.remaining} still pending.' : 'Sync complete: ${r.synced} synced, ${r.rejected} rejected.');
}

Future<void> recordWithFeedback(BuildContext context, WorkspaceController c, EventType type) async {
  final outcome = await c.record(type);
  if (!context.mounted) return;
  snack(context, outcome.message,
      action: outcome.openSettings ? SnackBarAction(label: 'Settings', onPressed: c.location.openSettings) : null);
}

/// Reviewer controls: simulated location and mock API scenario.
void showDevSheet(BuildContext context, WorkspaceController c) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: c,
        builder: (sheetContext, _) => SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ListTile(title: Text('Location source'), dense: true),
              RadioGroup<LocationMode>(
                groupValue: c.location.mode,
                onChanged: (m) => c.setLocationMode(m!),
                child: const Column(children: [
                  RadioListTile(value: LocationMode.gps, title: Text('Device GPS')),
                  RadioListTile(value: LocationMode.simulatedInside, title: Text('Simulated: inside office (~55 m)')),
                  RadioListTile(value: LocationMode.simulatedOutside, title: Text('Simulated: outside office (~500 m)')),
                ]),
              ),
              const Divider(),
              const ListTile(title: Text('Mock API scenario'), dense: true),
              for (final s in _scenarios.entries)
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(s.value),
                  subtitle: Text(s.key),
                  onTap: () async {
                    final msg = await c.setScenario(s.key);
                    if (context.mounted) snack(context, msg);
                  },
                ),
            ]),
          ),
        ),
      ),
    );
