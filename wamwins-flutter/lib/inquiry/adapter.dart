import 'draft_v2.dart';
import 'entry_ref.dart';

/// v1 Flutter draft (local_setting "profile.draft.<user>", questionnaire v1) -> v2 draft. The v1 record keys are kept
/// (kitchen:MAIN-1, storage:MAIN-1/REFRIGERATOR-1, equipment:MAIN-1:WOK, member:<key>, food:<key>), so saving again on an
/// existing household adds only what is new. The v1 draft and answers are never rewritten.
const _legacyKitchens = [('MAIN', 'Main kitchen'), ('SECONDARY', 'Second kitchen'), ('OUTDOOR', 'Outdoor kitchen'), ('BASEMENT', 'Basement kitchen'), ('OTHER', 'Other kitchen')];

DraftV2 adaptV1(EntryRef ref, J v1) {
  final counts = Map<String, dynamic>.from(v1['kitchens'] as Map? ?? {'MAIN': 1});
  final storageAll = Map<String, dynamic>.from(v1['storage'] as Map? ?? {});
  final kitchens = <J>[], appliances = <J>[], kitchenware = <J>[];
  for (final (code, name) in _legacyKitchens) {
    final n = (counts[code] as num?)?.toInt() ?? 0;
    for (var i = 1; i <= n; i++) {
      final key = '$code-$i';
      final st = Map<String, dynamic>.from(storageAll[key] as Map? ?? {});
      final storage = <J>[];
      for (final t in ref.storageTypes) {
        final c = (st[t['code']] as num?)?.toInt() ?? 0;
        for (var j = 1; j <= c; j++) { storage.add({'key': '$key/${t['code']}-$j', 'type': t['code'], 'name': c > 1 ? '${t['name']} $j' : t['name'], 'counts': <String, dynamic>{}, 'custom': <J>[], 'legacy': true}); }
      }
      kitchens.add({'key': key, 'kind': ref.kitchenKinds.any((k) => k['code'] == code) ? code : null, 'legacyType': code, 'name': n > 1 ? '$name $i' : name, 'storage': storage});
      for (final c in ((v1['appliances'] as Map?)?[key] as List? ?? const [])) {
        appliances.add({'key': '$key:$c', 'pkey': 'equipment:$key:$c', 'kitchenKey': key, 'code': c, 'name': ref.nameOf(ref.appliances, c), 'condition': 'WORKING'});
      }
      for (final c in [...((v1['cookware'] as Map?)?[key] as List? ?? const []), ...((v1['utensils'] as Map?)?[key] as List? ?? const [])]) {
        final t = ref.kitchenware.where((k) => k['code'] == c).firstOrNull;
        kitchenware.add({'key': '$key:$c', 'pkey': 'equipment:$key:$c', 'kitchenKey': key, 'code': t == null ? null : c, 'category': t?['category'] ?? 'COOKWARE',
          'name': t?['name'] ?? '$c'.replaceAll('_', ' ').toLowerCase(), 'quantity': 1});
      }
    }
  }
  final family = ((v1['family'] as List?) ?? const []).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  bool restricted(J m) => ((m['allergies'] as List?)?.isNotEmpty ?? false) || ((m['diets'] as List?)?.isNotEmpty ?? false) || ((m['health'] as List?)?.isNotEmpty ?? false);
  final me = family.where((m) => m['isMe'] == true).firstOrNull;
  final people = [for (final m in family) if (restricted(m) || (m['isMe'] != true && family.length > 1))
    {'key': m['key'], 'name': m['name'], 'relationship': m['isMe'] == true ? 'SELF' : m['relationship'], 'ageBand': m['ageBand'], 'isMe': m['isMe'] == true,
      'allergies': m['allergies'] ?? [], 'intolerances': [], 'diets': m['diets'] ?? [], 'health': m['health'] ?? [], 'avoid': [], 'prioritize': [], 'meals': <String, dynamic>{}}];
  final about = Map<String, dynamic>.from(v1['about'] as Map? ?? {});
  about.putIfAbsent('measures', () => 'IMPERIAL');
  final size = (v1['householdSize'] as num?)?.toInt() ?? 2;
  return DraftV2(DraftV2.normalize({
    'version': 2, 'migratedFrom': 1, 'about': about, 'selfKey': me?['key'] ?? 'me',
    'household': {'name': v1['householdName'] ?? '', 'nickname': '', 'size': size, 'eaters': size},
    'health': {'needed': family.any(restricted) ? 'YES' : (family.isEmpty ? null : 'NO'), 'consent': v1['healthConsent'], 'people': people},
    'kitchens': kitchens, 'appliances': appliances, 'kitchenware': kitchenware,
    'food': [for (final f in ((v1['food'] as List?) ?? const []).cast<Map>()) {...Map<String, dynamic>.from(f), 'sectionKey': null}],
  }));
}
