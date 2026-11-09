import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'entry_ref.dart';

/// Entry Module v2 draft. The JSON shape is IDENTICAL to the website's draft (frontend/www/js/inquiry/draft.js), so both
/// apps save the same HOUSEHOLD_PROFILE v2 answers. Scoped to onboarding; disposed when it closes.
typedef J = Map<String, dynamic>;
const steps = ['about', 'health', 'kitchens', 'appliances', 'kitchenware', 'food', 'review'];
const v1StepMap = {'about': 'about', 'household': 'about', 'kitchens': 'kitchens', 'family': 'health', 'food': 'food', 'review': 'review'};
final _uuid = const Uuid();
String uid() => _uuid.v4();

class DraftV2 extends ChangeNotifier {
  DraftV2(this.data);
  final J data;
  void changed() => notifyListeners();

  J get about => data['about'] as J;
  J get household => data['household'] as J;
  J get health => data['health'] as J;
  List<J> get people => (health['people'] as List).cast<J>();
  List<J> get kitchens => (data['kitchens'] as List).cast<J>();
  List<J> get appliances => (data['appliances'] as List).cast<J>();
  List<J> get kitchenware => (data['kitchenware'] as List).cast<J>();
  List<J> get food => (data['food'] as List).cast<J>();
  String get selfKey => data['selfKey'] as String? ?? 'me';
  String encode() => jsonEncode(data);

  static DraftV2 decode(String s) => DraftV2(normalize(jsonDecode(s) as J));
  /// Deep-copies JSON into growable, mutable maps/lists.
  static J normalize(J j) => jsonDecode(jsonEncode(j)) as J;

  static DraftV2 fresh(EntryRef ref, String displayName) {
    final main = newKitchen(ref, 'MAIN', const []);
    (main['storage'] as List).addAll([newStorage(ref, main, 'REFRIGERATOR'), newStorage(ref, main, 'PANTRY')]);
    return DraftV2(normalize({'version': 2, 'about': {'displayName': displayName, 'measures': 'IMPERIAL', 'cookingRole': 'ME', 'skill': 'COMFORTABLE'}, 'selfKey': 'me',
      'household': {'size': 2, 'eaters': 2}, 'health': {'needed': null, 'consent': null, 'people': []}, 'kitchens': [main], 'appliances': [], 'kitchenware': [], 'food': []}));
  }
}

int _n(String key) => int.tryParse(key.split('-').last) ?? 0;
J newKitchen(EntryRef ref, String kind, List<J> kitchens) {
  final n = [0, ...kitchens.where((k) => (k['key'] as String).startsWith('$kind-')).map((k) => _n(k['key'] as String))].reduce((a, b) => a > b ? a : b) + 1;
  final same = kitchens.where((k) => k['kind'] == kind).length;
  final name = ref.nameOf(ref.kitchenKinds, kind);
  return {'key': '$kind-$n', 'kind': kind, 'name': same > 0 ? '$name ${same + 1}' : name, 'storage': <J>[]};
}
J newStorage(EntryRef ref, J kitchen, String type) {
  final list = (kitchen['storage'] as List).cast<J>();
  final n = [0, ...list.where((s) => s['type'] == type).map((s) => _n(s['key'] as String))].reduce((a, b) => a > b ? a : b) + 1;
  final same = list.where((s) => s['type'] == type).length;
  final name = ref.nameOf(ref.storageTypes, type);
  return {'key': '${kitchen['key']}/$type-$n', 'type': type, 'name': same > 0 ? '$name ${same + 1}' : name,
    'counts': {for (final q in ref.questionsFor(type)) q['code'] as String: q['default_value']}, 'custom': <J>[]};
}

class Place {
  const Place(this.key, this.name, this.kind, [this.parentKey]);
  final String key, name, kind;
  final String? parentKey;
}

