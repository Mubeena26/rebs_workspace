import 'dart:math';

import 'models.dart';

enum TodayStatus { notCheckedIn, checkedIn, checkedOut }

/// A day as the user should see it: server data overlaid with local events.
class DayRecord {
  DayRecord(this.date);
  final String date;
  DateTime? checkIn;
  DateTime? checkOut;
  SyncStatus? checkInSync;
  SyncStatus? checkOutSync;
  final List<AttendanceEvent> rejected = [];

  TodayStatus get status => checkIn == null
      ? TodayStatus.notCheckedIn
      : checkOut == null
          ? TodayStatus.checkedIn
          : TodayStatus.checkedOut;

  /// Elapsed working time; runs against [nowUtc] until checked out.
  Duration? worked(DateTime nowUtc) => checkIn == null ? null : (checkOut ?? nowUtc).difference(checkIn!);
}

/// Merges server days with locally created events, newest day first.
/// Rejected events are listed but never count towards the day's status.
List<DayRecord> mergeRecords(List<AttendanceDay> server, List<AttendanceEvent> local) {
  final byDate = <String, DayRecord>{};
  for (final d in server) {
    byDate[d.date] = DayRecord(d.date)
      ..checkIn = d.checkIn
      ..checkOut = d.checkOut
      ..checkInSync = d.checkIn == null ? null : SyncStatus.synced
      ..checkOutSync = d.checkOut == null ? null : SyncStatus.synced;
  }
  for (final e in local) {
    final r = byDate.putIfAbsent(e.date, () => DayRecord(e.date));
    if (e.status == SyncStatus.rejected) {
      r.rejected.add(e);
    } else if (e.type == EventType.checkIn && r.checkIn == null) {
      r
        ..checkIn = e.timestamp
        ..checkInSync = e.status;
    } else if (e.type == EventType.checkOut && r.checkOut == null) {
      r
        ..checkOut = e.timestamp
        ..checkOutSync = e.status;
    }
  }
  return byDate.values.toList()..sort((a, b) => b.date.compareTo(a.date));
}

/// Returns a user-facing reason why [type] is not allowed, or null if it is.
String? attendanceRuleError(EventType type, TodayStatus today) => switch ((type, today)) {
      (EventType.checkIn, TodayStatus.notCheckedIn) => null,
      (EventType.checkIn, _) => 'You have already checked in today.',
      (EventType.checkOut, TodayStatus.notCheckedIn) => 'You must check in before checking out.',
      (EventType.checkOut, TodayStatus.checkedIn) => null,
      (EventType.checkOut, TodayStatus.checkedOut) => 'You have already checked out today.',
    };

/// Great-circle distance in metres (haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * pi / 180;
  final a = pow(sin(rad(lat2 - lat1) / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(rad(lng2 - lng1) / 2), 2);
  return 6371000 * 2 * atan2(sqrt(a), sqrt(1 - a));
}
