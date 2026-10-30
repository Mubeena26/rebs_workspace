# REBS Workspace — offline-capable employee attendance & leave

A Flutter app (Android/iOS) for one preconfigured employee to view attendance, check in/out inside an office geofence, and apply for leave. It keeps working offline and syncs reliably. It ships with a local mock HTTP API that has repeatable failure scenarios.

## Quick start

**Just install the APK.** By default the mock API runs *inside the app* (`lib/data/in_app_api.dart`), so the APK works on any phone or emulator with no server, no Wi-Fi setup and no tunnel. It still behaves like a remote server: requests fail while the device is offline (use airplane mode to demo offline), and its data survives app restarts. Mock scenarios and simulated location are in the app's developer sheet (tune icon on Home).

```bash
flutter pub get
flutter run                                  # in-app mock API (default)
flutter test

# Optional: a real HTTP mock server instead of the in-app one
dart run mock_server/server.dart            # http://0.0.0.0:8080
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080          # Android emulator
flutter run --dart-define=API_BASE_URL=http://localhost:8080         # iOS simulator
flutter run --dart-define=API_BASE_URL=http://<your-computer-ip>:8080 # physical device, same Wi-Fi
# On iPhone, tap "Allow" on the Local Network prompt.
```

Debug APK: `flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk` (uses the in-app mock API).

### Configuration

| What | Where | Default |
|---|---|---|
| Office coordinates / radius | env `OFFICE_LAT`, `OFFICE_LNG`, `OFFICE_RADIUS_M` on the mock server, or `MockBackend` defaults for the in-app API (delivered to the app via `/employee/me`) | 29.3759, 47.9774 (Kuwait City), 200 m |
| Company timezone | env `COMPANY_TZ_OFFSET` on the server; app fallback `--dart-define=COMPANY_TZ_OFFSET=3` | UTC+3 |
| API URL | `--dart-define=API_BASE_URL=...` | empty = in-app mock API |
| Port | env `PORT` | 8080 |

The office location comes from the server, not from an app constant. In production the server owns the geofence, and the app caches it for offline use.

### Simulating location (for reviewers)

Tap the **tune icon** (top right of the dashboard) to open the developer sheet. **Location source** offers:
- *Device GPS*: real location with the real permission flow.
- *Simulated: inside office*: office + ~55 m.
- *Simulated: outside office*: office + ~500 m, which shows the "you are N m away" message.

You can also start with `--dart-define=SIM_LOCATION=inside|outside`. On an emulator, you can also set a GPS fix in *Extended controls → Location*.

### Mock scenarios

Switch scenarios from the same developer sheet, or with curl:

```bash
curl -XPOST localhost:8080/__mock/scenario -d '{"name":"timeout"}'
curl -XPOST localhost:8080/__mock/reset      # back to seed data, scenario ok
```

| Scenario | Behaviour |
|---|---|
| `ok` | Normal responses |
| `slow` | Every response is delayed 3 s (shows loading states; still within the 5 s client timeout) |
| `timeout` | The request is **processed**, but the reply is held 20 s. The client times out at 5 s, which models "the server accepted it but the client never heard back" |
| `error` | Every request returns 500 without processing |
| `conflict` | A new check-in returns 409 `ATTENDANCE_EXISTS` (as if recorded from another device) |
| `leave_reject` | Leave submission returns 422 `POLICY_VIOLATION`, even when it passes local validation |

The server's own rules also give real conflicts, for example check-out without check-in → 409 `CHECK_IN_REQUIRED`, overlapping leave → 422 `OVERLAP`.

### API contract

| Method | Endpoint | Notes |
|---|---|---|
| GET | `/employee/me` | Employee **plus office geofence and timezone offset** (so they are server-configured) |
| GET | `/attendance?month=YYYY-MM` | `{records: [{date, checkIn, checkOut}]}`, timestamps ISO-8601 UTC |
| POST | `/attendance/events` | `{eventId, type: check_in\|check_out, timestamp, latitude, longitude}` → 201, or 200 `replayed: true` for a known `eventId` |
| GET | `/leave/balance` | `{available: {casual, sick}, entitlement: {...}}` |
| GET | `/leave/requests` | `{requests: [...]}` |
| POST | `/leave/requests` | `{requestId, type, startDate, endDate, reason}` |

