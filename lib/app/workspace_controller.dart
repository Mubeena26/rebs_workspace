import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/local_store.dart';
import '../data/location_service.dart';
import '../domain/attendance_rules.dart';
import '../domain/company_clock.dart';
import '../domain/leave_rules.dart';
import '../domain/models.dart';
import 'sync_service.dart';

typedef Outcome = ({String message, bool openSettings});

/// Single source of UI state. Widgets read fields and call methods; all
/// decisions live here or in the pure domain functions it calls.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.api,
    required this.store,
    required this.syncService,
    required this.location,
    required this.clock,
    this.connectivity,
  });

  final ApiClient api;
  final LocalStore store;
  final SyncService syncService;
  final LocationService location;
  final CompanyClock clock;
  final Stream<bool>? connectivity;
  StreamSubscription<bool>? _sub;

  Employee? employee;
  List<AttendanceDay> serverDays = [];
  Map<LeaveType, int> balance = {};
  List<LeaveRequest> leaves = [];
  List<AttendanceEvent> events = [];
  DateTime? lastUpdated;

  bool loading = false; // no cached data yet and a fetch is running
  String? loadError; // no cached data and the fetch failed
  bool offline = false;
  String? staleReason; // cached data shown because the last refresh failed
  bool busy = false; // attendance action in flight; blocks repeated taps
  bool syncing = false;
  ({double lat, double lng})? position; // last known location, for the geofence preview
  String? locationError;

  List<DayRecord> get records => mergeRecords(serverDays, events);
  DayRecord get today => records.firstWhere((r) => r.date == clock.today(), orElse: () => DayRecord(clock.today()));
  List<DayRecord> get recent => records.take(5).toList();
  int get pendingCount => events.where((e) => e.status == SyncStatus.pending).length;
  bool get hasData => employee != null;

  /// Metres from the office at the last location check.
  double? get distance {
    final p = position, o = employee?.office;
    return p == null || o == null ? null : distanceMeters(p.lat, p.lng, o.latitude, o.longitude);
  }

  Future<void> init() async {
    _loadCache();
    notifyListeners();
    _sub = connectivity?.listen((online) {
      if (online) {
        syncNow();
      } else {
        offline = true;
        notifyListeners();
      }
    });
    await syncNow();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _loadCache() {
    final emp = store.readCache('employee');
    if (emp != null) {
      employee = Employee.fromJson(emp as Map<String, dynamic>);
      clock.offsetHours = employee!.tzOffsetHours;
    }
    serverDays = [for (final d in (store.readCache('attendance') as List? ?? [])) AttendanceDay.fromJson(d as Map<String, dynamic>)];
    balance = _parseBalance(store.readCache('balance') as Map<String, dynamic>? ?? {});
    leaves = [for (final r in (store.readCache('leaves') as List? ?? [])) LeaveRequest.fromJson(r as Map<String, dynamic>)];
    final updated = store.readCache('updatedAt');
    lastUpdated = updated == null ? null : DateTime.parse(updated as String);
    events = store.events();
  }

  Map<LeaveType, int> _parseBalance(Map<String, dynamic> j) => {
        for (final t in LeaveType.values)
          if (j[t.name] != null) t: j[t.name] as int,
      };

  Future<void> refresh() async {
    loading = !hasData;
    loadError = null;
    notifyListeners();
    try {
      final emp = await api.getEmployeeJson();
      final employee = Employee.fromJson(emp);
      clock.offsetHours = employee.tzOffsetHours;
      final thisMonth = clock.today().substring(0, 7);
      final prev = DateTime.parse('$thisMonth-01').subtract(const Duration(days: 1)).toIso8601String().substring(0, 7);
      final results = await Future.wait([
        api.getAttendanceJson(thisMonth),
        api.getAttendanceJson(prev),
        api.getLeaveBalanceJson(),
        api.getLeaveRequestsJson(),
      ]);
      final days = [...results[0] as List, ...results[1] as List];
      this.employee = employee;
      serverDays = days.map((d) => AttendanceDay.fromJson(d as Map<String, dynamic>)).toList();
      balance = _parseBalance(results[2] as Map<String, dynamic>);
      leaves = (results[3] as List).map((r) => LeaveRequest.fromJson(r as Map<String, dynamic>)).toList();
      lastUpdated = clock.nowUtc();
      await Future.wait([
        store.writeCache('employee', emp),
        store.writeCache('attendance', days),
        store.writeCache('balance', results[2]),
        store.writeCache('leaves', results[3]),
        store.writeCache('updatedAt', lastUpdated!.toIso8601String()),
      ]);
      offline = false;
      staleReason = null;
    } on ApiException catch (e) {
      offline = e.status == null;
      if (hasData) {
        staleReason = e.message;
      } else {
        loadError = e.message;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Pushes pending events, then reloads server state.
  Future<SyncResult> syncNow() async {
    syncing = true;
    notifyListeners();
    final result = await syncService.sync();
    events = store.events();
    syncing = false;
    await refresh();
    return result;
  }

  Future<Outcome> record(EventType type) async {
    if (busy) return (message: 'Please wait, the previous action is still in progress.', openSettings: false);
    busy = true;
    notifyListeners();
    try {
      return await _record(type);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Outcome> _record(EventType type) async {
    final emp = employee;
    if (emp == null) {
      return (message: 'Office configuration has not been downloaded yet. Connect once and refresh.', openSettings: false);
    }
    final ruleError = attendanceRuleError(type, today.status);
    if (ruleError != null) return (message: ruleError, openSettings: false);

    final ({double lat, double lng}) pos;
    try {
      pos = await location.current(emp.office);
    } on LocationException catch (e) {
      return (message: e.message, openSettings: e.openSettings);
    }
    position = pos;
    locationError = null;
    final distance = this.distance!;
    if (distance > emp.office.radiusMeters) {
      return (
        message: 'You are ${distance.round()} m from ${emp.office.name}. '
            'Attendance can only be recorded within ${emp.office.radiusMeters.round()} m of the office.',
        openSettings: false,
      );
    }

    final now = clock.nowUtc();
    final event = AttendanceEvent(id: newId(), type: type, timestamp: now, date: clock.dateOf(now), latitude: pos.lat, longitude: pos.lng);
    await store.addEvent(event); // durable before we report anything
    events = store.events();
    notifyListeners();

    await syncNow();
    final saved = events.firstWhere((e) => e.id == event.id);
    final label = type == EventType.checkIn ? 'Check-in' : 'Check-out';
    return switch (saved.status) {
      SyncStatus.synced => (message: '$label recorded.', openSettings: false),
      SyncStatus.pending => (message: '$label saved offline. It will sync when the connection returns.', openSettings: false),
      SyncStatus.rejected => (message: '$label rejected by server: ${saved.error}', openSettings: false),
    };
  }

  String? validateLeaveForm({LeaveType? type, String? start, String? end, required String reason}) => validateLeave(
      type: type, start: start, end: end, reason: reason, today: clock.today(), available: balance, existing: leaves);

  /// Returns an error message, or null on success. [requestId] is created once
  /// per form so a resubmit after a lost response is not a second request.
  Future<String?> submitLeave({required String requestId, LeaveType? type, String? start, String? end, required String reason}) async {
    final error = validateLeaveForm(type: type, start: start, end: end, reason: reason);
    if (error != null) return error;
    try {
      await api.postLeave({'requestId': requestId, 'type': type!.name, 'startDate': start, 'endDate': end, 'reason': reason.trim()});
    } on ApiException catch (e) {
      return e.status == null ? 'Leave submission needs a connection. ${e.message}' : e.message;
    }
    await refresh();
    return null;
  }

  Future<String> setScenario(String name) async {
    try {
      await api.setScenario(name);
      return 'Mock scenario: $name';
    } on ApiException catch (e) {
      return 'Could not change scenario: ${e.message}';
    }
  }

  /// Refreshes [position] for the geofence preview without recording anything.
  Future<void> checkLocation() async {
    final emp = employee;
    if (emp == null) return;
    try {
      position = await location.current(emp.office);
      locationError = null;
    } on LocationException catch (e) {
      position = null;
      locationError = e.message;
    }
    notifyListeners();
  }

  void setLocationMode(LocationMode mode) {
    location.mode = mode;
    checkLocation();
  }
}

/// Random UUID v4.
String newId() {
  final b = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