/// Places inside a storage unit with stable keys (identical to the website: "<storageKey>#SHELVES-1", "<storageKey>#c:<node>").
({List<Place> sections, List<Place> containers}) sectionOptions(EntryRef ref, J s) {
  final sections = <Place>[], containers = <Place>[];
  final counts = (s['counts'] as Map?) ?? const {};
  for (final q in ref.questionsFor(s['type'] as String)) {
    final v = (counts[q['code']] as num?)?.toInt() ?? 0;
    if (q['input_kind'] == 'TOGGLE') {
      if (v > 0) sections.add(Place('${s['key']}#${q['code']}', q['name_pattern'] as String, q['section_kind'] as String));
    } else {
      for (var n = 1; n <= v; n++) { sections.add(Place('${s['key']}#${q['code']}-$n', (q['name_pattern'] as String).replaceAll('{n}', '$n'), q['section_kind'] as String)); }
    }
  }
  void walk(List? nodes, String prefix, String? parent) {
    for (final c in (nodes ?? const []).cast<J>()) {
      final key = '${s['key']}#c:${c['key']}';
      (c['kind'] == 'CONTAINER' ? containers : sections).add(Place(key, '$prefix${c['name']}', c['kind'] as String, parent));
      walk(c['children'] as List?, '$prefix${c['name']} › ', key);
    }
  }
  walk(s['custom'] as List?, '', null);
  return (sections: sections, containers: containers);
}

List<String> sectionNames(EntryRef ref, J s) {
  final counts = (s['counts'] as Map?) ?? const {};
  if (s['legacy'] == true && !counts.values.any((v) => (v as num? ?? 0) > 0) && ((s['custom'] as List?) ?? const []).isEmpty) {
    return [for (final t in ref.templates.where((t) => t['storage_type_code'] == s['type'])) t['default_name'] as String];
  }
  final o = sectionOptions(ref, s);
  return [...o.sections.map((p) => p.name), ...o.containers.map((p) => p.name)];
}

List<J> allStorage(DraftV2 d) => [for (final k in d.kitchens) for (final s in (k['storage'] as List).cast<J>()) {...s, 'kitchenKey': k['key'], 'kitchenName': k['name']}];

class TreeV2 {
  const TreeV2(this.storageCount, this.appliances, this.kitchenware, this.healthProfiles, this.members, this.foodCount, this.modules);
  final int storageCount, appliances, kitchenware, healthProfiles, members, foodCount;
  final List<(String code, String name, bool on)> modules;
  int get moduleCount => modules.where((m) => m.$3).length;
}

/// The household-specific module tree (health shown as a COUNT only, never details) - same rules as the website.
TreeV2 deriveTreeV2(DraftV2 d) {
  final storage = d.kitchens.fold<int>(0, (n, k) => n + (k['storage'] as List).length);
  final hp = d.health['needed'] == 'YES' ? d.people.length : 0;
  bool hasNeeds(J p) => [for (final k in ['allergies', 'intolerances', 'diets', 'health', 'avoid', 'prioritize']) ((p[k] as List?) ?? const []).length].any((n) => n > 0);
  final health = d.health['consent'] == true && d.people.any(hasNeeds);
  final cook = d.appliances.isNotEmpty;
  return TreeV2(storage, d.appliances.length, d.kitchenware.length, hp, 1 + d.people.where((p) => p['isMe'] != true).length, d.food.length, [
    ('HOUSEHOLD', 'Household', true), ('FAMILY', 'Family', true), ('HEALTH', 'Health & diet', health), ('KITCHEN', 'Kitchens', d.kitchens.isNotEmpty),
    ('STORAGE', 'Storage ($storage)', storage > 0), ('EQUIPMENT', 'Appliances & kitchenware', d.appliances.length + d.kitchenware.length > 0),
    ('INVENTORY', 'Inventory', storage > 0), ('SHOPPING', 'Shopping list', storage > 0), ('MATCHING', 'Meal matching', storage > 0 && cook), ('MEALS', 'Meal history', storage > 0 && cook),
  ]);
}

/// HOUSEHOLD_PROFILE v2 answers (same codes and values as the website).
List<(String code, Object? value)> answersOf(DraftV2 d) => [
      ('ABOUT_YOU', {'about': d.about, 'selfKey': d.selfKey}), ('HOUSEHOLD', d.household), ('HEALTH_NEEDED', d.health['needed']),
      ('HEALTH_CONSENT', d.health['consent']), ('HEALTH_PROFILES', d.people), ('KITCHENS', d.kitchens), ('APPLIANCES', d.appliances),
      ('KITCHENWARE', d.kitchenware), ('FOOD_ON_HAND', d.food),
    ];

@visibleForTesting
J debugJson(DraftV2 d) => d.data;
