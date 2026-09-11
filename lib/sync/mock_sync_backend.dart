import 'sync_backend.dart';

/// An in-memory stand-in for the Supabase tables. Several [MockSyncBackend]s
/// can share one server, each playing a different device for the same user,
/// which is how the sync tests simulate two phones.
class MockSyncServer {
  final Map<String, LibraryRow> library = {};
  final Map<String, SettingRow> settings = {};
  final Map<String, StatsRow> stats = {}; // key: '$deviceId/$key'

  /// The clock clamp from the real trigger: a timestamp more than 5 minutes
  /// ahead of [now] is pulled back to it.
  DateTime Function() now = DateTime.now;

  DateTime _clamp(DateTime t) {
    final cap = now().add(const Duration(minutes: 5));
    return t.isAfter(cap) ? cap : t;
  }

  void upsertLibrary(LibraryRow r) => library[r.id] = LibraryRow(
        id: r.id,
        kind: r.kind,
        data: r.data,
        position: r.position,
        updatedAt: _clamp(r.updatedAt),
        deleted: r.deleted,
      );

  void upsertSetting(SettingRow r) =>
      settings[r.key] = SettingRow(r.key, r.value, _clamp(r.updatedAt));

  void upsertStats(StatsRow r) => stats['${r.deviceId}/${r.key}'] =
      StatsRow(r.deviceId, r.key, r.data, _clamp(r.updatedAt));
}

class MockSyncBackend implements SyncBackend {
  MockSyncBackend(this.server, {this.userId = 'user-1'});

  final MockSyncServer server;

  /// Flip to simulate being offline: every call throws.
  bool offline = false;

  /// Flip to simulate signing out.
  bool signedIn = true;

  int pushes = 0;
  int pulls = 0;

  @override
  bool get isSignedIn => signedIn;

  @override
  final String userId;

  void _check() {
    if (offline) throw StateError('offline');
  }

  @override
  Future<List<LibraryRow>> pullLibrary() async {
    _check();
    pulls++;
    return server.library.values.toList();
  }

  @override
  Future<void> pushLibrary(List<LibraryRow> rows) async {
    _check();
    pushes++;
    rows.forEach(server.upsertLibrary);
  }

  @override
  Future<List<SettingRow>> pullSettings() async {
    _check();
    return server.settings.values.toList();
  }

  @override
  Future<void> pushSettings(List<SettingRow> rows) async {
    _check();
    rows.forEach(server.upsertSetting);
  }

  @override
  Future<List<StatsRow>> pullStats() async {
    _check();
    return server.stats.values.toList();
  }

  @override
  Future<void> pushStats(List<StatsRow> rows) async {
    _check();
    rows.forEach(server.upsertStats);
  }
}
