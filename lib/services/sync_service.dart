import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../database/local_database.dart';
import '../database/remote_database.dart';

class SyncService {
  final LocalDatabase _localDb;
  final RemoteDatabase _remoteDb;
  final Connectivity _connectivity = Connectivity();

  Timer? _syncTimer;
  bool _isSyncing = false;
  DateTime? lastSyncTime;
  int lastSyncCount = 0;

  bool get isSyncing => _isSyncing;

  SyncService(this._localDb, this._remoteDb);

  bool get isSyncEnabled => dotenv.env['SYNC_ENABLED']?.toLowerCase() == 'true';

  int get syncIntervalMinutes {
    final val = dotenv.env['SYNC_INTERVAL_MINUTES'];
    return int.tryParse(val ?? '15') ?? 15;
  }

  void startPeriodicSync() {
    if (!isSyncEnabled) return;
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      Duration(minutes: syncIntervalMinutes),
      (_) => syncNow(),
    );
    syncNow();
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<bool> _isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<SyncResult> syncNow() async {
    if (_isSyncing) return SyncResult(success: false, message: 'Sync already in progress');
    if (!isSyncEnabled) return SyncResult(success: false, message: 'Sync disabled');

    _isSyncing = true;
    try {
      if (!await _isOnline()) {
        return SyncResult(success: false, message: 'No internet connection');
      }

      var unsynced = await _localDb.getUnsyncedTransactions();

      // If everything looks synced locally, verify the remote actually has our data
      if (unsynced.isEmpty) {
        final needsResync = await _verifyRemoteIntegrity();
        if (needsResync) {
          unsynced = await _localDb.getUnsyncedTransactions();
        }
      }

      if (unsynced.isEmpty) {
        lastSyncTime = DateTime.now();
        lastSyncCount = 0;
        return SyncResult(success: true, message: 'Everything up to date', count: 0);
      }

      await _remoteDb.syncTransactions(unsynced);
      await _localDb.markSynced(unsynced.map((t) => t.id).toList());

      lastSyncTime = DateTime.now();
      lastSyncCount = unsynced.length;

      return SyncResult(
        success: true,
        message: 'Synced ${unsynced.length} transactions',
        count: unsynced.length,
      );
    } catch (e) {
      return SyncResult(success: false, message: 'Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Checks if the remote DB actually contains our first & last records and
  /// has a matching count. If anything is missing, marks all local records
  /// as unsynced so they get re-pushed.
  Future<bool> _verifyRemoteIntegrity() async {
    try {
      final localCount = await _localDb.getTransactionCount();
      if (localCount == 0) return false;

      final remoteCount = await _remoteDb.getRemoteCount();
      if (remoteCount < localCount) {
        await _localDb.markAllUnsynced();
        return true;
      }

      final firstId = await _localDb.getFirstTransactionId();
      final lastId = await _localDb.getLastTransactionId();

      if (firstId != null && !await _remoteDb.existsById(firstId)) {
        await _localDb.markAllUnsynced();
        return true;
      }
      if (lastId != null && !await _remoteDb.existsById(lastId)) {
        await _localDb.markAllUnsynced();
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    stopPeriodicSync();
    _remoteDb.close();
  }
}

class SyncResult {
  final bool success;
  final String message;
  final int count;

  SyncResult({required this.success, required this.message, this.count = 0});
}
