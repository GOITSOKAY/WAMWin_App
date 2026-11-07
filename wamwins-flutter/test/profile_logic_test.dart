// Pure logic shared with the web client: kitchen keys, storage expansion, household tree, module rules,
// step validation and password strength. Run: flutter test test/profile_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wamwins/inquiry/catalog.dart';
import 'package:wamwins/inquiry/draft.dart';
import 'package:wamwins/screens/setup/steps.dart';
import 'package:wamwins/security/auth_service.dart';

Catalog _catalog() => Catalog(
      storageTypes: const [Option('REFRIGERATOR', 'Refrigerator'), Option('FREEZER', 'Freezer'), Option('PANTRY', 'Pantry')],
      storageZones: const {'REFRIGERATOR': 'CHILLED', 'FREEZER': 'FROZEN', 'PANTRY': 'AMBIENT'},
      sectionTemplates: const {'REFRIGERATOR': [('SHELF', 'Top shelf', 't1'), ('CRISPER', 'Crisper drawer', 't2')], 'PANTRY': [('SHELF', 'Shelf 1', 't3')]},
      appliances: const [Option('STOVETOP', 'Stovetop / burner')], cookware: const [Option('WOK', 'Wok')], utensils: const [],
      allergens: const [Option('PEANUT', 'Peanuts')], diets: const [Option('DAIRY_FREE', 'Dairy-free')], healthGoals: const [], cuisines: const [],
      items: const [], units: const [UnitInfo('G', 'g', 'MASS'), UnitInfo('KG', 'kg', 'MASS'), UnitInfo('PIECE', 'pc', 'COUNT'), UnitInfo('PACK', 'pack', 'COUNT'), UnitInfo('CAN', 'can', 'COUNT')]);

void main() {
  test('household A vs B: only what each household has', () {
    final c = _catalog();
    final a = ProfileDraft()..kitchens = {'MAIN': 1}..storage = {'MAIN-1': {'REFRIGERATOR': 1, 'FREEZER': 1, 'PANTRY': 1}};
    final b = ProfileDraft()..kitchens = {'MAIN': 1, 'OUTDOOR': 1}..storage = {'MAIN-1': {'REFRIGERATOR': 1}, 'OUTDOOR-1': {'REFRIGERATOR': 2}};
    expect(deriveTree(a, c).storageCount, 3);
    final tb = deriveTree(b, c);
    expect(tb.kitchens.map((k) => k.name), ['Main kitchen', 'Outdoor kitchen']);
    expect(tb.storage['OUTDOOR-1']!.map((s) => s.name), ['Refrigerator 1', 'Refrigerator 2']);
    expect(tb.storage['MAIN-1']!.first.sections, ['Top shelf', 'Crisper drawer']);
  });

  test('modules follow the answers (same rules as the web client)', () {
    final c = _catalog();
    final d = ProfileDraft()..kitchens = {'MAIN': 1}..storage = {'MAIN-1': {'PANTRY': 1}};
    var on = deriveTree(d, c).modules.where((m) => m.on).map((m) => m.code).toSet();
    expect(on.containsAll({'HOUSEHOLD', 'KITCHEN', 'STORAGE', 'INVENTORY', 'SHOPPING'}), isTrue);
    expect(on.contains('MATCHING'), isFalse, reason: 'no family and no cooking appliance yet');
    d.family.add(Member(key: 'm', name: 'Ben', relationship: 'CHILD', ageBand: 'CHILD', allergies: ['PEANUT']));
    d.appliances['MAIN-1'] = ['STOVETOP'];
    on = deriveTree(d, c).modules.where((m) => m.on).map((m) => m.code).toSet();
    expect(on.containsAll({'FAMILY', 'HEALTH', 'EQUIPMENT', 'MATCHING', 'MEALS'}), isTrue);
  });

  test('validation messages', () {
    final d = ProfileDraft()..kitchens = {'MAIN': 0};
    expect(validateStep('about', d), 'Enter your name to continue.');
    d.householdName = 'Home';
    expect(validateStep('household', d), 'Add at least one kitchen.');
    d.kitchens = {'MAIN': 1}..addAll({});
    d.storage = {'MAIN-1': {}};
    expect(validateStep('kitchens', d), contains('at least one place'));
    expect(validateStep('family', d), 'Add at least one person.');
  });

  test('draft survives a save/resume round trip', () {
    final d = ProfileDraft()..householdName = 'Santos'..family.add(Member(key: 'k', name: 'Ana', relationship: 'SELF', ageBand: 'ADULT', isMe: true, diets: ['DAIRY_FREE']));
    final back = ProfileDraft.fromJson(d.toJson());
    expect(back.encode(), d.encode());
  });

  test('password rules match the web client', () {
    expect(passwordStrength('short').message, 'Add 5 more characters.');
    expect(passwordStrength('password1234').score, 1);
    expect(passwordStrength('Mango-Sunset-2026!').score, greaterThanOrEqualTo(3));
    expect(validEmail('ana@example.com'), isTrue);
    expect(validEmail('ana@'), isFalse);
  });
}
