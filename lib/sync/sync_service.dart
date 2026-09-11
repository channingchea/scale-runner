import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../quiz/quiz_settings.dart';
import '../streak/streak_service.dart';
import '../theory/voicings.dart';
import 'sync_backend.dart';

enum SyncState { idle, syncing, waiting }

/// Keeps the signed-in user's library the same on every device.
///
/// Local storage stays the source of truth: every write lands in
/// SharedPreferences first and the app never waits on the network. A sync is
/// then a full pull, a per-record merge (newest `updatedAt` wins, deletes
/// carried by tombstones), a local apply of what the other device changed,
/// and a push of what this device changed. It runs on launch, on foreground,
/// after sign-in, and a couple of seconds after any local edit. Failures are
/// swallowed and retried with backoff; nothing here ever surfaces an error
/// to the user beyond the "Waiting for connection" state in Settings.
///
/// Signed out, every entry point is a no-op.
class SyncService extends ChangeNotifier {
  SyncService({
    SyncBackend? backend,
    QuizSettings? settings,
    StreakService? streak,
    this.debounce = const Duration(seconds: 2),
    this.retryDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
    ],
  })  : _backend = backend,
        _streak = streak, // ignore: prefer_initializing_formals
        _injectedSettings = settings {
    if (backend != null) attach(backend);
  }

  static final SyncService instance = SyncService();

  final Duration debounce;
  final List<Duration> retryDelays;

  SyncBackend? _backend;
  final QuizSettings? _injectedSettings;
  final StreakService? _streak;

  /// Runs after every successful pull with the merged totals. SocialService
  /// uses it to keep the friends-facing rows (streak, this week, per-mode
  /// scores) equal to the sum over all devices.
  Future<void> Function()? onAggregates;

  SyncState _state = SyncState.idle;
  DateTime? _lastSyncedAt;
  Future<void>? _current;
  bool _runAgain = false;
  int _failures = 0;
  Timer? _debounceTimer;
  Timer? _retryTimer;

  SyncState get state => _state;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isSignedIn => _backend?.isSignedIn ?? false;

  Future<QuizSettings> get _settings async =>
      _injectedSettings ?? await QuizSettings.load();

  /// Point the service at a backend and start listening for local edits.
  /// Called once by SocialService when its Supabase client is ready.
  void attach(SyncBackend backend) {
    _backend = backend;
    QuizSettings.onSyncedDataChanged = scheduleSync;
    unawaited(_restoreLastSynced());
  }

  /// Show "Last synced" from before this launch until a fresh sync lands.
  Future<void> _restoreLastSynced() async {
    try {
      final at = await (await _settings).syncLastAt();
      if (at != null && _lastSyncedAt == null) {
        _lastSyncedAt = at;
        notifyListeners();
      }
    } catch (_) {
      // Prefs unavailable this early (tests, or a broken plugin): harmless.
    }
  }

  /// A local edit happened: sync soon, coalescing a burst of edits into one.
  void scheduleSync() {
    if (!isSignedIn) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, sync);
  }

  /// Sign-in and sign-out hooks for SocialService.
  Future<void> onSignedIn() => sync();

  Future<void> onSignedOut() async {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _failures = 0;
    _lastSyncedAt = null;
    _state = SyncState.idle;
    final settings = await _settings;
    await settings.setSyncLastAt(null);
    await settings.clearRemoteStats();
    notifyListeners();
  }

  /// Sync now. Never throws. If a sync is already running, one more runs as
  /// soon as it finishes (so a mid-run edit isn't missed) and the returned
  /// future completes after that follow-up.
  Future<void> sync() {
    final backend = _backend;
    if (backend == null || !backend.isSignedIn) return Future.value();
    if (_current case final running?) {
      _runAgain = true;
      return running;
    }
    return _current = _runLoop(backend);
  }

  Future<void> _runLoop(SyncBackend backend) async {
    do {
      _runAgain = false;
      await _runOnce(backend);
    } while (_runAgain);
    _current = null;
  }

  Future<void> _runOnce(SyncBackend backend) async {
    _retryTimer?.cancel();
    _state = SyncState.syncing;
    notifyListeners();
    try {
      final changed = await _syncLibrary(backend);
      await _syncSettings(backend);
      await _syncStats(backend);
      await onAggregates?.call();
      _lastSyncedAt = DateTime.now();
      await (await _settings).setSyncLastAt(_lastSyncedAt);
      _failures = 0;
      _state = SyncState.idle;
      if (changed) _libraryChanged = true;
    } catch (e) {
      debugPrint('sync failed: $e');
      _state = SyncState.waiting;
      if (_failures < retryDelays.length) {
        _retryTimer = Timer(retryDelays[_failures], sync);
      }
      _failures++;
    }
    notifyListeners();
    _libraryChanged = false;
  }

  /// True during the [notifyListeners] that follows a sync which changed the
  /// local library. The Voicings screen reloads on it.
  bool get libraryChanged => _libraryChanged;
  bool _libraryChanged = false;

  // ---- Library ----

  /// Returns whether anything was written locally.
  Future<bool> _syncLibrary(SyncBackend backend) async {
    final settings = await _settings;
    final remote = await backend.pullLibrary();
    final voicings = await settings.savedVoicings();
    final folders = await settings.voicingFolders();
    final tags = await settings.voicingTags();
    final tombstones = await settings.deletedRecords();

    final local = <String, LibraryRow>{
      for (final v in voicings) v.id: _rowOfVoicing(v),
      for (final f in folders) f.id: _rowOfLabel(f, 'folder'),
      for (final t in tags) t.id: _rowOfLabel(t, 'tag'),
    };
    final tombById = {for (final t in tombstones) t.id: t};
    final remoteById = {for (final r in remote) r.id: r};

    final toPush = <LibraryRow>[];
    final applyV = <VoicingSpec>[];
    final applyF = <VoicingLabel>[];
    final applyT = <VoicingLabel>[];
    final deleteIds = <String>{};
    final prune = <String>[];

    void apply(LibraryRow r) {
      switch (r.kind) {
        case 'voicing':
          final v = VoicingSpec.decode(jsonEncode(r.data));
          if (v != null) {
            applyV.add(v.copyWith(updatedAt: r.updatedAt, position: r.position));
          }
        case 'folder':
        case 'tag':
          final l = VoicingLabel.decode(jsonEncode(r.data));
          if (l != null) {
            (r.kind == 'folder' ? applyF : applyT)
                .add(l.copyWith(updatedAt: r.updatedAt, position: r.position));
          }
      }
    }

    for (final r in remote) {
      final t = tombById[r.id];
      if (t != null) {
        // We deleted it. Our delete wins unless the other device edited it
        // after we did; then the edit comes back.
        if (!r.deleted && r.updatedAt.isAfter(t.deletedAt)) {
          apply(r);
        } else if (!r.deleted) {
          toPush.add(_tombstoneRow(t, kind: r.kind));
        }
        prune.add(t.id);
        continue;
      }
      final l = local[r.id];
      if (l == null) {
        if (!r.deleted) apply(r);
      } else if (r.deleted) {
        if (r.updatedAt.isAfter(l.updatedAt)) {
          deleteIds.add(r.id);
        } else {
          toPush.add(l);
        }
      } else if (r.updatedAt.isAfter(l.updatedAt)) {
        apply(r);
      } else if (l.updatedAt.isAfter(r.updatedAt)) {
        toPush.add(l);
      }
    }
    for (final e in local.entries) {
      if (!remoteById.containsKey(e.key)) toPush.add(e.value);
    }
    for (final t in tombstones) {
      if (!remoteById.containsKey(t.id)) {
        toPush.add(_tombstoneRow(t));
        prune.add(t.id);
      }
    }

    final changed = applyV.isNotEmpty ||
        applyF.isNotEmpty ||
        applyT.isNotEmpty ||
        deleteIds.isNotEmpty;
    if (changed) {
      await settings.applyRemoteLibrary(
        voicings: applyV,
        folders: applyF,
        tags: applyT,
        deletedIds: deleteIds,
      );
    }
    if (toPush.isNotEmpty) await backend.pushLibrary(toPush);
    if (prune.isNotEmpty) await settings.pruneDeletedRecords(prune);
    return changed;
  }

  // ---- Practice settings ----

  /// Per key, newest wins. A key only one side has is copied to the other.
  Future<void> _syncSettings(SyncBackend backend) async {
    final settings = await _settings;
    final remote = await backend.pullSettings();
    final local = {for (final r in await settings.syncedSettingsSnapshot()) r.key: r};
    final apply = <SettingRow>[];
    final toPush = <SettingRow>[];
    for (final r in remote) {
      final l = local.remove(r.key);
      if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
        apply.add(r);
      } else if (l.updatedAt.isAfter(r.updatedAt)) {
        toPush.add(l);
      }
    }
    toPush.addAll(local.values); // only this device has these
    if (apply.isNotEmpty) await settings.applyRemoteSettings(apply);
    if (toPush.isNotEmpty) await backend.pushSettings(toPush);
  }

  // ---- Stats ----

  /// Upload this device's buckets, cache everyone else's, and adopt a streak
  /// practiced more recently elsewhere.
  Future<void> _syncStats(SyncBackend backend) async {
    final settings = await _settings;
    final deviceId = await settings.deviceId();
    final now = DateTime.now();
    final own = await settings.ownStatsSnapshot();
    await backend.pushStats([
      for (final e in own.entries) StatsRow(deviceId, e.key, e.value, now),
    ]);
    await settings.applyRemoteStats(await backend.pullStats(), deviceId);
    final newest = await settings.newestRemoteStreak();
    if (newest != null) {
      await (_streak ?? StreakService.instance).adoptSynced(
        current: newest.current,
        best: newest.best,
        total: newest.total,
        lastDate: newest.last,
      );
    }
  }

  static LibraryRow _rowOfVoicing(VoicingSpec v) => LibraryRow(
        id: v.id,
        kind: 'voicing',
        data: jsonDecode(v.encode()) as Map<String, dynamic>,
        position: v.position,
        updatedAt: v.updatedAt,
      );

  static LibraryRow _rowOfLabel(VoicingLabel l, String kind) => LibraryRow(
        id: l.id,
        kind: kind,
        data: jsonDecode(l.encode()) as Map<String, dynamic>,
        position: l.position,
        updatedAt: l.updatedAt,
      );

  static LibraryRow _tombstoneRow(DeletedRecord t, {String? kind}) =>
      LibraryRow(
        id: t.id,
        kind: kind ?? t.kind,
        data: const {},
        position: 0,
        updatedAt: t.deletedAt,
        deleted: true,
      );

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
