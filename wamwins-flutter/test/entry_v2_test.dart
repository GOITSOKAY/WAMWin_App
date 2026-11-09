// Entry Module v2 logic shared with the website: draft keys, nested section keys, the v1 -> v2 adapter, resume mapping,
// the household tree (health as a count only) and module validation. Run: flutter test test/entry_v2_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wamwins/inquiry/adapter.dart';
import 'package:wamwins/inquiry/draft_v2.dart';
import 'package:wamwins/inquiry/entry_ref.dart';
import 'package:wamwins/screens/setup/modules_v2.dart';

final ref = EntryRef.fromLists(
  kitchenKinds: [{'code': 'MAIN', 'name': 'Main Kitchen', 'legacy_kitchen_type': 'MAIN'}, {'code': 'BARN', 'name': 'Barn Kitchen', 'legacy_kitchen_type': 'OTHER'},
    {'code': 'MOBILE', 'name': 'Mobile Kitchen', 'legacy_kitchen_type': 'OTHER'}],
  storageTypes: [{'code': 'REFRIGERATOR', 'name': 'Refrigerator', 'temperature_zone': 'CHILLED'}, {'code': 'PANTRY', 'name': 'Pantry', 'temperature_zone': 'AMBIENT'}],
  questions: [
    {'storage_type_code': 'REFRIGERATOR', 'code': 'SHELVES', 'label': 'How many shelves?', 'section_kind': 'SHELF', 'name_pattern': 'Shelf {n}', 'input_kind': 'COUNT', 'default_value': 3, 'max_value': 12},
    {'storage_type_code': 'REFRIGERATOR', 'code': 'FREEZER_SECTION', 'label': 'Freezer section', 'section_kind': 'ZONE', 'name_pattern': 'Freezer section', 'input_kind': 'TOGGLE', 'default_value': 0, 'max_value': 1},
    {'storage_type_code': 'PANTRY', 'code': 'SHELVES', 'label': 'How many shelves?', 'section_kind': 'SHELF', 'name_pattern': 'Shelf {n}', 'input_kind': 'COUNT', 'default_value': 4, 'max_value': 12},
  ],
  templates: [{'id': 't1', 'storage_type_code': 'PANTRY', 'section_kind': 'SHELF', 'default_name': 'Top shelf', 'ordinal': 0}],
  appliances: [{'code': 'STOVETOP', 'name': 'Cooktop', 'power_source': 'ELECTRIC', 'size_rank': 5}],
  kitchenware: [{'code': 'WOK', 'category': 'COOKWARE', 'name': 'Wok', 'equipment_type_code': 'WOK'}],
);

