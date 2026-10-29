import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rebs_workspace/app/sync_service.dart';
import 'package:rebs_workspace/app/workspace_controller.dart';
import 'package:rebs_workspace/data/api_client.dart';
import 'package:rebs_workspace/data/local_store.dart';
import 'package:rebs_workspace/data/location_service.dart';
import 'package:rebs_workspace/domain/company_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_server/backend.dart';

/// Routes HTTP requests to an in-process [MockBackend], honouring its delays,
/// and records every POSTed attendance event type in [posted].
http.Client backendClient(MockBackend backend, {List<String>? posted}) => MockClient((req) async {
      final body = req.body.isEmpty ? null : jsonDecode(req.body);
      if (req.url.path == '/attendance/events') posted?.add((body as Map)['type'] as String);
      final res = await backend.handle(req.method, req.url.path, req.url.queryParameters, body);
      await Future<void>.delayed(res.delay);
      return http.Response(jsonEncode(res.body), res.status, headers: {'content-type': 'application/json'});
    });

/// A controller wired to [client] with a simulated in-office location.
Future<WorkspaceController> makeController(http.Client client) async {
  final store = LocalStore(await SharedPreferences.getInstance());
  final api = ApiClient('http://mock', client: client, timeout: const Duration(milliseconds: 100));
  return WorkspaceController(
    api: api,
    store: store,
    syncService: SyncService(api, store),
    location: LocationService()..mode = LocationMode.simulatedInside,
    clock: CompanyClock(3),
  );
}

/// Backend whose `timeout` scenario replies after the client has given up.
MockBackend testBackend() => MockBackend(timeoutDelay: const Duration(milliseconds: 300), slowDelay: Duration.zero);
