import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rebs_workspace/domain/models.dart';
import 'package:rebs_workspace/ui/dashboard_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows loading, then an error state when the first load fails', (tester) async {
    final c = await makeController(MockClient((_) => Future.delayed(
        const Duration(milliseconds: 50), () => http.Response('{"code":"SERVER_ERROR","message":"Boom."}', 500))));
    await tester.pumpWidget(MaterialApp(home: DashboardPage(controller: c)));
    c.refresh();
    await tester.pump();
    expect(find.text('Loading your data…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Failed to load data'), findsOneWidget);
    expect(find.textContaining('Boom.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('offline check-in shows Pending sync on the dashboard', (tester) async {
    final backend = testBackend();
    final c = await makeController(backendClient(backend));
    await tester.runAsync(c.refresh); // load + cache once while online

    backend.scenario = 'error';
    await tester.pumpWidget(MaterialApp(home: DashboardPage(controller: c)));
    await tester.runAsync(() => c.record(EventType.checkIn));
    await tester.pump();

    expect(find.text('Checked In'), findsOneWidget);
    expect(find.text('Pending sync'), findsWidgets);
    expect(find.text('Pending Sync'), findsOneWidget); // dashboard tile
    expect(find.text('1'), findsWidgets); // tile count and header badge
  });
}
