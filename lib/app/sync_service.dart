import '../data/api_client.dart';
import '../data/local_store.dart';
import '../domain/models.dart';

class SyncResult {
  const SyncResult({this.synced = 0, this.rejected = 0, this.remaining = 0, this.error});
  final int synced;
  final int rejected;
  final int remaining;
  final String? error; // transient failure that stopped the run
}

/// Drains the attendance outbox to the server, oldest first.
///
/// - Events keep their client-generated id across retries, and the server
///   treats a known id as a replay, so a retry after a lost response
///   (timeout) never creates a second record.
/// - A transient failure stops the run so a check-out is never sent ahead
///   of its check-in; the remaining events stay pending for the next run.
/// - A definitive 4xx (e.g. attendance already exists) marks the event
///   Rejected and the run continues.
class SyncService {
  SyncService(this._api, this._store);
  final ApiClient _api;
  final LocalStore _store;

  Future<SyncResult>? _running;

  /// Concurrent callers (Sync Now, connectivity restored, new event) share one run.
  Future<SyncResult> sync() => _running ??= _run().whenComplete(() => _running = null);

  Future<SyncResult> _run() async {
    var synced = 0, rejected = 0;
    String? error;
    final tried = <String>{};
    while (true) {
      // Re-read each step so events added during the run are picked up in order.
      final e = _store.events().where((e) => e.status == SyncStatus.pending && !tried.contains(e.id)).firstOrNull;
      if (e == null) break;
      tried.add(e.id);
      try {
        await _api.postEvent(e);
        await _store.updateEvent(e.copyWith(status: SyncStatus.synced, attempts: e.attempts + 1));
        synced++;
      } on ApiException catch (ex) {
        if (ex.isTransient) {
          await _store.updateEvent(e.copyWith(error: ex.message, attempts: e.attempts + 1));
          error = ex.message;
          break;
        }
        await _store.updateEvent(e.copyWith(status: SyncStatus.rejected, error: ex.message, attempts: e.attempts + 1));
        rejected++;
      }
    }
    final remaining = _store.events().where((e) => e.status == SyncStatus.pending).length;
    return SyncResult(synced: synced, rejected: rejected, remaining: remaining, error: error);
  }
}
