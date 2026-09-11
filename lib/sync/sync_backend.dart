import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// One row of the user's synced library: a voicing, folder or tag. [data] is
/// the record's own JSON; [updatedAt] and [position] are the columns the
/// merge reads, so they win over any copy inside [data].
class LibraryRow {
  final String id;
  final String kind; // 'voicing' | 'folder' | 'tag'
  final Map<String, dynamic> data;
  final double position;
  final DateTime updatedAt;
  final bool deleted;

  const LibraryRow({
    required this.id,
    required this.kind,
    required this.data,
    required this.position,
    required this.updatedAt,
    this.deleted = false,
  });
}

/// One synced preference. Newest [updatedAt] wins per key.
class SettingRow {
  final String key;
  final String value;
  final DateTime updatedAt;

  const SettingRow(this.key, this.value, this.updatedAt);
}

/// One device's bucket for one stats key. Never merged server-side; clients
/// sum the buckets.
class StatsRow {
  final String deviceId;
  final String key;
  final Map<String, dynamic> data;
  final DateTime updatedAt;

  const StatsRow(this.deviceId, this.key, this.data, this.updatedAt);
}

/// The remote side of sync. Every call is scoped to the signed-in user by the
/// server's row-level security; the client never sees anyone else's rows.
/// Abstracted so tests can run two "devices" against one in-memory server.
abstract class SyncBackend {
  bool get isSignedIn;
  String? get userId;

  Future<List<LibraryRow>> pullLibrary();
  Future<void> pushLibrary(List<LibraryRow> rows);

  Future<List<SettingRow>> pullSettings();
  Future<void> pushSettings(List<SettingRow> rows);

  Future<List<StatsRow>> pullStats();
  Future<void> pushStats(List<StatsRow> rows);
}

/// Production backend on the same Supabase client the social features use.
class SupabaseSyncBackend implements SyncBackend {
  SupabaseSyncBackend(this._client);

  final SupabaseClient _client;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  String? get userId => _client.auth.currentUser?.id;

  String get _uid {
    final id = userId;
    if (id == null) throw StateError('not signed in');
    return id;
  }

  static DateTime _ts(dynamic v) => DateTime.parse(v as String);

  /// Upserts in batches so a big first push can't exceed a request limit.
  Future<void> _upsert(String table, List<Map<String, dynamic>> rows) async {
    for (var i = 0; i < rows.length; i += 200) {
      final chunk = rows.sublist(i, i + 200 > rows.length ? rows.length : i + 200);
      await _client.from(table).upsert(chunk);
    }
  }

  @override
  Future<List<LibraryRow>> pullLibrary() async {
    final rows = await _client.from('library_items').select().eq('user_id', _uid);
    return [
      for (final r in rows)
        LibraryRow(
          id: r['id'] as String,
          kind: r['kind'] as String,
          data: Map<String, dynamic>.from(r['data'] as Map),
          position: (r['position'] as num).toDouble(),
          updatedAt: _ts(r['updated_at']),
          deleted: r['deleted'] as bool,
        ),
    ];
  }

  @override
  Future<void> pushLibrary(List<LibraryRow> rows) => _upsert('library_items', [
        for (final r in rows)
          {
            'user_id': _uid,
            'id': r.id,
            'kind': r.kind,
            'data': r.data,
            'position': r.position,
            'updated_at': r.updatedAt.toUtc().toIso8601String(),
            'deleted': r.deleted,
          },
      ]);

  @override
  Future<List<SettingRow>> pullSettings() async {
    final rows = await _client.from('user_settings').select().eq('user_id', _uid);
    return [
      for (final r in rows)
        SettingRow(r['key'] as String, r['value'] as String, _ts(r['updated_at'])),
    ];
  }

  @override
  Future<void> pushSettings(List<SettingRow> rows) => _upsert('user_settings', [
        for (final r in rows)
          {
            'user_id': _uid,
            'key': r.key,
            'value': r.value,
            'updated_at': r.updatedAt.toUtc().toIso8601String(),
          },
      ]);

  @override
  Future<List<StatsRow>> pullStats() async {
    final rows = await _client.from('device_stats').select().eq('user_id', _uid);
    return [
      for (final r in rows)
        StatsRow(
          r['device_id'] as String,
          r['key'] as String,
          Map<String, dynamic>.from(r['data'] as Map),
          _ts(r['updated_at']),
        ),
    ];
  }

  @override
  Future<void> pushStats(List<StatsRow> rows) => _upsert('device_stats', [
        for (final r in rows)
          {
            'user_id': _uid,
            'device_id': r.deviceId,
            'key': r.key,
            'data': r.data,
            'updated_at': r.updatedAt.toUtc().toIso8601String(),
          },
      ]);
}
