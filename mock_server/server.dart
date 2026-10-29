// Run: dart run mock_server/server.dart
// Env: PORT (8080), OFFICE_LAT, OFFICE_LNG, OFFICE_RADIUS_M, COMPANY_TZ_OFFSET
import 'dart:convert';
import 'dart:io';

import 'backend.dart';

Future<void> main() async {
  final env = Platform.environment;
  final backend = MockBackend(
    officeLat: double.tryParse(env['OFFICE_LAT'] ?? '') ?? 29.3759,
    officeLng: double.tryParse(env['OFFICE_LNG'] ?? '') ?? 47.9774,
    radiusMeters: double.tryParse(env['OFFICE_RADIUS_M'] ?? '') ?? 200,
    tzOffsetHours: int.tryParse(env['COMPANY_TZ_OFFSET'] ?? '') ?? 3,
  );
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Mock REBS API on http://0.0.0.0:$port (scenario: ${backend.scenario})');

  await for (final req in server) {
    final raw = await utf8.decodeStream(req);
    Object? body;
    try {
      body = raw.isEmpty ? null : jsonDecode(raw);
    } on FormatException {
      body = null;
    }
    final res = await backend.handle(req.method, req.uri.path, req.uri.queryParameters, body);
    stdout.writeln('[${backend.scenario}] ${req.method} ${req.uri} -> ${res.status}');
    await Future<void>.delayed(res.delay);
    req.response
      ..statusCode = res.status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(res.body));
    await req.response.close().catchError((_) {}); // client may have timed out and gone away
  }
}
