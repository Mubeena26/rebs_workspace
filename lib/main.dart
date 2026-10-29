import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/sync_service.dart';
import 'app/workspace_controller.dart';
import 'data/api_client.dart';
import 'data/local_store.dart';
import 'data/location_service.dart';
import 'domain/company_clock.dart';
import 'ui/home_shell.dart';

/// Android emulator reaches the host machine on 10.0.2.2. Override with
/// --dart-define=API_BASE_URL=http://YOUR_LAN_IP:8080 for a physical device.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

/// Used until /employee/me provides the company offset (Kuwait, UTC+3).
const defaultTzOffsetHours = int.fromEnvironment('COMPANY_TZ_OFFSET', defaultValue: 3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalStore(await SharedPreferences.getInstance());
  final api = ApiClient(apiBaseUrl);
  final controller = WorkspaceController(
    api: api,
    store: store,
    syncService: SyncService(api, store),
    location: LocationService(),
    clock: CompanyClock(defaultTzOffsetHours),
    connectivity: Connectivity().onConnectivityChanged.map((r) => r.any((c) => c != ConnectivityResult.none)).distinct(),
  );
  runApp(WorkspaceApp(controller: controller));
  controller.init();
}

class WorkspaceApp extends StatelessWidget {
  const WorkspaceApp({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'REBS Workspace',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: HomeShell(controller: controller),
      );
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB), brightness: brightness, dynamicSchemeVariant: DynamicSchemeVariant.fidelity);
  final light = brightness == Brightness.light;
  final card = light ? Colors.white : scheme.surfaceContainer;
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: light ? const Color(0xFFF6F7F9) : scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 50), shape: rounded)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 46), shape: rounded)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outlineVariant)),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: card, indicatorColor: scheme.primary.withValues(alpha: 0.12)),
  );
}
