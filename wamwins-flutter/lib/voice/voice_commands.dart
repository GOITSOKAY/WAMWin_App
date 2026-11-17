/// Voice command parsing (pure; same rules and phrases as the web client, frontend/www/js/voice/engine.js).
class VoiceIntent {
  const VoiceIntent(this.kind, {this.route, this.say, this.name, this.quantity, this.slot});
  final String kind;            // NAVIGATE | MATCH | STOCK | ADD | NONE | UNKNOWN
  final String? route, say, name, slot;
  final num? quantity;
}

const _num = {'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'twelve': 12, 'dozen': 12};
final _nav = [
  (RegExp(r'\b(inventory|pantry|food list|my food)\b'), 'inventory', 'Opening inventory'),
  (RegExp(r'\b(privacy|sharing|consent)\b'), 'privacy', 'Opening Privacy & sharing'),
  (RegExp(r'\bsettings?\b'), 'settings', 'Opening settings'),
  (RegExp(r'\b(home|dashboard|start)\b'), 'home', 'Going home'),
];

VoiceIntent parseCommand(String? raw) {
  final t = (raw ?? '').toLowerCase().replaceAll(RegExp(r'[.,!?]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return const VoiceIntent('NONE');
  if (RegExp(r"\b(what can (we|i) (cook|make|eat)|find (a )?meals?|meal ideas?|suggest (a )?meals?|what'?s for (dinner|lunch|breakfast))\b").hasMatch(t)) {
    final slot = RegExp(r'\b(breakfast|lunch|dinner|snack|dessert)\b').firstMatch(t)?.group(1);
    return VoiceIntent('MATCH', slot: slot?.toUpperCase());
  }
  var m = RegExp(r'^(?:please )?add (?:(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten|twelve|dozen) )?(?:(?:pounds?|lbs?|ounces?|oz|cups?|cans?|bags?|boxes?|packs?|pieces?|dozen) (?:of )?)?(.+)$').firstMatch(t);
  if (m != null) {
    final name = m.group(2)!.replaceFirst(RegExp(r'^(of|some) '), '').replaceFirst(RegExp(r' to (the )?(inventory|list|pantry|fridge|refrigerator)$'), '').trim();
    if (name.isNotEmpty) return VoiceIntent('ADD', name: name, quantity: m.group(1) == null ? null : (num.tryParse(m.group(1)!) ?? _num[m.group(1)]));
  }
  m = RegExp(r'\bhow (?:much|many) (.+?) (?:do|does) (?:we|i) have\b').firstMatch(t);
  if (m != null) return VoiceIntent('STOCK', name: m.group(1)!.trim());
  m = RegExp(r'\b(?:do (?:we|i) have(?: any)?|is there(?: any)?|are there(?: any)?) (.+?)(?: left| in the house| at home)?$').firstMatch(t);
  if (m != null) return VoiceIntent('STOCK', name: m.group(1)!.replaceFirst(RegExp(r'^(any|some) '), '').trim());
  if (RegExp(r'\b(open|go to|show|take me to|view)\b').hasMatch(t)) {
    for (final (re, route, say) in _nav) { if (re.hasMatch(t)) return VoiceIntent('NAVIGATE', route: route, say: say); }
  }
  return const VoiceIntent('UNKNOWN');
}
