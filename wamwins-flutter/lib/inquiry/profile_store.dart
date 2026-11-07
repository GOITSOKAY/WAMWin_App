import 'dart:convert';

import '../core/db.dart';
import '../core/ids.dart';
import '../tier/capabilities.dart';
import 'draft.dart';

const profileSteps = ['about', 'household', 'kitchens', 'family', 'food', 'review'];

/// Saves and resumes profiling. The full draft is kept per user (so profiling can resume even before the
/// household exists); once it exists, answers are also written as HOUSEHOLD_PROFILE answer rows (sync record).
class ProfileStore {
  ProfileStore(this.db, this.capabilities);
  final AppDb db;
  final Capabilities capabilities;

  String? _setting(String key) => db.first('SELECT value FROM local_setting WHERE key = ?', [key])?['value'] as String?;
  void _put(String key, String value) => db.run(
      "INSERT INTO local_setting(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')",
      [key, value]);

  String? householdIdFor(String userId) =>
      db.first("SELECT household_id FROM household_membership WHERE user_id = ? AND status = 'ACTIVE' AND deleted_at IS NULL", [userId])?['household_id'] as String?;
  bool isComplete(String userId) {
    final hh = householdIdFor(userId);
    return hh != null && db.first("SELECT 1 AS x FROM household WHERE id = ? AND onboarding_status = 'COMPLETED'", [hh]) != null;
  }
  String currentStep(String userId) => _setting('profile.step.$userId') ?? 'about';

  ProfileDraft loadDraft(DbRow user) {
    final raw = _setting('profile.draft.${user['id']}');
    final d = raw == null ? ProfileDraft() : ProfileDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    d.about.putIfAbsent('displayName', () => user['display_name'] as String);
    return d;
  }

  void save(DbRow user, ProfileDraft d, String nextStep) {
    final userId = user['id'] as String;
    db.transaction(() {
      _put('profile.draft.$userId', d.encode());
      _put('profile.step.$userId', nextStep);
      final hh = householdIdFor(userId);
      if (hh != null) _writeAnswers(userId, hh, d);
    });
  }

  String sessionFor(String userId, String householdId) {
    final existing = _setting('profile.session.$userId');
    if (existing != null && db.first('SELECT 1 AS x FROM questionnaire_session WHERE id = ?', [existing]) != null) return existing;
    final q = db.first("SELECT id FROM questionnaire WHERE code = 'HOUSEHOLD_PROFILE' AND status = 'PUBLISHED' ORDER BY version DESC LIMIT 1")!;
    final id = newId();
    db.run('INSERT INTO questionnaire_session(id, household_id, user_id, questionnaire_id) VALUES (?, ?, ?, ?)', [id, householdId, userId, q['id']]);
    _put('profile.session.$userId', id);
    return id;
  }

  void _writeAnswers(String userId, String hh, ProfileDraft d) {
    final session = sessionFor(userId, hh);
    final qs = {for (final r in db.select("SELECT q.id, q.code FROM question q JOIN questionnaire x ON x.id = q.questionnaire_id WHERE x.code = 'HOUSEHOLD_PROFILE'")) r['code'] as String: r['id'] as String};
    void answer(String code, String key, Object? value) {
      db.run("UPDATE answer SET superseded_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE session_id = ? AND question_id = ? AND repeat_key = ? AND superseded_at IS NULL",
          [session, qs[code], key]);
      db.run('INSERT INTO answer(id, household_id, session_id, question_id, repeat_key, text_value) VALUES (?, ?, ?, ?, ?, ?)',
          [newId(), hh, session, qs[code], key, jsonEncode(value)]);
    }
    answer('ABOUT_YOU', '', d.about);
    answer('HOUSEHOLD', '', {'name': d.householdName, 'size': d.householdSize});
    answer('KITCHENS', '', d.kitchens);
    for (final k in kitchenList(d)) {
      answer('STORAGE_UNITS', k.key, d.storage[k.key] ?? {});
      answer('COOKING_APPLIANCES', k.key, d.appliances[k.key] ?? []);
      answer('COOKWARE', k.key, d.cookware[k.key] ?? []);
      answer('UTENSILS', k.key, d.utensils[k.key] ?? []);
    }
    answer('HEALTH_CONSENT', '', d.healthConsent ?? false);
    answer('FAMILY_MEMBERS', '', d.family.map((m) => m.toJson()).toList());
    answer('FOOD_ON_HAND', '', d.food.map((f) => f.toJson()).toList());
  }

  /// Step 2: household + owner membership + WAMWins Basic entitlements. Idempotent.
  String ensureHousehold(DbRow user, ProfileDraft d) {
    final userId = user['id'] as String;
    return db.transaction(() {
      final existing = householdIdFor(userId);
      if (existing != null) {
        db.run("UPDATE household SET name = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND name <> ?",
            [d.householdName, existing, d.householdName]);
        return existing;
      }
      final hh = newId();
      db.run("INSERT INTO household(id, name, owner_user_id, onboarding_status) VALUES (?, ?, ?, 'IN_PROGRESS')", [hh, d.householdName, userId]);
      db.run("INSERT INTO household_membership(id, household_id, user_id, role_code, status, joined_at) VALUES (?, ?, ?, 'OWNER', 'ACTIVE', ?)",
          [newId(), hh, userId, nowIso()]);
      capabilities.startBasic(hh, userId);
      sessionFor(userId, hh);
      _writeAnswers(userId, hh, d);
      return hh;
    });
  }

  bool healthConsentGranted(String userId) =>
      (db.first("SELECT granted FROM consent_record WHERE user_id = ? AND consent_type = 'HEALTH_DATA_PROCESSING' ORDER BY recorded_at DESC, rowid DESC LIMIT 1", [userId])?['granted'] as int? ?? 0) == 1;
  void recordHealthConsent(String userId, bool granted) => db.run(
      "INSERT INTO consent_record(id, user_id, consent_type, document_version, granted) VALUES (?, ?, 'HEALTH_DATA_PROCESSING', '1', ?)", [newId(), userId, granted ? 1 : 0]);
}
