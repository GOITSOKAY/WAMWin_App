import 'dart:convert';

import '../core/db.dart';
import '../core/ids.dart';
import '../security/crypto.dart';
import 'notices.dart';

/// Consent ledger, person-level health access (with expiry), access log, privacy requests, retention and export.
/// Same rules as the web client (frontend/www/js/privacy/*.js) and PostgreSQL (privacy.relation, V028):
///   SELF      the person's own profile (family_member.linked_user_id)
///   GUARDIAN  household OWNER/ADMIN for children/teens and for profiles without their own account
///   GRANT     anyone else, only through an active access grant (category, VIEW or VIEW_EDIT, starts/expires)
class PrivacyService {
  PrivacyService(this.db);
  final AppDb db;

  static const minorBands = {'INFANT', 'TODDLER', 'CHILD', 'TEEN'};
  static const healthTableCategory = {
    'member_allergy': 'ALLERGIES', 'member_intolerance': 'ALLERGIES', 'member_dietary_requirement': 'DIETS',
    'member_health_food_requirement': 'HEALTH_GOALS', 'member_food_rule': 'FOOD_RULES', 'member_preference': 'MEAL_PREFERENCES',
  };
  String _now() => DateTime.now().toUtc().toIso8601String();

  // ---------------------------------------------------------------- consent ledger (append-only)
  DbRow? latestConsent(String userId, String type, [String? subjectRef]) => db.first(
      'SELECT * FROM consent_record WHERE user_id = ? AND consent_type = ? AND subject_ref IS ? ORDER BY recorded_at DESC, rowid DESC LIMIT 1',
      [userId, type, subjectRef]);
  /// Granted, and for the current document version (a new version asks again).
  bool hasConsent(String userId, String type, [String? subjectRef]) {
    final r = latestConsent(userId, type, subjectRef);
    return r != null && r['granted'] == 1 && r['document_version'] == consentDefs[type]!.version;
  }
  void recordConsent(String userId, String type, bool granted, {String? subjectRef, String method = 'POPUP', List<String>? shown}) {
    final def = consentDefs[type]!;
    db.run('INSERT INTO consent_record(id, user_id, consent_type, document_code, document_version, text_hash, method, subject_ref, user_agent, granted, recorded_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [newId(), userId, type, def.doc, def.version,
        shown == null ? null : sha256Hex(shown.join('\n')), method, subjectRef, 'wamwins-flutter', granted ? 1 : 0, _now()]);
  }
  List<DbRow> consentHistory(String userId) => db.select('SELECT * FROM consent_record WHERE user_id = ? ORDER BY recorded_at', [userId]);

  // ---------------------------------------------------------------- access rule
  static String grantStatus(DbRow g, [DateTime? now]) {
    final t = now ?? DateTime.now().toUtc();
    if (g['revoked_at'] != null) return 'REVOKED';
    if (DateTime.parse(g['starts_at'] as String).isAfter(t)) return 'SCHEDULED';
    final e = g['expires_at'] as String?;
    if (e != null && !DateTime.parse(e).isAfter(t)) return 'EXPIRED';
    return 'ACTIVE';
  }
  static List<String> categoriesOf(DbRow g) => (jsonDecode(g['categories'] as String) as List).cast<String>();

  static String? relation({required String userId, DbRow? membership, required DbRow? member, required List<DbRow> grants,
      String? category, DateTime? now, bool write = false}) {
    if (member == null) return null;
    if (member['linked_user_id'] != null && member['linked_user_id'] == userId) return 'SELF';
    final manager = membership != null && const {'OWNER', 'ADMIN'}.contains(membership['role_code']) && membership['status'] == 'ACTIVE';
    if (manager && (member['linked_user_id'] == null || minorBands.contains(member['age_band']))) return 'GUARDIAN';
    final ok = grants.any((g) => g['subject_member_id'] == member['id'] && g['grantee_user_id'] == userId && grantStatus(g, now) == 'ACTIVE'
        && (category == null || categoriesOf(g).contains(category)) && (!write || g['access_level'] == 'VIEW_EDIT'));
    return ok ? 'GRANT' : null;
  }

  DbRow? membershipOf(String userId) =>
      db.first("SELECT * FROM household_membership WHERE user_id = ? AND status = 'ACTIVE' AND deleted_at IS NULL", [userId]);
  List<DbRow> grants(String householdId) => db.select('SELECT * FROM access_grant WHERE household_id = ? ORDER BY granted_at DESC', [householdId]);
  /// True when [userId] may see [category] for [member] right now.
  bool canView(String userId, DbRow member, String category) {
    final m = membershipOf(userId);
    return relation(userId: userId, membership: m, member: member, grants: grants(member['household_id'] as String), category: category) != null;
  }

  // ---------------------------------------------------------------- grants
  DbRow createGrant({required String householdId, required DbRow subject, required String grantedBy, String? granteeUserId, String? granteeEmail,
      required String granteeName, required List<String> categories, String accessLevel = 'VIEW', required DateTime startsAt, DateTime? expiresAt, String? purpose}) {
    if (categories.isEmpty) throw ArgumentError('Choose at least one kind of detail to share.');
    if (expiresAt != null && !expiresAt.isAfter(startsAt)) throw ArgumentError('Access must end after it starts.');
    final id = newId();
    db.transaction(() {
      db.run('INSERT INTO access_grant(id, household_id, subject_member_id, grantee_user_id, grantee_email, grantee_name, categories, access_level, starts_at, expires_at, purpose, granted_by_user_id, granted_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [id, householdId, subject['id'], granteeUserId, granteeEmail?.toLowerCase(), granteeName,
          jsonEncode(categories.toSet().toList()), accessLevel, startsAt.toUtc().toIso8601String(), expiresAt?.toUtc().toIso8601String(), purpose, grantedBy, _now()]);
      _log(householdId, grantedBy, subject['id'] as String, 'GRANT_CREATED', categories, id);
    });
    return db.first('SELECT * FROM access_grant WHERE id = ?', [id])!;
  }
  void revokeGrant(DbRow g, String userId) => db.transaction(() {
        db.run('UPDATE access_grant SET revoked_at = ?, revoked_by_user_id = ? WHERE id = ? AND revoked_at IS NULL', [_now(), userId, g['id']]);
        _log(g['household_id'] as String, userId, g['subject_member_id'] as String, 'GRANT_REVOKED', categoriesOf(g), g['id'] as String);
      });

  // ---------------------------------------------------------------- accounting of disclosures
  void _log(String hh, String actor, String? subject, String action, List<String> categories, [String? grantId]) => db.run(
      'INSERT INTO access_log(id, household_id, actor_user_id, subject_member_id, action, categories, grant_id, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [newId(), hh, actor, subject, action, jsonEncode(categories), grantId, _now()]);
  void logView(String hh, String userId, List<DbRow> members, List<String> categories) {
    final gs = grants(hh);
    for (final m in members) {
      if (relation(userId: userId, member: m, grants: gs) != 'GRANT') continue;
      final g = gs.firstWhere((x) => x['subject_member_id'] == m['id'] && x['grantee_user_id'] == userId && grantStatus(x) == 'ACTIVE');
      _log(hh, userId, m['id'] as String, 'VIEWED', categories.where(categoriesOf(g).contains).toList(), g['id'] as String);
    }
  }
  List<DbRow> accessLog(String hh, {int limit = 25}) => db.select('SELECT * FROM access_log WHERE household_id = ? ORDER BY at DESC LIMIT ?', [hh, limit]);

  // ---------------------------------------------------------------- deletion, requests, retention, export
  int deleteHealthDetails(String hh, List<String> memberIds, String userId) {
    var n = 0;
    db.transaction(() {
      for (final t in healthTableCategory.keys) {
        for (final id in memberIds) {
          n += db.count('SELECT COUNT(*) FROM $t WHERE household_id = ? AND member_id = ?', [hh, id]);
          db.run('DELETE FROM $t WHERE household_id = ? AND member_id = ?', [hh, id]);
        }
      }
      for (final id in memberIds) { _log(hh, userId, id, 'HEALTH_DELETED', healthTableCategory.values.toSet().toList()); }
    });
    return n;
  }
  DbRow fileRequest({required String userId, String? householdId, required String type, String? details}) {
    final id = newId(), now = DateTime.now().toUtc();
    db.run('INSERT INTO privacy_request(id, user_id, household_id, request_type, details, requested_at, due_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, userId, householdId, type, details, now.toIso8601String(), now.add(const Duration(days: 45)).toIso8601String()]);
    return db.first('SELECT * FROM privacy_request WHERE id = ?', [id])!;
  }
  List<DbRow> requests(String userId) => db.select('SELECT * FROM privacy_request WHERE user_id = ? ORDER BY requested_at DESC', [userId]);
  /// Match explanations and who-ate-what older than 24 months are deleted (Privacy Notice, "How long we keep it").
  void applyRetention(String hh) {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 730)).toIso8601String();
    db.transaction(() {
      db.run('DELETE FROM match_run WHERE household_id = ? AND requested_at < ?', [hh, cutoff]);
      db.run('DELETE FROM meal_participant WHERE household_id = ? AND meal_record_id IN (SELECT id FROM meal_record WHERE household_id = ? AND created_at < ?)', [hh, hh, cutoff]);
    });
  }
  /// "Download a copy of my data": every household-scoped table plus the account's own rows (no secrets).
  String exportJson(DbRow user, String? hh) {
    const skip = {'local_auth_identity', 'local_session', 'schema_migration_history', 'sync_outbox'};
    final out = <String, Object?>{'exported_at': _now(), 'format': 'wamwins-export-1',
      'account': {'id': user['id'], 'email': user['email'], 'display_name': user['display_name']}, 'data': <String, Object?>{}};
    final data = out['data']! as Map<String, Object?>;
    data['consent_record'] = consentHistory(user['id'] as String);
    data['privacy_request'] = requests(user['id'] as String);
    if (hh != null) {
      for (final t in db.select("SELECT m.name AS t FROM sqlite_master m WHERE m.type = 'table' AND EXISTS (SELECT 1 FROM pragma_table_info(m.name) WHERE name = 'household_id')")) {
        final table = t['t'] as String;
        if (skip.contains(table)) continue;
        final rows = db.select('SELECT * FROM $table WHERE household_id = ?', [hh]);
        if (rows.isNotEmpty) data[table] = rows;
      }
    }
    return const JsonEncoder.withIndent('  ').convert(out);
  }
}
