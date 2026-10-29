enum EventType {
  checkIn('check_in'),
  checkOut('check_out');

  const EventType(this.wire);
  final String wire;
  static EventType fromWire(String s) => values.firstWhere((t) => t.wire == s);
}

enum SyncStatus { pending, synced, rejected }

class Office {
  const Office({required this.name, required this.latitude, required this.longitude, required this.radiusMeters});
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  factory Office.fromJson(Map<String, dynamic> j) => Office(
        name: j['name'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        radiusMeters: (j['radiusMeters'] as num).toDouble(),
      );
}

class Employee {
  const Employee({required this.id, required this.name, required this.department, required this.office, required this.tzOffsetHours});
  final String id;
  final String name;
  final String department;
  final Office office;
  final int tzOffsetHours;

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as String,
        name: j['name'] as String,
        department: j['department'] as String,
        office: Office.fromJson(j['office'] as Map<String, dynamic>),
        tzOffsetHours: j['timezoneOffsetHours'] as int,
      );
}

/// A check-in/out created on this device. [id] is generated once at creation
/// and reused on every retry: it is the server's idempotency key.
class AttendanceEvent {
  const AttendanceEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.date,
    required this.latitude,
    required this.longitude,
    this.status = SyncStatus.pending,
    this.error,
    this.attempts = 0,
  });

  final String id;
  final EventType type;
  final DateTime timestamp; // UTC
  final String date; // company-local YYYY-MM-DD
  final double latitude;
  final double longitude;
  final SyncStatus status;
  final String? error;
  final int attempts;

  AttendanceEvent copyWith({SyncStatus? status, String? error, int? attempts}) => AttendanceEvent(
        id: id,
        type: type,
        timestamp: timestamp,
        date: date,
        latitude: latitude,
        longitude: longitude,
        status: status ?? this.status,
        error: error,
        attempts: attempts ?? this.attempts,
      );

  Map<String, dynamic> toApiJson() => {
        'eventId': id,
        'type': type.wire,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      };

  Map<String, dynamic> toJson() => {
        ...toApiJson(),
        'date': date,
        'status': status.name,
        'error': error,
        'attempts': attempts,
      };

  factory AttendanceEvent.fromJson(Map<String, dynamic> j) => AttendanceEvent(
        id: j['eventId'] as String,
        type: EventType.fromWire(j['type'] as String),
        timestamp: DateTime.parse(j['timestamp'] as String),
        date: j['date'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        status: SyncStatus.values.byName(j['status'] as String),
        error: j['error'] as String?,
        attempts: j['attempts'] as int? ?? 0,
      );
}

/// One day of attendance as returned by the server.
class AttendanceDay {
  const AttendanceDay({required this.date, this.checkIn, this.checkOut});
  final String date;
  final DateTime? checkIn;
  final DateTime? checkOut;

  factory AttendanceDay.fromJson(Map<String, dynamic> j) => AttendanceDay(
        date: j['date'] as String,
        checkIn: j['checkIn'] == null ? null : DateTime.parse(j['checkIn'] as String),
        checkOut: j['checkOut'] == null ? null : DateTime.parse(j['checkOut'] as String),
      );

  Map<String, dynamic> toJson() => {'date': date, 'checkIn': checkIn?.toIso8601String(), 'checkOut': checkOut?.toIso8601String()};
}

enum LeaveType { casual, sick }

enum LeaveStatus { pending, approved, rejected }

class LeaveRequest {
  const LeaveRequest({required this.id, required this.type, required this.startDate, required this.endDate, required this.reason, required this.status});
  final String id;
  final LeaveType type;
  final String startDate; // YYYY-MM-DD
  final String endDate;
  final String reason;
  final LeaveStatus status;

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
        id: j['id'] as String,
        type: LeaveType.values.byName(j['type'] as String),
        startDate: j['startDate'] as String,
        endDate: j['endDate'] as String,
        reason: j['reason'] as String,
        status: LeaveStatus.values.byName(j['status'] as String),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type.name, 'startDate': startDate, 'endDate': endDate, 'reason': reason, 'status': status.name};
}
