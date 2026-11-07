import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalog.dart';

class Member {
  Member({required this.key, required this.name, required this.relationship, required this.ageBand, this.isMe = false,
      List<String>? allergies, List<String>? diets, List<String>? health, List<String>? cuisines})
      : allergies = allergies ?? [], diets = diets ?? [], health = health ?? [], cuisines = cuisines ?? [];
  final String key;
  String name, relationship, ageBand;
  final bool isMe;
  List<String> allergies, diets, health, cuisines;
  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'relationship': relationship, 'ageBand': ageBand, 'isMe': isMe,
      'allergies': allergies, 'diets': diets, 'health': health, 'cuisines': cuisines};
  static Member fromJson(Map<String, dynamic> j) => Member(key: j['key'], name: j['name'], relationship: j['relationship'], ageBand: j['ageBand'],
      isMe: j['isMe'] == true, allergies: List<String>.from(j['allergies'] ?? []), diets: List<String>.from(j['diets'] ?? []),
      health: List<String>.from(j['health'] ?? []), cuisines: List<String>.from(j['cuisines'] ?? []));
}

class FoodEntry {
  FoodEntry({required this.key, required this.itemId, required this.name, required this.storageKey, required this.quantity, required this.unit, this.expiresOn, this.custom});
  final String key, itemId, name, storageKey;
  double quantity;
  String unit;
  String? expiresOn;
  /// Set for the household's own foods: {category, unit, zone, allergens} -> item_master + item_allergen rows.
  final Map<String, dynamic>? custom;
  Map<String, dynamic> toJson() => {'key': key, 'itemId': itemId, 'name': name, 'storageKey': storageKey, 'quantity': quantity, 'unit': unit, 'expiresOn': expiresOn, if (custom != null) 'custom': custom};
  static FoodEntry fromJson(Map<String, dynamic> j) => FoodEntry(key: j['key'], itemId: j['itemId'], name: j['name'], storageKey: j['storageKey'],
      quantity: (j['quantity'] as num).toDouble(), unit: j['unit'], expiresOn: j['expiresOn'], custom: j['custom'] == null ? null : Map<String, dynamic>.from(j['custom'] as Map));
}

/// In-memory view of the HOUSEHOLD_PROFILE answers for the profiling screens only (scoped state,
/// disposed when profiling closes). Persisted after every step.
class ProfileDraft extends ChangeNotifier {
  Map<String, String> about = {};
  String householdName = '';
  int householdSize = 2;
  Map<String, int> kitchens = {'MAIN': 1};
  Map<String, Map<String, int>> storage = {'MAIN-1': {'REFRIGERATOR': 1, 'PANTRY': 1}};
  Map<String, List<String>> appliances = {}, cookware = {}, utensils = {};
  List<Member> family = [];
  bool? healthConsent;
  List<FoodEntry> food = [];

  void changed() => notifyListeners();

  Map<String, dynamic> toJson() => {'about': about, 'householdName': householdName, 'householdSize': householdSize, 'kitchens': kitchens,
      'storage': storage, 'appliances': appliances, 'cookware': cookware, 'utensils': utensils,
      'family': family.map((m) => m.toJson()).toList(), 'healthConsent': healthConsent, 'food': food.map((f) => f.toJson()).toList()};

  static ProfileDraft fromJson(Map<String, dynamic> j) {
    Map<String, List<String>> lists(dynamic v) => {for (final e in (v as Map? ?? {}).entries) e.key as String: List<String>.from(e.value as List)};
    return ProfileDraft()
      ..about = Map<String, String>.from(j['about'] ?? {})
      ..householdName = j['householdName'] ?? ''
      ..householdSize = j['householdSize'] ?? 2
      ..kitchens = Map<String, int>.from(j['kitchens'] ?? {'MAIN': 1})
      ..storage = {for (final e in (j['storage'] as Map? ?? {}).entries) e.key as String: Map<String, int>.from(e.value as Map)}
      ..appliances = lists(j['appliances'])
      ..cookware = lists(j['cookware'])
      ..utensils = lists(j['utensils'])
      ..family = [for (final m in (j['family'] as List? ?? [])) Member.fromJson(Map<String, dynamic>.from(m as Map))]
      ..healthConsent = j['healthConsent'] as bool?
      ..food = [for (final f in (j['food'] as List? ?? [])) FoodEntry.fromJson(Map<String, dynamic>.from(f as Map))];
  }
  String encode() => jsonEncode(toJson());
}

