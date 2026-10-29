import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int? status; // null = no response (offline, timeout)
  final String code;
  final String message;

  /// Transient failures are retried later; anything else is a final answer.
  bool get isTransient => status == null || status! >= 500 || status == 408 || status == 429;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 5)}) : _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers['content-type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _client.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw ApiException(null, 'TIMEOUT', 'The server did not respond in time.');
    } catch (e) {
      // SocketException / ClientException: no connectivity or server unreachable.
      throw ApiException(null, 'NETWORK', 'Unable to reach the server.');
    }
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw ApiException(res.statusCode, 'BAD_RESPONSE', 'Unexpected server response (${res.statusCode}).');
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, '${json['code'] ?? 'ERROR'}', '${json['message'] ?? 'Request failed.'}');
    }
    return json;
  }

  Future<Map<String, dynamic>> getEmployeeJson() => _send('GET', '/employee/me');

  Future<List<Map<String, dynamic>>> getAttendanceJson(String month) async =>
      ((await _send('GET', '/attendance', query: {'month': month}))['records'] as List).cast<Map<String, dynamic>>();

  Future<void> postEvent(AttendanceEvent e) => _send('POST', '/attendance/events', body: e.toApiJson());

  Future<Map<String, dynamic>> getLeaveBalanceJson() async => (await _send('GET', '/leave/balance'))['available'] as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> getLeaveRequestsJson() async =>
      ((await _send('GET', '/leave/requests'))['requests'] as List).cast<Map<String, dynamic>>();

  Future<void> postLeave(Map<String, dynamic> body) => _send('POST', '/leave/requests', body: body);

  Future<void> setScenario(String name) => _send('POST', '/__mock/scenario', body: {'name': name});
}