Errors are `{code, message}`: 400 malformed, 409 attendance conflict, 422 validation, 500 server.

The one change to the suggested contract: the client sends **no `date`** with attendance events. The server derives the working day from the timestamp in company time, so a client cannot misattribute a day.

## Architecture

```
lib/
  domain/   pure Dart: models, attendance rules, leave rules, company clock   (no Flutter, no IO)
  data/     ApiClient (http), LocalStore (SharedPreferences), LocationService (geolocator),
            in_app_api.dart (routes ApiClient's HTTP requests to the mock backend in-process)
  mock/     backend.dart: the mock API logic (pure Dart), shared by the server, the app and tests
  app/      SyncService (outbox), WorkspaceController (ChangeNotifier, the UI state)
  ui/       widgets only: render controller state, call controller methods
mock_server/
  server.dart   dart:io HttpServer wrapper around lib/mock/backend.dart
```

**State management: a plain `ChangeNotifier` plus `ListenableBuilder`.** This is one screen tree with one source of state, so Provider/Riverpod/Bloc would add a dependency and ceremony without adding capability. The controller is constructed in `main()` and passed down explicitly. Tests construct it with fake transports. If the app grew to several features, I would move to Riverpod for scoped dependency injection.

Widgets contain no business decisions. The rules live in `domain/` as pure functions: `attendanceRuleError`, `mergeRecords`, `validateLeave`, `distanceMeters`. The controller orchestrates them.

### Dependencies

| Package | Why |
|---|---|
| `http` | HTTP client; its `MockClient` lets tests run against the real mock backend in-process |
| `shared_preferences` | Persistent cache + outbox (see trade-offs) |
| `geolocator` | GPS + permission states (denied / denied forever / service off) |
| `connectivity_plus` | Triggers a sync when the network returns |

No codegen, no DI framework, no UUID package (v4 ids come from `Random.secure`, about 10 lines).

## Offline & synchronization design

**Outbox pattern.** A check-in/out is always written to the local outbox first (`LocalStore.addEvent`, awaited until persisted), then the app tries to sync. Online and offline use the same code path, so the offline path is not a rarely tested special case.

**Event identity and idempotency.**
- Each event gets a UUID v4 `eventId` **once, when the user taps**. It is persisted with the event and sent unchanged on every retry.
- The server stores accepted events by `eventId`. If an id it already knows arrives again, the server returns the original result (`200, replayed: true`) and creates nothing new.
- This makes the timeout case safe. If the server accepted the event but the reply was lost, the client keeps the event *Pending*, and the next sync resends the same id. The server answers "already have it", and the client marks the event *Synced*. The result is one record, not two.
- Leave submissions use the same idea: one `requestId` per form instance.