class KitchenRef {
  const KitchenRef(this.key, this.type, this.n, this.name);
  final String key, type, name;
  final int n;
}

class StorageRef {
  const StorageRef(this.key, this.type, this.zone, this.name, this.sections, this.items);
  final String key, type, zone, name;
  final List<String> sections;
  final int items;
}

class ModuleFlag {
  const ModuleFlag(this.code, this.name, this.on);
  final String code, name;
  final bool on;
}

class HouseholdTree {
  const HouseholdTree(this.kitchens, this.storage, this.equipment, this.storageCount, this.equipmentCount, this.members, this.modules);
  final List<KitchenRef> kitchens;
  final Map<String, List<StorageRef>> storage; // kitchen key -> units
  final Map<String, int> equipment;            // kitchen key -> count
  final int storageCount, equipmentCount, members;
  final List<ModuleFlag> modules;
  int get moduleCount => modules.where((m) => m.on).length;
}

/// Kitchens the household said it has, with stable keys used across steps ("MAIN-1").
List<KitchenRef> kitchenList(ProfileDraft d) => [
      for (final t in kitchenTypes)
        for (var i = 1; i <= (d.kitchens[t.code] ?? 0); i++) KitchenRef('${t.code}-$i', t.code, i, (d.kitchens[t.code] ?? 0) > 1 ? '${t.name} $i' : t.name)
    ];

List<StorageRef> storageList(ProfileDraft d, Catalog c, String kitchenKey) {
  final counts = d.storage[kitchenKey] ?? {};
  return [
    for (final t in c.storageTypes)
      for (var i = 1; i <= (counts[t.code] ?? 0); i++)
        StorageRef('$kitchenKey/${t.code}-$i', t.code, c.storageZones[t.code] ?? 'AMBIENT', (counts[t.code] ?? 0) > 1 ? '${t.name} $i' : t.name,
            [for (final s in c.sectionTemplates[t.code] ?? const <(String, String, String)>[]) s.$2],
            d.food.where((f) => f.storageKey == '$kitchenKey/${t.code}-$i').length)
  ];
}

/// The household-specific module tree and the modules these answers require (same rules as the web client).
HouseholdTree deriveTree(ProfileDraft d, Catalog c) {
  final ks = kitchenList(d);
  final storage = {for (final k in ks) k.key: storageList(d, c, k.key)};
  final equipment = {for (final k in ks) k.key: (d.appliances[k.key]?.length ?? 0) + (d.cookware[k.key]?.length ?? 0) + (d.utensils[k.key]?.length ?? 0)};
  final storageCount = storage.values.fold<int>(0, (n, l) => n + l.length);
  final equipmentCount = equipment.values.fold<int>(0, (n, v) => n + v);
  final members = d.family.length;
  final health = d.family.any((m) => m.allergies.isNotEmpty || m.diets.isNotEmpty || m.health.isNotEmpty);
  final canCook = ks.any((k) => (d.appliances[k.key] ?? const []).isNotEmpty);
  return HouseholdTree(ks, storage, equipment, storageCount, equipmentCount, members, [
    const ModuleFlag('HOUSEHOLD', 'Household', true),
    ModuleFlag('KITCHEN', 'Kitchens', ks.isNotEmpty),
    ModuleFlag('STORAGE', 'Storage ($storageCount)', storageCount > 0),
    ModuleFlag('EQUIPMENT', 'Appliances & tools', equipmentCount > 0),
    ModuleFlag('FAMILY', 'Family', members > 0),
    ModuleFlag('HEALTH', 'Health & diet', health),
    ModuleFlag('INVENTORY', 'Inventory', storageCount > 0),
    ModuleFlag('SHOPPING', 'Shopping list', storageCount > 0),
    ModuleFlag('MATCHING', 'Meal matching', members > 0 && storageCount > 0 && canCook),
    ModuleFlag('MEALS', 'Meal history', members > 0 && storageCount > 0 && canCook),
  ]);
}