void main() {
  test('kitchens and storage get the same stable keys as the website', () {
    final d = DraftV2.fresh(ref, 'Ana');
    expect(d.kitchens.single['key'], 'MAIN-1');
    expect((d.kitchens.single['storage'] as List).map((s) => s['key']), ['MAIN-1/REFRIGERATOR-1', 'MAIN-1/PANTRY-1']);
    final barn = newKitchen(ref, 'BARN', d.kitchens);
    expect(barn['key'], 'BARN-1');
    expect(barn['name'], 'Barn Kitchen');
    d.kitchens.add(barn);
    expect(newKitchen(ref, 'BARN', d.kitchens)['name'], 'Barn Kitchen 2');
    expect(d.about['measures'], 'IMPERIAL', reason: 'U.S. customary is the default');
  });

  test('follow-up and nested sections: same keys as the website, any depth, containers apart', () {
    final s = newStorage(ref, {'key': 'MAIN-1', 'storage': <J>[]}, 'PANTRY');
    (s['custom'] as List).add({'key': 'bin', 'kind': 'BIN', 'name': 'Snack bin', 'children': [
      {'key': 'side', 'kind': 'COMPARTMENT', 'name': 'Left side', 'children': [{'key': 'jar', 'kind': 'CONTAINER', 'name': 'Container A', 'children': <J>[]}]}]});
    final o = sectionOptions(ref, s);
    expect(o.sections.map((x) => x.key), ['MAIN-1/PANTRY-1#SHELVES-1', 'MAIN-1/PANTRY-1#SHELVES-2', 'MAIN-1/PANTRY-1#SHELVES-3', 'MAIN-1/PANTRY-1#SHELVES-4',
      'MAIN-1/PANTRY-1#c:bin', 'MAIN-1/PANTRY-1#c:side']);
    expect(o.sections.last.parentKey, 'MAIN-1/PANTRY-1#c:bin');
    expect(o.containers.single.name, 'Snack bin › Left side › Container A');
    expect(o.containers.single.parentKey, 'MAIN-1/PANTRY-1#c:side');
  });

  test('v1 draft -> v2: record keys kept, v1 steps resume in v2 modules', () {
    final d = adaptV1(ref, {
      'about': {'displayName': 'Ana'}, 'householdName': 'Santos', 'householdSize': 3, 'kitchens': {'MAIN': 1, 'OTHER': 1},
      'storage': {'MAIN-1': {'PANTRY': 1}}, 'appliances': {'MAIN-1': ['STOVETOP']}, 'cookware': {'MAIN-1': ['WOK']}, 'utensils': {},
      'family': [{'key': 'k1', 'name': 'Ana', 'relationship': 'SELF', 'ageBand': 'ADULT', 'isMe': true, 'allergies': [], 'diets': [], 'health': []},
        {'key': 'k2', 'name': 'Ben', 'relationship': 'CHILD', 'ageBand': 'CHILD', 'allergies': ['PEANUT'], 'diets': [], 'health': []}],
      'healthConsent': true, 'food': [{'key': 'f1', 'itemId': 'x', 'name': 'White rice', 'storageKey': 'MAIN-1/PANTRY-1', 'quantity': 1, 'unit': 'G'}],
    });
    expect(d.kitchens.map((k) => k['key']), ['MAIN-1', 'OTHER-1']);
    expect(d.kitchens.last['kind'], isNull, reason: '"Other kitchen" is not a v2 kind; the v1 kitchen keeps its name');
    expect(((d.kitchens.first['storage'] as List).single as Map)['legacy'], isTrue);
    expect(d.appliances.single['pkey'], 'equipment:MAIN-1:STOVETOP');
    expect(d.kitchenware.single['pkey'], 'equipment:MAIN-1:WOK');
    expect(d.selfKey, 'k1');
    expect(d.health['needed'], 'YES');
    expect(d.people.map((p) => p['key']), ['k2']);
    expect(d.about['measures'], 'IMPERIAL');
    expect(v1StepMap['household'], 'about');
    expect(v1StepMap['family'], 'health');
  });

  test('household tree shows health as a count only, and modules follow the answers', () {
    final d = DraftV2.fresh(ref, 'Ana');
    d.health['needed'] = 'YES'; d.health['consent'] = true;
    d.people.add({'key': 'b', 'name': 'Ben', 'isMe': false, 'allergies': ['PEANUT']});
    final t = deriveTreeV2(d);
    expect(t.healthProfiles, 1);
    expect(t.modules.firstWhere((m) => m.$1 == 'HEALTH').$3, isTrue);
    expect(t.modules.firstWhere((m) => m.$1 == 'MATCHING').$3, isFalse, reason: 'no appliance yet');
    d.appliances.add({'key': 'a', 'kitchenKey': 'MAIN-1', 'code': 'STOVETOP', 'name': 'Cooktop'});
    expect(deriveTreeV2(d).modules.firstWhere((m) => m.$1 == 'MATCHING').$3, isTrue);
  });

  test('module validation (same rules and messages as the website)', () {
    final d = DraftV2.fresh(ref, '');
    expect(validateAbout(d), 'Enter your name to continue.');
    d.about['displayName'] = 'Ana'; d.household['name'] = 'Santos';
    expect(validateAbout(d), isNull);
    expect(validateHealth(d), 'Choose Yes or No to continue.');
    d.health['needed'] = 'YES'; d.health['consent'] = true;
    expect(validateHealth(d), 'Add at least one person, or choose No.');
    d.health['consent'] = false;
    expect(validateHealth(d), isNull, reason: 'can continue without storing health data');
    d.kitchens.clear();
    expect(validateKitchens(d), 'Add at least one kitchen.');
    d.food.add({'quantity': 0});
    expect(validateFood(d), 'Each food needs a quantity greater than zero.');
  });
}
