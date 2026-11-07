import '../core/db.dart';
import '../core/ids.dart';
import 'catalog.dart';
import 'draft.dart';

class ProvisionResult {
  int kitchens = 0, storage = 0, sections = 0, equipment = 0, members = 0, items = 0;
  bool get createdStructure => kitchens + storage > 0;
}

/// "Create my household": answers become records - ONLY what the answers describe - in one transaction.
/// Every created record is traced in profile_provisioning_record by a stable draft key, so running it again
/// ("Update my answers") adds what is new and never duplicates. The shared database triggers enforce the
/// inventory ledger: items are created at 0 and filled by a MANUAL_ADD transaction.
class Provisioner {
  Provisioner(this.db, this.catalog);
  final AppDb db;
  final Catalog catalog;

  ProvisionResult provision({required DbRow user, required String householdId, required String sessionId, required ProfileDraft d}) {
    final r = ProvisionResult();
    final hh = householdId;
    String once(String draftKey, String table, String Function() create) {
      final existing = db.first('SELECT created_entity_id FROM profile_provisioning_record WHERE household_id = ? AND draft_key = ?', [hh, draftKey]);
      if (existing != null) return existing['created_entity_id'] as String;
      final id = create();
      db.run('INSERT INTO profile_provisioning_record(id, household_id, session_id, draft_key, created_entity_table, created_entity_id) VALUES (?, ?, ?, ?, ?, ?)',
          [newId(), hh, sessionId, draftKey, table, id]);
      return id;
    }
    String moduleId(String code) => db.first('SELECT id FROM module_definition WHERE module_code = ?', [code])!['id'] as String;
    void moduleInstance(String code, String? resourceId, String name) => once('module:$code:${resourceId ?? ''}', 'household_module_instance', () {
          final id = newId();
          db.run("INSERT INTO household_module_instance(id, household_id, module_id, resource_type, resource_id, display_name, current_status) VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE')",
              [id, hh, moduleId(code), resourceId == null ? null : 'storage_instance', resourceId, name]);
          return id;
        });

    db.transaction(() {
      final storageIds = <String, String>{};
      final kitchens = kitchenList(d);
      for (var ki = 0; ki < kitchens.length; ki++) {
        final k = kitchens[ki];
        final kitchenId = once('kitchen:${k.key}', 'kitchen', () {
          final id = newId();
          db.run("INSERT INTO kitchen(id, household_id, name, kitchen_type, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')", [id, hh, k.name, k.type, ki]);
          r.kitchens++;
          return id;
        });
        final units = storageList(d, catalog, k.key);
        for (var si = 0; si < units.length; si++) {
          final s = units[si];
          final sid = once('storage:${s.key}', 'storage_instance', () {
            final id = newId();
            db.run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
                [id, hh, kitchenId, s.type, s.name, s.zone, si]);
            final templates = catalog.sectionTemplates[s.type] ?? const <(String, String, String)>[];
            for (var oi = 0; oi < templates.length; oi++) {
              db.run("INSERT INTO storage_section(id, household_id, storage_instance_id, section_kind, name, ordinal, template_id, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'SYSTEM_DEFAULT')",
                  [newId(), hh, id, templates[oi].$1, templates[oi].$2, oi, templates[oi].$3]);
              r.sections++;
            }
            r.storage++;
            return id;
          });
          storageIds[s.key] = sid;
          moduleInstance('STORAGE', sid, s.name);
        }
        for (final (table, codes, list) in [
          ('household_appliance', d.appliances[k.key] ?? const <String>[], catalog.appliances),
          ('household_cookware', d.cookware[k.key] ?? const <String>[], catalog.cookware),
          ('household_utensil', d.utensils[k.key] ?? const <String>[], catalog.utensils),
        ]) {
          for (final code in codes) {
            once('equipment:${k.key}:$code', table, () {
              final id = newId();
              db.run("INSERT INTO $table(id, household_id, kitchen_id, equipment_type_code, name, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')",
                  [id, hh, kitchenId, code, catalog.nameOf(list, code)]);
              r.equipment++;
              return id;
            });
          }
        }
      }

      for (final m in d.family) {
        final memberId = once('member:${m.key}', 'family_member', () {
          final id = newId();
          db.run("INSERT INTO family_member(id, household_id, linked_user_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 'MANUAL')",
              [id, hh, m.isMe ? user['id'] : null, m.name, m.isMe ? 'SELF' : m.relationship, m.ageBand]);
          r.members++;
          return id;
        });
        db.run("UPDATE family_member SET display_name = ?, relationship = ?, age_band = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') "
            'WHERE id = ? AND (display_name <> ? OR relationship <> ? OR age_band <> ?)',
            [m.name, m.isMe ? 'SELF' : m.relationship, m.ageBand, memberId, m.name, m.isMe ? 'SELF' : m.relationship, m.ageBand]);
        // Health rows reflect the latest answers and are stored only with consent.
        if (d.healthConsent == true) {
          db.run('DELETE FROM member_allergy WHERE member_id = ?', [memberId]);
          db.run('DELETE FROM member_dietary_requirement WHERE member_id = ?', [memberId]);
          db.run('DELETE FROM member_health_food_requirement WHERE member_id = ?', [memberId]);
          for (final c in m.allergies) {
            db.run("INSERT INTO member_allergy(id, household_id, member_id, allergen_code, severity) VALUES (?, ?, ?, ?, 'UNKNOWN')", [newId(), hh, memberId, c]);
          }
          for (final c in m.diets) {
            db.run("INSERT INTO member_dietary_requirement(id, household_id, member_id, dietary_pattern_code, strictness) VALUES (?, ?, ?, ?, 'HARD')", [newId(), hh, memberId, c]);
          }
          for (final c in m.health) {
            db.run("INSERT INTO member_health_food_requirement(id, household_id, member_id, requirement_type_code, strictness) VALUES (?, ?, ?, ?, 'SOFT')", [newId(), hh, memberId, c]);
          }
        }
        db.run("DELETE FROM member_preference WHERE member_id = ? AND subject_type = 'CUISINE'", [memberId]);
        for (final c in m.cuisines) {
          db.run("INSERT INTO member_preference(id, household_id, member_id, preference_kind, subject_type, cuisine_code) VALUES (?, ?, ?, 'LIKE', 'CUISINE', ?)", [newId(), hh, memberId, c]);
        }
      }

      for (final f in d.food.where((f) => f.custom != null)) {
        once('item:${f.itemId}', 'item_master', () {
          final c = f.custom!;
          final zone = (c['zone'] as String?) ?? 'ANY';
          db.run("INSERT INTO item_master(id, household_id, item_kind, canonical_name, food_category_code, default_unit_code, storage_zone, is_perishable, is_verified, created_source_code) "
              "VALUES (?, ?, 'FOOD', ?, ?, ?, ?, ?, 0, 'MANUAL')",
              [f.itemId, hh, f.name, (c['category'] as String?) ?? 'OTHER', c['unit'] ?? f.unit, zone, zone == 'CHILLED' || zone == 'FROZEN' ? 1 : 0]);
          for (final a in List<String>.from((c['allergens'] as List?) ?? const [])) {
            db.run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, ?, 'CONTAINS')", [f.itemId, a]);
          }
          return f.itemId;
        });
      }
      for (final f in d.food) {
        final storageId = storageIds[f.storageKey];
        if (storageId == null || f.quantity <= 0) continue;
        once('food:${f.key}', 'inventory_item', () {
          final item = catalog.items.where((i) => i.id == f.itemId).firstOrNull;
          final storage = db.first('SELECT kitchen_id, temperature_zone FROM storage_instance WHERE id = ?', [storageId])!;
          final today = todayIso();
          final life = item?.shelfLife[storage['temperature_zone']];
          final candidates = [if (f.expiresOn != null && f.expiresOn!.isNotEmpty) f.expiresOn!, if (life != null) addDaysIso(today, life)]..sort();
          final id = newId();
          db.run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, quantity, unit_code, purchased_on, expires_on, use_soon_on, label, created_source_code) "
              "VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 'MANUAL')",
              [id, hh, f.itemId, storage['kitchen_id'], storageId, f.unit, today, (f.expiresOn ?? '').isEmpty ? null : f.expiresOn, candidates.isEmpty ? null : candidates.first, f.name]);
          db.run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, actor_user_id, created_source_code, idempotency_key) "
              "VALUES (?, ?, ?, 'MANUAL_ADD', ?, ?, 0, ?, ?, 'MANUAL', ?)",
              [newId(), hh, id, f.quantity, f.unit, f.quantity, user['id'], 'onboarding:${f.key}']);
          r.items++;
          return id;
        });
      }

      for (final m in deriveTree(d, catalog).modules.where((m) => m.on && m.code != 'STORAGE')) {
        moduleInstance(m.code, null, m.name);
      }
      db.run("UPDATE questionnaire_session SET status = 'COMPLETED', completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [sessionId]);
      db.run("UPDATE household SET onboarding_status = 'COMPLETED', row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [hh]);
      final name = d.about['displayName'];
      if (name != null && name.trim().isNotEmpty) {
        db.run("UPDATE user_account SET display_name = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [name.trim(), user['id']]);
      }
    });
    return r;
  }
}
