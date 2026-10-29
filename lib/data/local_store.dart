import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// Persists the read cache and the attendance outbox.
// shortcut: whole lists rewritten as JSON in SharedPreferences; fine for one
// employee and a few dozen events, move to sqflite/drift for larger histories.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  static const _eventsKey = 'attendance_events';
  static const _maxSyncedEvents = 50;

  Object? readCache(String key) {
    final raw = _prefs.getString('cache.$key');
    return raw == null ? null : jsonDecode(raw);
  }

  Future<void> writeCache(String key, Object? value) => _prefs.setString('cache.$key', jsonEncode(value));

  /// Local events in creation order (the order they must be synced in).
  List<AttendanceEvent> events() {
    final raw = _prefs.getString(_eventsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => AttendanceEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Read-modify-write is synchronous up to setString, so within one isolate
  // concurrent add/update calls cannot lose each other's changes.
  Future<void> addEvent(AttendanceEvent e) => _saveEvents([...events(), e]);

  Future<void> updateEvent(AttendanceEvent e) => _saveEvents([for (final x in events()) x.id == e.id ? e : x]);

  /// Completes once the write has been flushed, so callers can treat the event as durable.
  Future<void> _saveEvents(List<AttendanceEvent> events) {
    // Keep every pending/rejected event; trim only the oldest synced ones.
    var excess = events.where((e) => e.status == SyncStatus.synced).length - _maxSyncedEvents;
    final kept = events.where((e) => e.status != SyncStatus.synced || excess-- <= 0).toList();
    return _prefs.setString(_eventsKey, jsonEncode(kept.map((e) => e.toJson()).toList()));
  }
}
