import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebs_workspace/data/location_service.dart';
import 'package:rebs_workspace/domain/attendance_rules.dart';
import 'package:rebs_workspace/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  test('check-out without check-in is rejected locally and by the server', () async {
    expect(attendanceRuleError(EventType.checkOut, TodayStatus.notCheckedIn), isNotNull);

    final backend = testBackend();
    final c = await makeController(backendClient(backend));
    await c.refresh();
    final outcome = await c.record(EventType.checkOut);
    expect(outcome.message, contains('check in before'));
    expect(c.events, isEmpty);

    final res = await backend.handle('POST', '/attendance/events', {}, {
      'eventId': 'x', 'type': 'check_out', 'timestamp': DateTime.now().toUtc().toIso8601String(),
      'latitude': backend.officeLat, 'longitude': backend.officeLng,
    });
    expect(res.status, 409);
  });

  test('repeated taps and retry after a lost response create one server record', () async {
    final backend = testBackend();
    final c = await makeController(backendClient(backend));
    await c.refresh();

    // Server accepts the event but the reply arrives after the client timeout.
    backend.scenario = 'timeout';
    final results = await Future.wait([c.record(EventType.checkIn), c.record(EventType.checkIn)]);
    expect(results[1].message, contains('in progress'));
    expect(c.events, hasLength(1));
    expect(c.events.single.status, SyncStatus.pending);
    expect(backend.eventsById, hasLength(1)); // server already has it

    backend.scenario = 'ok';
    await c.syncNow(); // retry with the same eventId
    expect(c.events.single.status, SyncStatus.synced);
    expect(backend.eventsById, hasLength(1));
    expect(c.today.status, TodayStatus.checkedIn);
  });

  test('duplicate attendance conflict marks the event Rejected', () async {
    final backend = testBackend();
    final c = await makeController(backendClient(backend));
    await c.refresh();
    backend.scenario = 'conflict';
    final outcome = await c.record(EventType.checkIn);
    expect(outcome.message, contains('rejected'));
    expect(c.events.single.status, SyncStatus.rejected);
    expect(c.today.status, TodayStatus.notCheckedIn);
  });

  test('pending events survive a restart and sync in order', () async {
    final backend = testBackend();
    final posted = <String>[];
    var c = await makeController(backendClient(backend, posted: posted));
    await c.refresh();

    backend.scenario = 'error'; // server unavailable: events queue up locally
    await c.record(EventType.checkIn);
    await c.record(EventType.checkOut);
    expect(c.events.map((e) => (e.type, e.status)), [
      (EventType.checkIn, SyncStatus.pending),
      (EventType.checkOut, SyncStatus.pending),
    ]);
    expect(backend.eventsById, isEmpty);

    // "Restart": drop the in-memory instance and reload from storage.
    SharedPreferences.resetStatic();
    backend.scenario = 'ok';
    posted.clear();
    c = await makeController(backendClient(backend, posted: posted));
    await c.init();

    expect(posted, ['check_in', 'check_out']);
    expect(c.events.every((e) => e.status == SyncStatus.synced), isTrue);
    expect(c.today.status, TodayStatus.checkedOut);
    expect(backend.eventsById, hasLength(2));
  });

  test('outside the geofence is refused', () async {
    final backend = testBackend();
    final c = await makeController(backendClient(backend));
    await c.refresh();
    c.location.mode = LocationMode.simulatedOutside;
    final outcome = await c.record(EventType.checkIn);
    expect(outcome.message, contains('within 200 m'));
    expect(c.events, isEmpty);
  });

  test('in-app backend state survives a save and restore', () async {
    final backend = testBackend();
    await backend.handle('POST', '/attendance/events', {}, {
      'eventId': 'e1', 'type': 'check_in', 'timestamp': DateTime.now().toUtc().toIso8601String(),
      'latitude': backend.officeLat, 'longitude': backend.officeLng,
    });
    final restored = testBackend()..restore(jsonDecode(jsonEncode(backend.toJson())) as Map<String, dynamic>);
    expect(restored.eventsById.keys, ['e1']);
    expect(restored.days, backend.days);
    // A replay after restart is still recognised, not a second record.
    final replay = await restored.handle('POST', '/attendance/events', {}, {
      'eventId': 'e1', 'type': 'check_in', 'timestamp': DateTime.now().toUtc().toIso8601String(),
      'latitude': backend.officeLat, 'longitude': backend.officeLng,
    });
    expect(replay.status, 200);
  });
}
