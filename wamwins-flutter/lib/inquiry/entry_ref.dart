import '../core/db.dart';

/// Entry Module v2 reference data, read from the shared seeded tables (same codes and ids as the website and cloud).
/// Loaded once when onboarding opens (small lists) and released with it.
class EntryRef {
  EntryRef._(this.kitchenKinds, this.roles, this.storageTypes, this.questions, this.templates, this.appliances, this.kitchenware, this.packaging);
  final List<DbRow> kitchenKinds, roles, storageTypes, questions, templates, appliances, kitchenware, packaging;

  /// For tests and previews: build from plain lists (same column names as the tables).
  factory EntryRef.fromLists({List<DbRow> kitchenKinds = const [], List<DbRow> roles = const [], List<DbRow> storageTypes = const [], List<DbRow> questions = const [],
      List<DbRow> templates = const [], List<DbRow> appliances = const [], List<DbRow> kitchenware = const [], List<DbRow> packaging = const []}) =>
      EntryRef._(kitchenKinds, roles, storageTypes, questions, templates, appliances, kitchenware, packaging);

  static EntryRef load(AppDb db) => EntryRef._(
        db.select('SELECT code, name, legacy_kitchen_type FROM kitchen_kind WHERE active = 1 ORDER BY sort_order'),
        db.select('SELECT code, name FROM household_role WHERE active = 1 ORDER BY sort_order'),
        db.select('SELECT code, name, temperature_zone FROM storage_type WHERE active = 1 ORDER BY sort_order'),
        db.select('SELECT storage_type_code, code, label, section_kind, name_pattern, input_kind, default_value, max_value FROM storage_section_question ORDER BY sort_order'),
        db.select('SELECT id, storage_type_code, section_kind, default_name, ordinal FROM storage_section_template WHERE is_default_selected = 1 ORDER BY storage_type_code, ordinal'),
        db.select("SELECT code, name, power_source, size_rank, provides_storage_type_code FROM equipment_type WHERE equipment_class = 'APPLIANCE' AND active = 1 "
            "AND code <> 'CUSTOM_APPLIANCE' ORDER BY COALESCE(size_rank, 999), sort_order"),
        db.select('SELECT code, category, name, equipment_type_code FROM kitchenware_type WHERE active = 1 ORDER BY sort_order'),
        db.select('SELECT code, name FROM packaging_type ORDER BY sort_order'),
      );

  String nameOf(List<DbRow> list, Object? code) => list.where((r) => r['code'] == code).map((r) => r['name'] as String).firstOrNull ?? '${code ?? ''}';
  String zoneOf(String type) => storageTypes.where((r) => r['code'] == type).map((r) => r['temperature_zone'] as String).firstOrNull ?? 'AMBIENT';
  List<DbRow> questionsFor(String type) => questions.where((q) => q['storage_type_code'] == type).toList();
}
