import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock/backend.dart';

/// Serves the mock REBS API inside the app so the APK works with no server.
/// It still behaves like a remote server: requests fail while the device is
/// offline, and its data is saved so it survives app restarts.
// shortcut: demo/review only; production builds must set API_BASE_URL to a real server.
http.Client inAppApiClient(SharedPreferences prefs) {
  const key = 'in_app_mock_backend';
  final backend = MockBackend();
  final saved = prefs.getString(key);
  if (saved != null) backend.restore(jsonDecode(saved) as Map<String, dynamic>);

  return MockClient((req) async {
    final net = await Connectivity().checkConnectivity();
    if (net.every((c) => c == ConnectivityResult.none)) throw http.ClientException('No connectivity', req.url);
    final body = req.body.isEmpty ? null : jsonDecode(req.body);
    final res = await backend.handle(req.method, req.url.path, req.url.queryParameters, body);
    await prefs.setString(key, jsonEncode(backend.toJson()));
    // Delay after saving: the `timeout` scenario means "accepted, reply lost".
    await Future<void>.delayed(res.delay);
    return http.Response(jsonEncode(res.body), res.status, headers: {'content-type': 'application/json'});
  });
}
