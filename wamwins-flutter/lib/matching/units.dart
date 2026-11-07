import '../core/db.dart';

/// Port of src/modules/catalog/domain/UnitConverter.ts: same-dimension conversion via unit_of_measure,
/// cross-dimension via item_unit_conversion (e.g. 1 PIECE egg = 50 G). Returns null when impossible.
class UnitConverter {
  UnitConverter(this.db);
  final AppDb db;
  Map<String, (String dimension, String? base, double? factor)>? _units;
  final Map<String, List<(String from, String to, double factor)>> _itemConv = {};

  (String, String?, double?)? _unit(String code) {
    _units ??= {for (final r in db.select('SELECT code, dimension, base_unit_code, to_base_factor FROM unit_of_measure'))
      r['code'] as String: (r['dimension'] as String, r['base_unit_code'] as String?, (r['to_base_factor'] as num?)?.toDouble())};
    return _units![code];
  }

  ({double qty, String base})? _toBase(double qty, String code) {
    final u = _unit(code);
    if (u == null) return null;
    return u.$2 != null ? (qty: qty * u.$3!, base: u.$2!) : (qty: qty, base: code);
  }

  List<(String, String, double)> _conversions(String itemId) => _itemConv.putIfAbsent(itemId, () => [
        for (final r in db.select('SELECT from_unit_code, to_unit_code, factor FROM item_unit_conversion WHERE item_master_id = ?', [itemId]))
          (r['from_unit_code'] as String, r['to_unit_code'] as String, (r['factor'] as num).toDouble())
      ]);

  double? convert(double qty, String from, String to, [String? itemId]) {
    if (from == to) return qty;
    final a = _toBase(qty, from), b = _toBase(1, to);
    if (a == null || b == null) return null;
    if (a.base == b.base) return a.qty / b.qty;
    if (itemId == null) return null;
    for (final c in _conversions(itemId)) {
      final viaFrom = _toBase(1, c.$1), viaTo = _toBase(1, c.$2);
      if (viaFrom == null || viaTo == null) continue;
      if (viaFrom.base == a.base && viaTo.base == b.base) return (a.qty / viaFrom.qty) * c.$3 * viaTo.qty / b.qty;
      if (viaTo.base == a.base && viaFrom.base == b.base) return (a.qty / viaTo.qty) / c.$3 * viaFrom.qty / b.qty;
    }
    return null;
  }

  /// Grams or millilitres, for nutrient maths.
  ({double amount, String basis})? toMassOrVolume(double qty, String unit, String itemId) {
    final g = convert(qty, unit, 'G', itemId);
    if (g != null) return (amount: g, basis: 'G');
    final ml = convert(qty, unit, 'ML', itemId);
    return ml == null ? null : (amount: ml, basis: 'ML');
  }
}
