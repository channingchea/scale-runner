import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_config.dart';
import 'social_models.dart';

/// The remote operations SocialService needs. Abstracted so tests can run
/// against an in-memory fake (house style: hand-rolled fakes + injection).
abstract class SocialBackend {
  bool get isSignedIn;
  String? get userId;

  Future<AuthResult> signInWithApple();
  Future<AuthResult> signInWithGoogle();
  Future<void> signOut();

  /// Deletes the auth account server-side (edge function) and signs out.
  Future<void> deleteAccount();

  Future<SocialProfile?> myProfile();
  Future<void> upsertProfile(String displayName, String avatarSeed);
  Future<void> upsertStreak(int current, int best, int totalDays);

  Future<List<FriendEntry>> fetchFriends();
  Future<void> removeFriend(String otherId);

  /// Creates an invite row and returns its code.
  Future<String> createInvite();
  Future<InvitePreview?> invitePreview(String code);

  /// Returns null on success, else a user-facing error message.
  Future<String?> acceptInvite(String code);

  /// Inserts applause; treats "already applauded today" as success.
  Future<void> applaud(String toId, int streakDays);

  /// Applause received (newest first, capped).
  Future<List<ApplauseReceived>> fetchApplause();

  /// Friend ids already applauded today (UTC), to disable their buttons.
  Future<Set<String>> applaudedTodayIds();

  Future<void> markApplauseSeen();

  /// Upserts the caller's current-week practice aggregate.
  Future<void> upsertWeeklyStats(WeeklyStat stat);

  /// A user's recent weekly aggregates, newest first (capped at [limit]).
  Future<List<WeeklyStat>> fetchWeeklyStats(String userId, {int limit});

  /// Upserts the caller's lifetime per-mode totals (for overview scores).
  Future<void> upsertModeStats(ModeStats stats);

  /// A user's per-mode totals, or null if they have none yet.
  Future<ModeStats?> fetchModeStats(String userId);
}

/// Production backend on supabase_flutter.
class SupabaseSocialBackend implements SocialBackend {
  SupabaseSocialBackend(this._client);

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

  // ---- Auth ----

