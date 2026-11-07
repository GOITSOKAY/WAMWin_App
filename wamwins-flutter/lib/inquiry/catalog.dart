import '../core/db.dart';

class Option {
  const Option(this.code, this.name, [this.hint]);
  final String code;
  final String name;
  final String? hint;
}

class ItemInfo {
  const ItemInfo(this.id, this.name, this.unit, this.zone, this.shelfLife);
  final String id;
  final String name;
  final String unit;
  final String zone;
  final Map<String, int?> shelfLife; // AMBIENT / CHILLED / FROZEN
}

class UnitInfo {
  const UnitInfo(this.code, this.symbol, this.dimension);
  final String code;
  final String symbol;
  final String dimension;
}

/// Reference lists read from the shared seeded tables (same ids as the cloud and the web app).
/// Loaded once when profiling opens (a few hundred small rows) and released with it.
class Catalog {
  Catalog({required this.storageTypes, required this.storageZones, required this.sectionTemplates, required this.appliances,
      required this.cookware, required this.utensils, required this.allergens, required this.diets, required this.healthGoals,
      required this.cuisines, required this.items, required this.units, this.foodGroups = const []});
  final List<Option> storageTypes;
  final Map<String, String> storageZones;
  final Map<String, List<(String kind, String name, String templateId)>> sectionTemplates;
  final List<Option> appliances, cookware, utensils, allergens, diets, healthGoals, cuisines;
  final List<ItemInfo> items;
  final List<UnitInfo> units;
  final List<Option> foodGroups;

  /// Global list + (when [householdId] is given) the household's own foods.
  static Catalog load(AppDb db, {String? householdId}) {
    List<Option> opts(String sql) => [for (final r in db.select(sql)) Option(r['code'] as String, r['name'] as String)];
    List<Option> equipment(String cls) => opts("SELECT code, name FROM equipment_type WHERE equipment_class = '$cls' AND active = 1 "
        "AND code NOT IN ('REFRIGERATOR','UPRIGHT_FREEZER','CHEST_FREEZER') ORDER BY sort_order");
    final templates = <String, List<(String, String, String)>>{};
    for (final r in db.select('SELECT id, storage_type_code, section_kind, default_name FROM storage_section_template WHERE is_default_selected = 1 ORDER BY storage_type_code, ordinal')) {
      templates.putIfAbsent(r['storage_type_code'] as String, () => []).add((r['section_kind'] as String, r['default_name'] as String, r['id'] as String));
    }
    return Catalog(
      storageTypes: opts("SELECT code, name FROM storage_type WHERE code <> 'CUSTOM' AND active = 1 ORDER BY sort_order"),
      storageZones: {for (final r in db.select('SELECT code, temperature_zone FROM storage_type')) r['code'] as String: r['temperature_zone'] as String},
      sectionTemplates: templates,
      appliances: equipment('APPLIANCE'), cookware: equipment('COOKWARE'), utensils: equipment('UTENSIL'),
      allergens: opts('SELECT code, name FROM allergen ORDER BY rowid'),
      diets: opts('SELECT code, name FROM dietary_pattern ORDER BY rowid'),
      healthGoals: opts('SELECT code, name FROM food_requirement_type ORDER BY rowid'),
      cuisines: opts("SELECT code, name FROM cuisine WHERE code <> 'OTHER' ORDER BY rowid"),
      items: [for (final r in db.select('SELECT id, canonical_name, default_unit_code, storage_zone, shelf_life_ambient_days, shelf_life_chilled_days, shelf_life_frozen_days FROM item_master WHERE (household_id IS NULL OR household_id = ?) AND deleted_at IS NULL ORDER BY search_name', [householdId]))
        ItemInfo(r['id'] as String, r['canonical_name'] as String, r['default_unit_code'] as String, r['storage_zone'] as String,
            {'AMBIENT': r['shelf_life_ambient_days'] as int?, 'CHILLED': r['shelf_life_chilled_days'] as int?, 'FROZEN': r['shelf_life_frozen_days'] as int?})],
      units: [for (final r in db.select('SELECT code, symbol, dimension FROM unit_of_measure ORDER BY sort_order')) UnitInfo(r['code'] as String, r['symbol'] as String, r['dimension'] as String)],
      foodGroups: opts('SELECT code, name FROM food_category ORDER BY sort_order'),
    );
  }

  String nameOf(List<Option> list, String code) => list.firstWhere((o) => o.code == code, orElse: () => Option(code, code)).name;
  List<UnitInfo> unitsLike(String code) {
    final dim = units.firstWhere((u) => u.code == code, orElse: () => UnitInfo(code, code, 'OTHER')).dimension;
    return units.where((u) => u.dimension == dim && (dim != 'COUNT' || u.code == code || u.code == 'PIECE' || u.code == 'PACK')).toList();
  }
}

// Fixed choice lists for questions that are not reference tables (same codes as the web client).
const kitchenTypes = [Option('MAIN', 'Main kitchen'), Option('SECONDARY', 'Second kitchen'), Option('OUTDOOR', 'Outdoor kitchen'),
  Option('BASEMENT', 'Basement kitchen'), Option('OTHER', 'Other kitchen')];
const cookingRoles = [Option('ME', 'Mostly me'), Option('SHARED', 'We share it'), Option('OTHER', 'Someone else does')];
const skills = [Option('BEGINNER', 'Just starting out', 'Simple recipes with clear steps'), Option('COMFORTABLE', 'Comfortable', 'Everyday cooking is fine'),
  Option('CONFIDENT', 'Confident cook', 'Happy to try anything')];
const measures = [Option('METRIC', 'Metric', 'grams, millilitres'), Option('IMPERIAL', 'Imperial', 'ounces, cups')];
const relationships = [Option('PARTNER', 'Partner'), Option('CHILD', 'Child'), Option('PARENT', 'Parent'), Option('SIBLING', 'Sibling'),
  Option('GRANDPARENT', 'Grandparent'), Option('RELATIVE', 'Relative'), Option('CAREGIVER', 'Helper or caregiver'), Option('OTHER', 'Other')];
const ageBands = [Option('INFANT', 'Baby'), Option('TODDLER', 'Toddler'), Option('CHILD', 'Child'), Option('TEEN', 'Teen'), Option('ADULT', 'Adult'), Option('SENIOR', 'Senior')];
const storageHints = {'REFRIGERATOR': 'Fridge', 'FREEZER': 'Upright or top freezer', 'CHEST_FREEZER': 'Lift-top freezer',
  'HANGING_CABINET': 'Wall cabinet', 'GROUND_CABINET': 'Base cabinet under the counter'};
