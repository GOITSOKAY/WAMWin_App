// Conformance rule C3 (docs/CLIENT_CONFORMANCE.md): this client must reproduce the reference matching
// decisions for the shared scenario household - same exclusions with the same reasons, same recommended set.
// Uses the real shared database (bundled migrations) in memory. Run: flutter test test/matching_conformance_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamwins/core/db.dart';
import 'package:wamwins/core/ids.dart';
import 'package:wamwins/matching/matching_service.dart';
import 'package:wamwins/matching/meal_service.dart';

/// Builds the fixture household with the same SQL the app's provisioning uses.
({String hh, String user, List<String> members}) buildFixture(AppDb db, Map<String, dynamic> fx) {
  final user = newId(), hh = newId(), today = fx['today'] as String;
  final memberIds = <String>[];
  db.transaction(() {
    db.run("INSERT INTO user_account(id, email, display_name) VALUES (?, 'fixture@example.com', 'Fixture')", [user]);
    db.run("INSERT INTO household(id, name, owner_user_id, onboarding_status) VALUES (?, 'Fixture household', ?, 'COMPLETED')", [hh, user]);
    db.run("INSERT INTO household_membership(id, household_id, user_id, role_code, status) VALUES (?, ?, ?, 'OWNER', 'ACTIVE')", [newId(), hh, user]);
    final kitchen = newId();
    db.run("INSERT INTO kitchen(id, household_id, name, kitchen_type, sort_order, created_source_code) VALUES (?, ?, ?, ?, 0, 'MANUAL')", [kitchen, hh, fx['kitchen']['name'], fx['kitchen']['type']]);
    final storage = <String, (String id, String zone)>{};
    for (final s in (fx['storage'] as List).cast<Map<String, dynamic>>()) {
      final id = newId();
      db.run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 0, 'MANUAL')",
          [id, hh, kitchen, s['type'], s['name'], s['zone']]);
      storage[s['key'] as String] = (id, s['zone'] as String);
    }
    for (final e in (fx['equipment'] as List).cast<List>()) {
      db.run("INSERT INTO ${e[0]}(id, household_id, kitchen_id, equipment_type_code, name, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')", [newId(), hh, kitchen, e[1], e[1]]);
    }
    for (final i in (fx['inventory'] as List).cast<Map<String, dynamic>>()) {
      final item = db.first('SELECT id, default_unit_code, shelf_life_ambient_days, shelf_life_chilled_days, shelf_life_frozen_days FROM item_master WHERE canonical_name = ? AND household_id IS NULL', [i['item']])!;
      final (sid, zone) = storage[i['storage']]!;
      final life = item[zone == 'CHILLED' ? 'shelf_life_chilled_days' : zone == 'FROZEN' ? 'shelf_life_frozen_days' : 'shelf_life_ambient_days'] as int?;
      final dates = [if (i['expiresOn'] != null) i['expiresOn'] as String, if (life != null) addDaysIso(today, life)]..sort();
      final id = newId();
      final qty = (i['qty'] as num).toDouble();
      db.run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, quantity, unit_code, purchased_on, expires_on, use_soon_on, created_source_code) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, 'MANUAL')",
          [id, hh, item['id'], kitchen, sid, item['default_unit_code'], today, i['expiresOn'], dates.isEmpty ? null : dates.first]);
      db.run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, created_source_code) VALUES (?, ?, ?, 'MANUAL_ADD', ?, ?, 0, ?, 'MANUAL')",
          [newId(), hh, id, qty, item['default_unit_code'], qty]);
    }
    for (final m in (fx['members'] as List).cast<Map<String, dynamic>>()) {
      final id = newId();
      memberIds.add(id);
      db.run("INSERT INTO family_member(id, household_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')", [id, hh, m['name'], m['relationship'], m['ageBand']]);
      for (final a in m['allergies'] as List) { db.run("INSERT INTO member_allergy(id, household_id, member_id, allergen_code, severity) VALUES (?, ?, ?, ?, 'SEVERE')", [newId(), hh, id, a]); }
      for (final d in m['diets'] as List) { db.run("INSERT INTO member_dietary_requirement(id, household_id, member_id, dietary_pattern_code, strictness) VALUES (?, ?, ?, ?, 'HARD')", [newId(), hh, id, d]); }
      for (final h in m['health'] as List) { db.run("INSERT INTO member_health_food_requirement(id, household_id, member_id, requirement_type_code, strictness) VALUES (?, ?, ?, ?, 'SOFT')", [newId(), hh, id, h]); }
    }
  });
  return (hh: hh, user: user, members: memberIds);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fx = jsonDecode(File('test/fixtures/matching_household.json').readAsStringSync()) as Map<String, dynamic>;
  final scenario = jsonDecode(File('test/vectors/matching-scenario.json').readAsStringSync()) as Map<String, dynamic>;

  test('same exclusions (with reasons) and same recommendations as the reference', () async {
    final db = await AppDb.open(path: ':memory:');
    final f = buildFixture(db, fx);
    final run = MatchingService(db).run(householdId: f.hh, userId: f.user, memberIds: f.members, maxResults: 10, today: fx['today'] as String);
    final excluded = {for (final e in run.excluded) run.recipeTitles[e.recipeId]!: e.reason};
    expect(excluded, Map<String, String>.from(scenario['must_exclude'] as Map));
    expect(run.results.map((r) => r.ranked.title).toList()..sort(), List<String>.from(scenario['must_recommend'] as List));
    for (final r in run.results) {
      expect(r.ranked.factors.first.code, 'SAFETY');
    }
    db.close();
  });

  test('cooking deducts inventory through the ledger, once', () async {
    final db = await AppDb.open(path: ':memory:');
    final f = buildFixture(db, fx);
    final run = MatchingService(db).run(householdId: f.hh, userId: f.user, memberIds: f.members, today: fx['today'] as String);
    final top = run.results.first;
    final before = db.count('SELECT COUNT(*) FROM inventory_transaction WHERE household_id = ?', [f.hh]);
    final c = MealService(db).confirm(householdId: f.hh, userId: f.user, matchResultId: top.matchResultId, today: fx['today'] as String);
    final usages = db.count("SELECT COUNT(*) FROM inventory_transaction WHERE transaction_type_code = 'MEAL_USAGE' AND meal_record_id = ?", [c.mealRecordId]);
    expect(usages, greaterThan(0));
    expect(c.shortfalls, isEmpty);
    expect(db.count('SELECT COUNT(*) FROM consumption_record WHERE meal_record_id = ?', [c.mealRecordId]), usages);
    final again = MealService(db).confirm(householdId: f.hh, userId: f.user, matchResultId: top.matchResultId, today: fx['today'] as String);
    expect(again.alreadyConfirmed, isTrue);
    expect(db.count('SELECT COUNT(*) FROM inventory_transaction WHERE household_id = ?', [f.hh]), before + usages);
    db.close();
  });
}