  @override
  Future<AuthResult> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) return const AuthError('Apple sign-in failed.');
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      return AuthSuccess(suggestedName: credential.givenName);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthCancelled();
      }
      return AuthError(e.message);
    } catch (e) {
      return AuthError('$e');
    }
  }

  // GoogleSignIn.instance is a process-wide singleton whose initialize() must
  // be called exactly once, and the nonce can only be set there — so the nonce
  // is fixed for the life of the app run and reused by every sign-in attempt.
  static String? _googleRawNonce;
  static Future<void>? _googleInit;

  /// Initialises the Google SDK once and returns the raw nonce for Supabase.
  ///
  /// Google copies the nonce we give it into the ID token verbatim, while
  /// Supabase sha256s whatever we hand `signInWithIdToken` before comparing it
  /// to that claim. So Google gets the hash and Supabase gets the raw value —
  /// the same split as Apple above. Passing raw to both is what produced
  /// "Nonces mismatch" (400).
  Future<String> _initGoogleSignIn() async {
    final rawNonce = _googleRawNonce ??= _generateNonce();
    final pending = _googleInit ??= GoogleSignIn.instance.initialize(
      serverClientId: googleServerClientId,
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    try {
      await pending;
    } catch (_) {
      _googleInit = null; // a failed init shouldn't block later attempts
      rethrow;
    }
    return rawNonce;
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    try {
      final rawNonce = await _initGoogleSignIn();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return const AuthError('Google sign-in failed.');
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        nonce: rawNonce,
      );
      return AuthSuccess(suggestedName: account.displayName);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthCancelled();
      }
      return AuthError(e.description ?? 'Google sign-in failed.');
    } catch (e) {
      return AuthError('$e');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete_account');
    await _client.auth.signOut();
  }

  // ---- Profile / streak ----

  @override
  Future<SocialProfile?> myProfile() async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', _uid)
        .maybeSingle();
    return row == null ? null : SocialProfile.fromRow(row);
  }

  @override
  Future<void> upsertProfile(String displayName, String avatarSeed) async {
    await _client.from('profiles').upsert({
      'id': _uid,
      'display_name': displayName,
      'avatar_seed': avatarSeed,
    });
  }

  @override
  Future<void> upsertStreak(int current, int best, int totalDays) async {
    await _client.from('streaks').upsert({
      'user_id': _uid,
      'current': current,
      'best': best,
      'total_days': totalDays,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // ---- Friends ----

  @override
  Future<List<FriendEntry>> fetchFriends() async {
    final uid = _uid;
    final rows = await _client.from('friendships').select();
    final since = <String, DateTime>{};
    for (final row in rows) {
      final a = row['user_a'] as String;
      final b = row['user_b'] as String;
      final other = a == uid ? b : a;
      if (other == uid) continue;
      since[other] = DateTime.parse(row['created_at'] as String).toLocal();
    }
    if (since.isEmpty) return const [];
    final ids = since.keys.toList();
    final profileRows =
        await _client.from('profiles').select().inFilter('id', ids);
    final streakRows =
        await _client.from('streaks').select().inFilter('user_id', ids);
    final streaks = {
      for (final r in streakRows) r['user_id'] as String: r,
    };
    return [
      for (final p in profileRows)
        FriendEntry(
          profile: SocialProfile.fromRow(p),
          currentStreak: (streaks[p['id']]?['current'] as int?) ?? 0,
          bestStreak: (streaks[p['id']]?['best'] as int?) ?? 0,
          totalDays: (streaks[p['id']]?['total_days'] as int?) ?? 0,
          friendsSince: since[p['id']] ?? DateTime.now(),
        ),
    ];
  }

  @override
  Future<void> removeFriend(String otherId) async {
    final uid = _uid;
    final a = uid.compareTo(otherId) < 0 ? uid : otherId;
    final b = uid.compareTo(otherId) < 0 ? otherId : uid;
    await _client
        .from('friendships')
        .delete()
        .eq('user_a', a)
        .eq('user_b', b);
  }

  // ---- Invites ----

  @override
  Future<String> createInvite() async {
    final code = _generateInviteCode();
    await _client.from('invites').insert({
      'code': code,
      'inviter_id': _uid,
    });
    return code;
  }

  @override
  Future<InvitePreview?> invitePreview(String code) async {
    final rows =
        await _client.rpc('invite_preview', params: {'p_code': code});
    final list = rows as List;
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    return InvitePreview(
      inviterId: row['inviter_id'] as String,
      displayName: row['display_name'] as String? ?? 'Pianist',
      avatarSeed: row['avatar_seed'] as String? ?? '',
      currentStreak: row['current_streak'] as int? ?? 0,
    );
  }

  @override
  Future<String?> acceptInvite(String code) async {
    final res =
        await _client.rpc('accept_invite_tx', params: {'p_code': code});
    final map = (res as Map).cast<String, dynamic>();
    if (map['ok'] == true) return null;
    return switch (map['error']) {
      'invalid_code' => 'This invite link isn\'t valid.',
      'already_used' => 'This invite was already used.',
      'expired' => 'This invite has expired — ask for a new one.',
      'own_invite' => 'That\'s your own invite link!',
      _ => 'Couldn\'t accept the invite. Try again.',
    };
  }

  // ---- Applause / activity ----

  @override
  Future<void> applaud(String toId, int streakDays) async {
    try {
      await _client.from('applause').insert({
        'from_id': _uid,
        'to_id': toId,
        'streak_days': streakDays,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // unique violation = already today: ok
    }
  }

  @override
  Future<List<ApplauseReceived>> fetchApplause() async {
    final rows = await _client
        .from('applause')
        .select('streak_days, created_at, seen_at, '
            'from:profiles!applause_from_id_fkey(id, display_name, avatar_seed)')
        .eq('to_id', _uid)
        .order('created_at', ascending: false)
        .limit(50);
    return [
      for (final row in rows)
        ApplauseReceived(
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          from: row['from'] == null
              ? null
              : SocialProfile.fromRow(
                  (row['from'] as Map).cast<String, dynamic>()),
          streakDays: row['streak_days'] as int? ?? 0,
          seen: row['seen_at'] != null,
        ),
    ];
  }

  @override
  Future<Set<String>> applaudedTodayIds() async {
    final now = DateTime.now().toUtc();
    final dayStart =
        DateTime.utc(now.year, now.month, now.day).toIso8601String();
    final rows = await _client
        .from('applause')
        .select('to_id')
        .eq('from_id', _uid)
        .gte('created_at', dayStart);
    return {for (final r in rows) r['to_id'] as String};
  }

  @override
  Future<void> markApplauseSeen() async {
    await _client
        .from('applause')
        .update({'seen_at': DateTime.now().toUtc().toIso8601String()})
        .eq('to_id', _uid)
        .isFilter('seen_at', null);
  }

  // ---- Weekly stats ----

  @override
  Future<void> upsertWeeklyStats(WeeklyStat stat) async {
    await _client.from('weekly_stats').upsert(stat.toRow(_uid));
  }

  @override
  Future<List<WeeklyStat>> fetchWeeklyStats(String userId,
      {int limit = 12}) async {
    final rows = await _client
        .from('weekly_stats')
        .select()
        .eq('user_id', userId)
        .order('iso_week', ascending: false)
        .limit(limit);
    return [for (final r in rows) WeeklyStat.fromRow(r)];
  }

  // ---- Mode stats ----

  @override
  Future<void> upsertModeStats(ModeStats stats) async {
    await _client.from('mode_stats').upsert(stats.toRow(_uid));
  }

  @override
  Future<ModeStats?> fetchModeStats(String userId) async {
    final row = await _client
        .from('mode_stats')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : ModeStats.fromRow(row);
  }

  // ---- Helpers ----

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  /// 10 chars from an unambiguous alphabet (no 0/O/1/I/L).
  static String _generateInviteCode() {
    const charset = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
        10, (_) => charset[random.nextInt(charset.length)]).join();
  }
}

/// Whether native Apple sign-in is offered on this platform.
bool get appleSignInAvailable =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Google sign-in needs a configured server client ID (see social_config).
bool get googleSignInAvailable => googleServerClientId.isNotEmpty;
