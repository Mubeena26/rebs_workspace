// Mock REBS backend. Pure Dart (no Flutter) so it runs both behind a real
// HttpServer (server.dart) and in-process in tests via http's MockClient.
import 'dart:math';

class MockResponse {
  MockResponse(this.status, this.body, {this.delay = Duration.zero});
  final int status;
  final Object? body;

  /// Applied by the transport *after* the request was processed, so the
  /// `timeout` scenario models "server accepted, client never saw the reply".
  final Duration delay;
}

/// Repeatable scenarios, switched at runtime via POST /__mock/scenario.
const scenarios = ['ok', 'slow', 'timeout', 'error', 'conflict', 'leave_reject'];

class MockBackend {
  MockBackend({
    this.officeLat = 29.3759,
    this.officeLng = 47.9774,
    this.radiusMeters = 200,
    this.tzOffsetHours = 3,
    DateTime Function()? now,
    this.slowDelay = const Duration(seconds: 3),
    this.timeoutDelay = const Duration(seconds: 20),
  }) : _now = now ?? DateTime.now {
    _seed();
  }

  final double officeLat;
  final double officeLng;
  final double radiusMeters;
  final int tzOffsetHours;
  final DateTime Function() _now;
  final Duration slowDelay;
  final Duration timeoutDelay;

  String scenario = 'ok';

  /// Every accepted event, keyed by the client-generated eventId.
  final Map<String, Map<String, dynamic>> eventsById = {};

  /// date (YYYY-MM-DD, company time) -> {checkIn, checkOut} ISO UTC strings.
  final Map<String, Map<String, String?>> days = {};

  final List<Map<String, dynamic>> leaveRequests = [];
  final Map<String, int> entitlement = {'casual': 10, 'sick': 7};

  String _dateOf(DateTime utc) =>
      utc.toUtc().add(Duration(hours: tzOffsetHours)).toIso8601String().substring(0, 10);

  String _addDays(String date, int n) =>
      DateTime.parse(date).add(Duration(days: n)).toIso8601String().substring(0, 10);

  void _seed() {
    final today = _dateOf(_now());
    // Six past working days of history, 08:00-17:00 company time.
    for (var i = 1; i <= 6; i++) {
      final d = _addDays(today, -i);
      final start = DateTime.parse('${d}T08:0$i:00Z').subtract(Duration(hours: tzOffsetHours));
      days[d] = {
        'checkIn': start.toIso8601String(),
        'checkOut': start.add(const Duration(hours: 9)).toIso8601String(),
      };
    }
    leaveRequests.addAll([
      _leave('LR-1', 'casual', _addDays(today, -40), _addDays(today, -38), 'Family wedding out of town', 'approved'),
      _leave('LR-2', 'sick', _addDays(today, -20), _addDays(today, -20), 'Flu, doctor advised rest', 'rejected'),
      _leave('LR-3', 'casual', _addDays(today, 20), _addDays(today, 21), 'Personal errands abroad', 'pending'),
    ]);
  }

  Map<String, dynamic> _leave(String id, String type, String start, String end, String reason, String status) => {
        'id': id,
        'type': type,
        'startDate': start,
        'endDate': end,
        'days': _days(start, end),
        'reason': reason,
        'status': status,
      };

  int _days(String start, String end) => DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;

  Map<String, int> _available() => {
        for (final type in entitlement.keys)
          type: entitlement[type]! -
              leaveRequests
                  .where((r) => r['type'] == type && r['status'] != 'rejected')
                  .fold<int>(0, (sum, r) => sum + (r['days'] as int)),
      };

  MockResponse _error(int status, String code, String message, {Duration delay = Duration.zero}) =>
      MockResponse(status, {'code': code, 'message': message}, delay: delay);

  Future<MockResponse> handle(String method, String path, Map<String, String> query, Object? body) async {
    if (path.startsWith('/__mock/')) return _control(method, path, body);

    final delay = switch (scenario) {
      'slow' => slowDelay,
      'timeout' => timeoutDelay,
      _ => Duration.zero,
    };
    if (scenario == 'error') return _error(500, 'SERVER_ERROR', 'Simulated server failure.');

    final res = _route(method, path, query, body);
    return MockResponse(res.status, res.body, delay: delay);
  }

  MockResponse _control(String method, String path, Object? body) {
    if (path == '/__mock/scenario' && method == 'POST') {
      final name = (body as Map?)?['name'];
      if (!scenarios.contains(name)) return _error(400, 'BAD_SCENARIO', 'Use one of $scenarios');
      scenario = name as String;
    } else if (path == '/__mock/reset' && method == 'POST') {
      scenario = 'ok';
      eventsById.clear();
      days.clear();
      leaveRequests.clear();
      _seed();
    }
    return MockResponse(200, {'scenario': scenario, 'available': scenarios});
  }

