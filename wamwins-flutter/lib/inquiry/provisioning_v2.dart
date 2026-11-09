import '../core/db.dart';
import '../core/ids.dart';
import 'catalog.dart';
import 'draft_v2.dart';
import 'entry_ref.dart';

/// "Save Entries" (Entry Module v2) - port of frontend/www/js/inquiry/provisioning.js. Answers become records, ONLY what
/// the answers describe, in one transaction. Every record is traced in profile_provisioning_record by the same stable draft
/// keys v1 used, so saving again adds only what is new. Quantities go through the ledger (item at 0 + MANUAL_ADD; the shared
/// triggers apply it). Health rows are written only with consent.
class SaveResult {
  int kitchens = 0, storage = 0, sections = 0, appliances = 0, kitchenware = 0, members = 0, items = 0, photos = 0;
  bool existing = false;
}

const _cooking = {'ME': 'PRIMARY', 'SHARED': 'SHARED', 'OTHER': 'OTHER'};

class ProvisionerV2 {
  ProvisionerV2(this.db, this.ref, this.catalog);
  final AppDb db;
  final EntryRef ref;
  final Catalog catalog;

  SaveResult save({required DbRow user, required String householdId, required String sessionId, required DraftV2 d}) {
    final r = SaveResult();
    final hh = householdId;
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    r.existing = db.count('SELECT COUNT(*) FROM profile_provisioning_record WHERE household_id = ?', [hh]) > 0;
    String once(String key, String table, String Function() create) {
      final e = db.first('SELECT created_entity_id FROM profile_provisioning_record WHERE household_id = ? AND draft_key = ?', [hh, key]);
      if (e != null) return e['created_entity_id'] as String;
      final id = create();
      db.run('INSERT INTO profile_provisioning_record(id, household_id, session_id, draft_key, created_entity_table, created_entity_id) VALUES (?, ?, ?, ?, ?, ?)',
          [newId(), hh, sessionId, key, table, id]);
      return id;
    }
    String moduleId(String code) => db.first('SELECT id FROM module_definition WHERE module_code = ?', [code])!['id'] as String;
    void module(String code, String? resourceId, String name) => once('module:$code:${resourceId ?? ''}', 'household_module_instance', () {
          final id = newId();
          db.run("INSERT INTO household_module_instance(id, household_id, module_id, resource_type, resource_id, display_name, current_status) VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE')",
              [id, hh, moduleId(code), resourceId == null ? null : 'storage_instance', resourceId, name]);
          return id;
        });
    final ids = <String, Map<String, String?>>{};

    db.transaction(() {
      // ---- Module 1: you
      final selfId = once('member:${d.selfKey}', 'family_member', () {
        final id = newId(); r.members++;
        db.run("INSERT INTO family_member(id, household_id, linked_user_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, ?, ?, 'SELF', 'ADULT', 'MANUAL')",
            [id, hh, user['id'], d.about['displayName']]);
        return id;
      });
      db.run("UPDATE family_member SET display_name = ?, household_role_code = ?, cooking_responsibility = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?",
          [d.about['displayName'], d.about['cookingRole'] == 'ME' ? d.about['householdRole'] : null, _cooking[d.about['cookingRole']], selfId]);

      // ---- Module 3: kitchens -> storage -> sections (follow-ups + nested own sections) / containers
      for (var ki = 0; ki < d.kitchens.length; ki++) {
        final k = d.kitchens[ki];
        final legacy = ref.kitchenKinds.where((x) => x['code'] == k['kind']).map((x) => x['legacy_kitchen_type'] as String).firstOrNull ?? (k['legacyType'] as String?) ?? 'OTHER';
        final kitchenId = once('kitchen:${k['key']}', 'kitchen', () {
          final id = newId(); r.kitchens++;
          db.run("INSERT INTO kitchen(id, household_id, name, kitchen_type, kitchen_kind_code, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 'MANUAL')",
              [id, hh, k['name'], legacy, k['kind'], ki]);
          return id;
        });
        db.run("UPDATE kitchen SET name = ?, kitchen_kind_code = ? WHERE id = ? AND (name <> ? OR kitchen_kind_code IS NOT ?)", [k['name'], k['kind'], kitchenId, k['name'], k['kind']]);
        ids['kitchen:${k['key']}'] = {'kitchen': kitchenId};
        final storage = (k['storage'] as List).cast<J>();
        for (var si = 0; si < storage.length; si++) {
          final st = storage[si];
          final sid = once('storage:${st['key']}', 'storage_instance', () {
            final id = newId(); r.storage++;
            db.run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
                [id, hh, kitchenId, st['type'], st['name'], ref.zoneOf(st['type'] as String), si]);
            final counts = (st['counts'] as Map?) ?? const {};
            if (st['legacy'] == true && !counts.values.any((v) => (v as num? ?? 0) > 0)) {         // v1 storage never saved before: v1 template sections
              final tpl = ref.templates.where((t) => t['storage_type_code'] == st['type']).toList();
              for (var oi = 0; oi < tpl.length; oi++) {
                r.sections++;
                db.run("INSERT INTO storage_section(id, household_id, storage_instance_id, section_kind, name, ordinal, template_id, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'SYSTEM_DEFAULT')",
                    [newId(), hh, id, tpl[oi]['section_kind'], tpl[oi]['default_name'], oi, tpl[oi]['id']]);
              }
            }
            return id;
          });
          db.run('UPDATE storage_instance SET name = ? WHERE id = ? AND name <> ?', [st['name'], sid, st['name']]);
          ids['storage:${st['key']}'] = {'kitchen': kitchenId, 'storage': sid};
          module('STORAGE', sid, st['name'] as String);
          final o = sectionOptions(ref, st);
          for (var oi = 0; oi < o.sections.length; oi++) {
            final sec = o.sections[oi];
            final parent = sec.parentKey == null ? null : ids['section:${sec.parentKey}']?['section'];
            final secId = once('section:${sec.key}', 'storage_section', () {
              final id = newId(); r.sections++;
              db.run("INSERT INTO storage_section(id, household_id, storage_instance_id, parent_section_id, section_kind, name, ordinal, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
                  [id, hh, sid, parent, sec.kind, sec.name.split(' › ').last, oi]);
              return id;
            });
            ids['section:${sec.key}'] = {'kitchen': kitchenId, 'storage': sid, 'section': secId};
          }
          for (final c in o.containers) {
            final parent = c.parentKey == null ? null : ids['section:${c.parentKey}']?['section'];
            final cid = once('container:${c.key}', 'household_container', () {
              final id = newId();
              db.run("INSERT INTO household_container(id, household_id, kitchen_id, storage_instance_id, storage_section_id, equipment_type_code, name, created_source_code) "
                  "VALUES (?, ?, ?, ?, ?, 'AIRTIGHT_CONTAINER', ?, 'MANUAL')", [id, hh, kitchenId, sid, parent, c.name.split(' › ').last]);
              return id;
            });
            ids['container:${c.key}'] = {'kitchen': kitchenId, 'storage': sid, 'section': parent, 'container': cid};
          }
        }
      }
      // reference photos taken during onboarding -> real ids (they keep their draft key for traceability)
      for (final m in db.select('SELECT id, location_draft_key FROM location_media WHERE household_id = ? AND location_draft_key IS NOT NULL AND kitchen_id IS NULL', [hh])) {
        final at = ids[m['location_draft_key']];
        if (at == null) continue;
        r.photos++;
        db.run("UPDATE location_media SET kitchen_id = ?, storage_instance_id = ?, storage_section_id = ?, container_id = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?",
            [at['kitchen'], at['storage'], at['section'], at['container'], m['id']]);
      }

      // ---- Module 4: appliances (details; refrigerator/freezer cross-reference their storage unit)
      for (final a in d.appliances) {
        final kitchenId = ids['kitchen:${a['kitchenKey']}']?['kitchen'];
        if (kitchenId == null) continue;
        final linked = ids['storage:${a['storageKey']}']?['storage'] ?? ids['storage:${a['location']}']?['storage'];
        final vals = [a['name'], s(a['brand']), s(a['model']), s(a['serial']), s(a['purchasedOn']), s(a['warrantyEnd']),
          ids['storage:${a['location']}'] == null ? s(a['location']) : null, a['condition'] ?? 'WORKING', s(a['notes']), linked];
        final aid = once((a['pkey'] as String?) ?? 'appliance:${a['kitchenKey']}:${a['key']}', 'household_appliance', () {
          final id = newId(); r.appliances++;
          db.run("INSERT INTO household_appliance(id, household_id, kitchen_id, equipment_type_code, name, brand, model, serial_number, purchased_on, warranty_end_on, location_note, condition, notes, storage_instance_id, created_source_code) "
              "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')", [id, hh, kitchenId, a['code'] ?? 'CUSTOM_APPLIANCE', ...vals]);
          return id;
        });
        db.run("UPDATE household_appliance SET name = ?, brand = ?, model = ?, serial_number = ?, purchased_on = ?, warranty_end_on = ?, location_note = ?, condition = ?, notes = ?, storage_instance_id = ?, "
            "row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [...vals, aid]);
      }
      // ---- Module 5: kitchenware with quantities (v1 cookware/utensil records are found by their v1 keys: no duplicates)
      for (final w in d.kitchenware) {
        final kitchenId = ids['kitchen:${w['kitchenKey']}']?['kitchen'];
        if (kitchenId == null) continue;
        final wid = once((w['pkey'] as String?) ?? 'kitchenware:${w['kitchenKey']}:${w['code'] ?? w['key']}', 'household_kitchenware', () {
          final id = newId(); r.kitchenware++;
          db.run("INSERT INTO household_kitchenware(id, household_id, kitchen_id, kitchenware_type_code, category, name, quantity, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
              [id, hh, kitchenId, w['code'], w['category'], w['name'], w['quantity']]);
          return id;
        });
        if (w['pkey'] == null) {
          db.run("UPDATE household_kitchenware SET quantity = ?, name = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND (quantity <> ? OR name <> ?)",
              [w['quantity'], w['name'], wid, w['quantity'], w['name']]);
        }
      }

      // ---- Module 2: health profiles, only with consent
      if (d.health['needed'] == 'YES' && d.health['consent'] == true) {
        for (final p in d.people) {
          final memberId = p['isMe'] == true ? selfId : once('member:${p['key']}', 'family_member', () {
            final existing = p['existingId'] as String?;
            if (existing != null && db.first('SELECT 1 AS x FROM family_member WHERE id = ? AND household_id = ?', [existing, hh]) != null) return existing;
            final id = newId(); r.members++;
            db.run("INSERT INTO family_member(id, household_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')",
                [id, hh, p['name'], p['relationship'], p['ageBand']]);
            return id;
          });
          if (p['isMe'] != true) {
            db.run("UPDATE family_member SET display_name = ?, relationship = ?, age_band = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?",
                [p['name'], p['relationship'], p['ageBand'], memberId]);
          }
          List<String> codes(String k) => ((p[k] as List?) ?? const []).cast<String>();
          for (final t in ['member_allergy', 'member_intolerance', 'member_dietary_requirement', 'member_health_food_requirement', 'member_food_rule']) {
            db.run('DELETE FROM $t WHERE member_id = ?', [memberId]);
          }
          for (final c in codes('allergies')) { db.run("INSERT INTO member_allergy(id, household_id, member_id, allergen_code, severity) VALUES (?, ?, ?, ?, 'UNKNOWN')", [newId(), hh, memberId, c]); }
          for (final c in codes('intolerances')) { db.run("INSERT INTO member_intolerance(id, household_id, member_id, allergen_code, severity, handling) VALUES (?, ?, ?, ?, 'MODERATE', 'EXCLUDE')", [newId(), hh, memberId, c]); }
          for (final c in codes('diets')) { db.run("INSERT INTO member_dietary_requirement(id, household_id, member_id, dietary_pattern_code, strictness) VALUES (?, ?, ?, ?, 'HARD')", [newId(), hh, memberId, c]); }
          for (final c in codes('health')) { db.run("INSERT INTO member_health_food_requirement(id, household_id, member_id, requirement_type_code, strictness) VALUES (?, ?, ?, ?, 'SOFT')", [newId(), hh, memberId, c]); }
          void rule(String kind, String ctx, J t) => db.run("INSERT INTO member_food_rule(id, household_id, member_id, rule_kind, meal_context, label, item_master_id, food_category_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              [newId(), hh, memberId, kind, ctx, t['label'], t['itemId'], t['categoryCode']]);
          for (final t in ((p['avoid'] as List?) ?? const []).cast<J>()) { rule('AVOID', 'ANY', t); }
          for (final t in ((p['prioritize'] as List?) ?? const []).cast<J>()) { rule('PRIORITIZE', 'ANY', t); }
          for (final e in ((p['meals'] as Map?) ?? const {}).entries) {
            final m = e.value as Map;
            for (final t in ((m['avoid'] as List?) ?? const []).cast<J>()) { rule('AVOID', e.key as String, t); }
            for (final t in ((m['prioritize'] as List?) ?? const []).cast<J>()) { rule('PRIORITIZE', e.key as String, t); }
            final note = s(m['note']);
            if (note != null) rule('NOTE', e.key as String, {'label': note});
          }
        }
      }

      // ---- Module 6: the household's own foods, then food -> inventory item (at 0) + MANUAL_ADD (the triggers apply it)
      for (final f in d.food.where((f) => f['custom'] != null)) {
        once('item:${f['itemId']}', 'item_master', () {
          final c = f['custom'] as Map;
          final zone = (c['zone'] as String?) ?? 'ANY';
          db.run("INSERT INTO item_master(id, household_id, item_kind, canonical_name, food_category_code, default_unit_code, storage_zone, is_perishable, is_verified, created_source_code) "
              "VALUES (?, ?, 'FOOD', ?, ?, ?, ?, ?, 0, 'MANUAL')", [f['itemId'], hh, f['name'], c['category'] ?? 'OTHER', c['unit'] ?? f['unit'], zone, zone == 'CHILLED' || zone == 'FROZEN' ? 1 : 0]);
          for (final a in ((c['allergens'] as List?) ?? const []).cast<String>()) {
            db.run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, ?, 'CONTAINS')", [f['itemId'], a]);
          }
          return f['itemId'] as String;
        });
      }
      for (final f in d.food) {
        final at = ids['storage:${f['storageKey']}'];
        final qty = (f['quantity'] as num?)?.toDouble() ?? 0;
        if (at == null || qty <= 0) continue;
        once('food:${f['key']}', 'inventory_item', () {
          r.items++;
          final item = catalog.items.where((i) => i.id == f['itemId']).firstOrNull;
          final zone = db.first('SELECT temperature_zone FROM storage_instance WHERE id = ?', [at['storage']])!['temperature_zone'] as String;
          final purchased = s(f['purchasedOn']) ?? todayIso();
          final life = item?.shelfLife[zone];
          final soon = [s(f['expiresOn']), s(f['useByOn']), s(f['bestByOn']), if (life != null) addDaysIso(purchased, life)].whereType<String>().toList()..sort();
          final id = newId();
          db.run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, storage_section_id, container_id, quantity, unit_code, purchased_on, opened_on, "
              "best_before_on, use_by_on, expires_on, use_soon_on, brand, packaging_code, package_size, package_unit_code, item_condition, notes, label, created_source_code) "
              "VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
              [id, hh, f['itemId'], at['kitchen'], at['storage'], ids['section:${f['sectionKey']}']?['section'], ids['container:${f['containerKey']}']?['container'], f['unit'], purchased,
                s(f['openedOn']), s(f['bestByOn']), s(f['useByOn']), s(f['expiresOn']), soon.isEmpty ? null : soon.first, s(f['brand']), s(f['packaging']),
                (f['packageSize'] as num?)?.toDouble(), s(f['packageUnit']), s(f['condition']), s(f['notes']), f['name']]);
          db.run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, actor_user_id, created_source_code, idempotency_key) "
              "VALUES (?, ?, ?, 'MANUAL_ADD', ?, ?, 0, ?, ?, 'MANUAL', ?)", [newId(), hh, id, qty, f['unit'], qty, user['id'], 'onboarding:${f['key']}']);
          return id;
        });
      }

      // ---- modules this household needs (only those)
      for (final m in deriveTreeV2(d).modules.where((m) => m.$3 && m.$1 != 'STORAGE')) { module(m.$1, null, m.$2); }
      db.run("UPDATE questionnaire_session SET status = 'COMPLETED', completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [sessionId]);
      db.run("UPDATE household SET onboarding_status = 'COMPLETED', row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [hh]);
      db.run("UPDATE user_account SET display_name = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [d.about['displayName'], user['id']]);
    });
    return r;
  }
}