**Ordering.** Events are stored in creation order and sent strictly one at a time, oldest first. A **transient** failure (no response, timeout, 5xx, 408/429) stops the run, so a check-out is never sent before its check-in. A **definitive** 4xx marks that event *Rejected* (with the server's message) and the run continues. The server then decides what that means for the next event. For example, a check-out whose check-in was rejected gets `CHECK_IN_REQUIRED`.

**Statuses.** *Pending sync* / *Synced* / *Rejected* show as chips on today's card and in the recent records list. The app bar badge shows the pending count. Rejected events never count towards today's status, so the user can try again.

**When sync runs:** app start, the **Sync Now** button (app bar or banner), pull-to-refresh, right after each new event, and when `connectivity_plus` reports the network is back. Concurrent triggers share one in-flight run.

**Concurrency safety.** `LocalStore` does per-event read-modify-write. SharedPreferences reads are synchronous in memory, so within the single UI isolate an event added during a sync run cannot be overwritten. The sync loop re-reads the outbox at each step, so it also picks up events added mid-run, in order.

**Read cache.** After a successful refresh, the employee, office config, two months of attendance, the leave balance and the leave requests are cached. When offline (or on server errors) the app shows the cache with a banner and the last-updated time. Pending local events are overlaid on the server data (`mergeRecords`).

**Duplicate taps.** The controller has a `busy` guard: a second tap while an action is in flight is ignored, and the buttons are disabled. After the first event is saved, the local rule refuses a second check-in. The server's idempotency covers anything that gets past both.

## What a production server must re-validate

The device checks exist for user experience only. A modified client can bypass all of them, so the server must enforce:
1. **Geofence.** Recompute the distance from the submitted coordinates against the server-side office config. Better still, add anti-spoofing signals (mock-location flag, Play Integrity/App Attest, IP/Wi-Fi heuristics), because GPS coordinates are client-supplied.
2. **Working day from the timestamp, in company timezone.** Never trust a client-sent "date".
3. **Timestamp plausibility.** Reject times in the future. Accept past times only within a bounded offline window (the mock uses 7 days). Consider comparing against server receive time and the device clock skew.
4. **One check-in per day; check-out only after check-in, and later than it; no second check-out.**
5. **Idempotency by `eventId`**, scoped per employee, with a unique constraint in the database, not just an in-memory check.
6. **Authorization.** The employee identity comes from the auth token, never from the request body.
7. **Leave:** start ≥ company today, end ≥ start, reason length, balance, overlap with pending/approved requests (in a transaction, so two concurrent submissions cannot both pass), and `requestId` idempotency.

## Assumptions

- One employee, no login. The office and timezone are delivered by `/employee/me`.
- One attendance session per day, no overnight shifts. Today is defined in company time, not device time.
- Leave counts calendar days inclusively. "Available balance" = entitlement − pending − approved days (computed server-side).
- The company timezone is a fixed UTC offset (no DST). Kuwait is the default.
- On first launch the app must be online once to download the office config. Without it, a geofence check is impossible, so check-in is blocked with an explanatory message.

## Completed

- Dashboard: employee, today's status, check-in/out times, live elapsed duration, leave balance, latest five records. Loading, empty, error, offline and stale-data states.
- Check-in/out with rules, GPS capture, 200 m geofence, all permission/availability failures (with an "open Settings" action when permission is permanently denied), and location simulation.
- Offline outbox: persistence across restarts, Pending/Synced/Rejected, Sync Now, auto-sync on reconnect, ordering, conflict handling, timeout-safe retries.
- Leave: form with all five validations, server error display, request list with statuses, offline viewing.
- Mock API with the six scenarios. Tests (10) cover every required case plus widget tests.

## Tests

`flutter test`:
- `attendance_test.dart`: check-out without check-in rejected (local + server); double tap + timeout + retry → exactly one server record; conflict → Rejected; pending events survive a simulated restart and sync in order (`check_in`, `check_out`); geofence refusal.
- `leave_test.dart`: overlap rejected (adjacent dates and rejected requests do not block); the other leave rules; server rejection surfaced, then an idempotent resubmit.
- `dashboard_widget_test.dart`: loading → error state; offline check-in shows **Pending sync**.

The tests run against the **real mock backend logic** (`lib/mock/backend.dart`) through `http`'s `MockClient`, so the idempotency tests exercise the actual server dedupe rather than a stub.

## Limitations & trade-offs

- **SharedPreferences as the store.** It is simple, atomic per key and sufficient for one employee and a few dozen events. Synced events are trimmed to the last 50. For larger histories or multi-user devices, move to SQLite (drift/sqflite) with a proper outbox table.
- **No background sync while the app is terminated** (out of scope). WorkManager/BGTaskScheduler would be the next step.
- **Fixed-offset timezone.** Use `package:timezone` for regions with DST.
- **Connectivity ≠ internet.** `connectivity_plus` only reports that an interface is up. Real reachability is inferred from request failures, which are shown as offline. There is no exponential backoff; retries happen on the triggers listed above.
- **Leave submission is online-only**, as specified. An offline submit shows a clear message and the form keeps its contents.
- **The mock server is in-memory**, so restarting it resets data (the app's cache and outbox survive).
- **No anti-spoofing** of GPS on the device (see server section).
- The UI is Material 3 with three tabs (Home, Attendance, Leave). Layouts are checked for overflow at 320, 360 and 412 dp widths; tablets are not specially tuned.
- **The geofence preview is a schematic** (office, 200 m circle, your position to scale) drawn with `CustomPaint`, not a map. A real map (google_maps_flutter / flutter_map) would add an API key or tile dependency for no gain in correctness.

## Time spent

_TODO: fill in actual hours._

## AI disclosure

This project was built with the help of an AI coding assistant (Claude Code), which generated a large share of the code and documentation. I reviewed all of it and can explain and modify every part.