  MockResponse _route(String method, String path, Map<String, String> query, Object? body) {
    switch ((method, path)) {
      case ('GET', '/employee/me'):
        return MockResponse(200, {
          'id': 'EMP-1042',
          'name': 'Sara Al-Mutairi',
          'department': 'Finance & Accounts',
          'timezoneOffsetHours': tzOffsetHours,
          'office': {'name': 'REBS HQ', 'latitude': officeLat, 'longitude': officeLng, 'radiusMeters': radiusMeters},
        });
      case ('GET', '/attendance'):
        final month = query['month'] ?? '';
        final records = days.entries
            .where((e) => e.key.startsWith(month))
            .map((e) => {'date': e.key, ...e.value})
            .toList()
          ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
        return MockResponse(200, {'month': month, 'records': records});
      case ('POST', '/attendance/events'):
        return _postEvent(body);
      case ('GET', '/leave/balance'):
        return MockResponse(200, {'available': _available(), 'entitlement': entitlement});
      case ('GET', '/leave/requests'):
        return MockResponse(200, {'requests': leaveRequests.reversed.toList()});
      case ('POST', '/leave/requests'):
        return _postLeave(body);
    }
    return _error(404, 'NOT_FOUND', 'No route for $method $path');
  }

  MockResponse _postEvent(Object? body) {
    if (body is! Map) return _error(400, 'BAD_REQUEST', 'JSON body required.');
    final id = body['eventId'];
    final type = body['type'];
    final ts = DateTime.tryParse('${body['timestamp']}');
    final lat = body['latitude'];
    final lng = body['longitude'];
    if (id is! String || id.isEmpty || !(type == 'check_in' || type == 'check_out') || ts == null || lat is! num || lng is! num) {
      return _error(400, 'BAD_REQUEST', 'eventId, type, timestamp, latitude and longitude are required.');
    }

    // Idempotency: a replay of an already-accepted event returns the original
    // result instead of creating a second record.
    final existing = eventsById[id];
    if (existing != null) return MockResponse(200, {'event': existing, 'replayed': true});

    final now = _now().toUtc();
    if (ts.isAfter(now.add(const Duration(minutes: 5)))) {
      return _error(422, 'INVALID_TIMESTAMP', 'Event time is in the future.');
    }
    if (ts.isBefore(now.subtract(const Duration(days: 7)))) {
      return _error(422, 'INVALID_TIMESTAMP', 'Event is too old to be accepted.');
    }
    if (_distance(lat.toDouble(), lng.toDouble(), officeLat, officeLng) > radiusMeters) {
      return _error(422, 'OUTSIDE_GEOFENCE', 'Location is outside the permitted office area.');
    }

    // The server derives the working day from the timestamp; it never trusts a client date.
    final date = _dateOf(ts);
    final day = days[date];
    if (type == 'check_in') {
      if (day?['checkIn'] != null || scenario == 'conflict') {
        return _error(409, 'ATTENDANCE_EXISTS', 'Attendance already exists for $date (recorded from another device).');
      }
      days[date] = {'checkIn': ts.toIso8601String(), 'checkOut': null};
    } else {
      if (day?['checkIn'] == null) return _error(409, 'CHECK_IN_REQUIRED', 'Cannot check out before checking in on $date.');
      if (day!['checkOut'] != null) return _error(409, 'ATTENDANCE_EXISTS', 'Check-out already recorded for $date.');
      if (ts.isBefore(DateTime.parse(day['checkIn']!))) {
        return _error(422, 'INVALID_TIMESTAMP', 'Check-out cannot be earlier than check-in.');
      }
      day['checkOut'] = ts.toIso8601String();
    }
    final event = {'eventId': id, 'type': type, 'timestamp': ts.toIso8601String(), 'date': date};
    eventsById[id] = event;
    return MockResponse(201, {'event': event, 'replayed': false});
  }

  MockResponse _postLeave(Object? body) {
    if (body is! Map) return _error(400, 'BAD_REQUEST', 'JSON body required.');
    final requestId = body['requestId'];
    final dup = leaveRequests.where((r) => r['id'] == requestId).firstOrNull;
    if (dup != null) return MockResponse(200, dup);

    if (scenario == 'leave_reject') {
      return _error(422, 'POLICY_VIOLATION', 'Leave during month-end closing needs manager pre-approval.');
    }
    final type = body['type'];
    final start = '${body['startDate']}';
    final end = '${body['endDate']}';
    final reason = '${body['reason'] ?? ''}';
    if (requestId is! String || !entitlement.containsKey(type) || DateTime.tryParse(start) == null || DateTime.tryParse(end) == null) {
      return _error(400, 'BAD_REQUEST', 'requestId, type, startDate and endDate are required.');
    }
    if (start.compareTo(_dateOf(_now())) < 0) return _error(422, 'START_IN_PAST', 'Start date is before today.');
    if (end.compareTo(start) < 0) return _error(422, 'END_BEFORE_START', 'End date is before start date.');
    if (reason.replaceAll(RegExp(r'\s'), '').length < 10) {
      return _error(422, 'REASON_TOO_SHORT', 'Reason needs at least 10 non-whitespace characters.');
    }
    final n = _days(start, end);
    if (n > _available()[type]!) return _error(422, 'INSUFFICIENT_BALANCE', 'Requested $n days exceeds available balance.');
    final overlap = leaveRequests.any((r) =>
        r['status'] != 'rejected' && start.compareTo(r['endDate']) <= 0 && end.compareTo(r['startDate']) >= 0);
    if (overlap) return _error(422, 'OVERLAP', 'Dates overlap an existing pending or approved request.');

    final created = _leave(requestId, type as String, start, end, reason, 'pending');
    leaveRequests.add(created);
    return MockResponse(201, created);
  }

  static double _distance(double lat1, double lng1, double lat2, double lng2) {
    double rad(double d) => d * pi / 180;
    final a = pow(sin(rad(lat2 - lat1) / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(rad(lng2 - lng1) / 2), 2);
    return 6371000 * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
