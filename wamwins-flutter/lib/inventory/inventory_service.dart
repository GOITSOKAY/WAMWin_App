import '../core/db.dart';
import '../core/ids.dart';

/// Manual inventory for the Flutter app - same rules as every client. Quantities change ONLY by inserting an
/// inventory_transaction; the shared database triggers (trg_txn_validate / trg_txn_apply) check it and apply the
/// quantity and lifecycle status. This class adds the friendly checks and messages before the database does.
class InventoryException implements Exception {
  InventoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _effect = {'OPENING_BALANCE': 1, 'MANUAL_ADD': 1, 'PURCHASE': 1, 'TRANSFER_IN': 1, 'MEAL_USAGE': -1, 'WASTE': -1, 'EXPIRED': -1, 'RETURN': -1,
  'TRANSFER_OUT': -1, 'CORRECTION': 0, 'OTHER': 0};
const typeNames = {'OPENING_BALANCE': 'Opening balance', 'MANUAL_ADD': 'Added', 'PURCHASE': 'Bought', 'TRANSFER_IN': 'Moved in', 'MEAL_USAGE': 'Used in a meal',
  'WASTE': 'Thrown away', 'EXPIRED': 'Expired', 'RETURN': 'Returned', 'TRANSFER_OUT': 'Moved out', 'CORRECTION': 'Corrected', 'OTHER': 'Used'};
const _needsReason = {'WASTE', 'CORRECTION', 'OTHER'};
double r4(num v) => (v * 10000).roundToDouble() / 10000;
String fmtQty(num v) { final d = r4(v); return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString(); }

class Flags {
  Flags(DbRow i, String today) : usedUp = !((i['quantity'] as num) > 0),
        expired = (i['quantity'] as num) > 0 && (((i['expires_on'] as String?) != null && (i['expires_on'] as String).compareTo(today) < 0) || i['lifecycle_status'] == 'EXPIRED'),
        low = (i['quantity'] as num) > 0 && i['lifecycle_status'] == 'LOW',
        opened = (i['quantity'] as num) > 0 && i['opened_on'] != null,
        useSoonRaw = (i['quantity'] as num) > 0 && i['use_soon_on'] != null && (i['use_soon_on'] as String).compareTo(addDaysIso(today, 3)) <= 0;
  final bool usedUp, expired, low, opened, useSoonRaw;
  bool get useSoon => useSoonRaw && !expired;
}

class InventoryService {
  InventoryService(this.db);
  final AppDb db;

  /// Storage places, in kitchen order, with a display label.
  List<DbRow> places(String hh) {
    final multi = db.count('SELECT COUNT(*) FROM kitchen WHERE household_id = ? AND deleted_at IS NULL', [hh]) > 1;
    return [for (final r in db.select('SELECT s.id, s.kitchen_id, s.name, s.temperature_zone, k.name AS kitchen_name FROM storage_instance s JOIN kitchen k ON k.id = s.kitchen_id '
        'WHERE s.household_id = ? AND s.deleted_at IS NULL ORDER BY k.sort_order, s.sort_order', [hh])) {...r, 'label': multi ? '${r['name']} (${r['kitchen_name']})' : r['name']}];
  }
  List<DbRow> sections(String storageId) => db.select('SELECT id, name FROM storage_section WHERE storage_instance_id = ? AND deleted_at IS NULL ORDER BY ordinal', [storageId]);

  /// One page of items (never the whole household). [show]: IN_STOCK, USE_SOON, EXPIRED, LOW, USED_UP.
  List<DbRow> items(String hh, {String? storageId, String query = '', String show = 'IN_STOCK', int limit = 50, required String today}) {
    final where = StringBuffer('i.household_id = ? AND i.deleted_at IS NULL');
    final args = <Object?>[hh];
    if (storageId != null) { where.write(' AND i.storage_instance_id = ?'); args.add(storageId); }
    if (query.trim().isNotEmpty) { where.write(' AND lower(COALESCE(m.canonical_name, i.label)) LIKE ?'); args.add('%${query.trim().toLowerCase()}%'); }
    switch (show) {
      case 'USED_UP': where.write(' AND i.quantity = 0'); break;
      case 'LOW': where.write(" AND i.quantity > 0 AND i.lifecycle_status = 'LOW'"); break;
      case 'EXPIRED': where.write(" AND i.quantity > 0 AND ((i.expires_on IS NOT NULL AND i.expires_on < ?) OR i.lifecycle_status = 'EXPIRED')"); args.add(today); break;
      case 'USE_SOON': where.write(' AND i.quantity > 0 AND i.use_soon_on IS NOT NULL AND i.use_soon_on <= ? AND NOT (i.expires_on IS NOT NULL AND i.expires_on < ?)');
        args..add(addDaysIso(today, 3))..add(today); break;
      default: where.write(' AND i.quantity > 0');
    }
    return db.select('SELECT i.*, COALESCE(m.canonical_name, i.label) AS food_name, u.symbol, sec.name AS section_name, s.sort_order AS s_order, k.sort_order AS k_order '
        'FROM inventory_item i JOIN item_master m ON m.id = i.item_master_id JOIN unit_of_measure u ON u.code = i.unit_code '
        'JOIN storage_instance s ON s.id = i.storage_instance_id JOIN kitchen k ON k.id = i.kitchen_id LEFT JOIN storage_section sec ON sec.id = i.storage_section_id '
        'WHERE $where ORDER BY k.sort_order, s.sort_order, lower(COALESCE(m.canonical_name, i.label)) LIMIT ?', [...args, limit + 1]);
  }

  ({int soon, int expired, int low}) attention(String hh, String today) => (
        soon: db.count('SELECT COUNT(*) FROM inventory_item WHERE household_id = ? AND deleted_at IS NULL AND quantity > 0 AND use_soon_on IS NOT NULL AND use_soon_on <= ? '
            'AND NOT (expires_on IS NOT NULL AND expires_on < ?)', [hh, addDaysIso(today, 3), today]),
        expired: db.count("SELECT COUNT(*) FROM inventory_item WHERE household_id = ? AND deleted_at IS NULL AND quantity > 0 AND ((expires_on IS NOT NULL AND expires_on < ?) OR lifecycle_status = 'EXPIRED')", [hh, today]),
        low: db.count("SELECT COUNT(*) FROM inventory_item WHERE household_id = ? AND deleted_at IS NULL AND quantity > 0 AND lifecycle_status = 'LOW'", [hh]),
      );

  DbRow? item(String hh, String id) => db.first('SELECT i.*, COALESCE(m.canonical_name, i.label) AS food_name, m.household_id AS food_household, u.symbol, '
      'sec.name AS section_name, s.name AS storage_name, s.temperature_zone, m.shelf_life_ambient_days, m.shelf_life_chilled_days, m.shelf_life_frozen_days, m.shelf_life_opened_days '
      'FROM inventory_item i JOIN item_master m ON m.id = i.item_master_id JOIN unit_of_measure u ON u.code = i.unit_code JOIN storage_instance s ON s.id = i.storage_instance_id '
      'LEFT JOIN storage_section sec ON sec.id = i.storage_section_id WHERE i.id = ? AND i.household_id = ?', [id, hh]);

  List<DbRow> history(String hh, String itemId) => db.select('SELECT transaction_type_code, quantity_delta, quantity_before, quantity_after, occurred_at, reason, unit_code '
      'FROM inventory_transaction WHERE household_id = ? AND inventory_item_id = ? ORDER BY occurred_at DESC, recorded_at DESC LIMIT 50', [hh, itemId]);

  /// Append one transaction (inside or outside a transaction); the triggers apply it.
  String post({required String hh, required String itemId, required String type, required double delta, String? reason, required String userId,
      String? groupId, String? relatedId, String? unitLabel}) {
    final eff = _effect[type];
    if (eff == null) throw InventoryException('Unknown change type $type');
    final d = r4(delta);
    if (d == 0) throw InventoryException('Enter an amount greater than zero.');
    if ((eff > 0 && d < 0) || (eff < 0 && d > 0)) throw InventoryException('That change goes the wrong way.');
    if (_needsReason.contains(type) && (reason ?? '').trim().isEmpty) throw InventoryException('Please choose a reason.');
    final cur = db.first('SELECT quantity, unit_code FROM inventory_item WHERE id = ? AND household_id = ? AND deleted_at IS NULL', [itemId, hh]);
    if (cur == null) throw InventoryException('This food is no longer in your inventory.');
    final before = r4(cur['quantity'] as num), after = r4(before + d);
    if (after < 0) throw InventoryException('Only ${fmtQty(before)} ${unitLabel ?? (cur['unit_code'] as String).toLowerCase()} left.');
    final id = newId();
    db.run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, "
        "actor_user_id, transfer_group_id, related_inventory_item_id, reason, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
        [id, hh, itemId, type, d, cur['unit_code'], before, after, userId, groupId, relatedId, reason?.trim()]);
    return id;
  }

  static String? useSoonOn({String? purchasedOn, String? zone, required DbRow food, String? expiresOn, String? bestBeforeOn, String? openedOn}) {
    final life = food[zone == 'FROZEN' ? 'shelf_life_frozen_days' : zone == 'CHILLED' ? 'shelf_life_chilled_days' : 'shelf_life_ambient_days'] as int?;
    final opened = food['shelf_life_opened_days'] as int?;
    final c = <String>[if (expiresOn != null) expiresOn, if (bestBeforeOn != null) bestBeforeOn, if (purchasedOn != null && life != null) addDaysIso(purchasedOn, life),
      if (openedOn != null && opened != null) addDaysIso(openedOn, opened)]..sort();
    return c.isEmpty ? null : c.first;
  }

  DbRow _food(String hh, String itemMasterId) => db.first('SELECT id, canonical_name, default_unit_code, shelf_life_ambient_days, shelf_life_chilled_days, shelf_life_frozen_days, shelf_life_opened_days '
      'FROM item_master WHERE id = ? AND (household_id IS NULL OR household_id = ?) AND deleted_at IS NULL', [itemMasterId, hh]) ?? (throw InventoryException('Unknown food.'));

  /// New lot at 0 + its opening transaction.
  String createLot({required String hh, required String userId, required String itemMasterId, required String storageId, String? sectionId, required double quantity,
      required String unit, String? purchasedOn, String? openedOn, String? expiresOn, String? bestBeforeOn, double? lowStock, String? notes,
      String type = 'MANUAL_ADD', String? groupId, String? relatedId}) {
    if (!(quantity > 0)) throw InventoryException('Enter an amount greater than zero.');
    return db.transaction(() {
      final food = _food(hh, itemMasterId);
      final s = db.first('SELECT kitchen_id, temperature_zone FROM storage_instance WHERE id = ? AND household_id = ?', [storageId, hh]) ?? (throw InventoryException('Unknown storage place.'));
      final bought = purchasedOn ?? todayIso();
      final id = newId();
      db.run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, storage_section_id, quantity, unit_code, low_stock_threshold, "
          "purchased_on, opened_on, best_before_on, expires_on, use_soon_on, label, notes, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
          [id, hh, itemMasterId, s['kitchen_id'], storageId, sectionId, unit, lowStock, bought, openedOn, bestBeforeOn, expiresOn,
            useSoonOn(purchasedOn: bought, zone: s['temperature_zone'] as String?, food: food, expiresOn: expiresOn, bestBeforeOn: bestBeforeOn, openedOn: openedOn),
            food['canonical_name'], notes]);
      post(hh: hh, itemId: id, type: type, delta: quantity, userId: userId, groupId: groupId, relatedId: relatedId);
      return id;
    });
  }

  /// Move part or all: TRANSFER_OUT here + new lot with TRANSFER_IN there (one group id). Returns the new lot id.
  String transfer({required String hh, required String userId, required String itemId, required String toStorageId, String? toSectionId, required double quantity}) =>
      db.transaction(() {
        final src = db.first('SELECT * FROM inventory_item WHERE id = ? AND household_id = ?', [itemId, hh]) ?? (throw InventoryException('Unknown item.'));
        if (toStorageId == src['storage_instance_id'] && toSectionId == src['storage_section_id']) throw InventoryException('Choose a different place or shelf.');
        final group = newId();
        post(hh: hh, itemId: itemId, type: 'TRANSFER_OUT', delta: -quantity, userId: userId, groupId: group);
        return createLot(hh: hh, userId: userId, itemMasterId: src['item_master_id'] as String, storageId: toStorageId, sectionId: toSectionId, quantity: quantity,
            unit: src['unit_code'] as String, purchasedOn: src['purchased_on'] as String?, openedOn: src['opened_on'] as String?, expiresOn: src['expires_on'] as String?,
            bestBeforeOn: src['best_before_on'] as String?, lowStock: (src['low_stock_threshold'] as num?)?.toDouble(), notes: src['notes'] as String?,
            type: 'TRANSFER_IN', groupId: group, relatedId: itemId);
      });

  /// Details (no quantity change): shelf, dates, running-low level, note, opened. Recomputes use-soon and status.
  void setDetails({required String hh, required String itemId, String? sectionId, String? expiresOn, String? purchasedOn, double? lowStock, String? notes, String? openedOn}) =>
      db.transaction(() {
        final it = item(hh, itemId) ?? (throw InventoryException('Unknown item.'));
        final qty = (it['quantity'] as num).toDouble();
        final soon = useSoonOn(purchasedOn: purchasedOn, zone: it['temperature_zone'] as String?, food: it, expiresOn: expiresOn,
            bestBeforeOn: it['best_before_on'] as String?, openedOn: openedOn);
        final status = qty <= 0 ? it['lifecycle_status'] : (lowStock != null && qty <= lowStock) ? 'LOW' : openedOn != null ? 'OPENED' : 'ACTIVE';
        db.run("UPDATE inventory_item SET storage_section_id = ?, expires_on = ?, purchased_on = ?, low_stock_threshold = ?, notes = ?, opened_on = ?, use_soon_on = ?, "
            "lifecycle_status = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND household_id = ?",
            [sectionId, expiresOn, purchasedOn, lowStock, notes, openedOn, soon, status, itemId, hh]);
      });

  void remove(String hh, String itemId) {
    final it = db.first('SELECT quantity FROM inventory_item WHERE id = ? AND household_id = ?', [itemId, hh]);
    if (it == null) return;
    if ((it['quantity'] as num) > 0) throw InventoryException('Use up or throw away the stock first.');
    db.run("UPDATE inventory_item SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'), row_version = row_version + 1 WHERE id = ? AND household_id = ?", [itemId, hh]);
  }

  // ---------------------------------------------------------------- the household's own foods
  List<DbRow> myFoods(String hh) => db.select("SELECT m.*, (SELECT group_concat(allergen_code) FROM item_allergen a WHERE a.item_master_id = m.id) AS allergens, "
      "(SELECT COUNT(*) FROM inventory_item i WHERE i.item_master_id = m.id AND i.deleted_at IS NULL) AS lots, "
      "(SELECT COUNT(*) FROM inventory_item i WHERE i.item_master_id = m.id AND i.deleted_at IS NULL AND i.quantity > 0) AS in_stock "
      "FROM item_master m WHERE m.household_id = ? AND m.deleted_at IS NULL ORDER BY m.search_name", [hh]);

  bool nameTaken(String hh, String name, {String? exceptId}) => db.first('SELECT 1 AS x FROM item_master WHERE (household_id IS NULL OR household_id = ?) AND deleted_at IS NULL '
      'AND search_name = ? AND id <> ?', [hh, name.trim().toLowerCase(), exceptId ?? '']) != null;

  String createFood({required String hh, required String name, required String category, required String unit, required String zone, required List<String> allergens}) =>
      db.transaction(() {
        if (nameTaken(hh, name)) throw InventoryException('“$name” already exists.');
        final id = newId();
        db.run("INSERT INTO item_master(id, household_id, item_kind, canonical_name, food_category_code, default_unit_code, storage_zone, is_perishable, is_verified, created_source_code) "
            "VALUES (?, ?, 'FOOD', ?, ?, ?, ?, ?, 0, 'MANUAL')", [id, hh, name.trim(), category, unit, zone, zone == 'AMBIENT' ? 0 : 1]);
        for (final a in allergens) {
          db.run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, ?, 'CONTAINS')", [id, a]);
        }
        return id;
      });

  void updateFood({required String hh, required String id, required String name, required String category, required String unit, required String zone, required List<String> allergens}) =>
      db.transaction(() {
        if (nameTaken(hh, name, exceptId: id)) throw InventoryException('“$name” already exists. Choose another name.');
        final hasLots = db.count('SELECT COUNT(*) FROM inventory_item WHERE item_master_id = ? AND deleted_at IS NULL', [id]) > 0;
        db.run("UPDATE item_master SET canonical_name = ?, food_category_code = ?, default_unit_code = CASE WHEN ? THEN default_unit_code ELSE ? END, storage_zone = ?, "
            "is_perishable = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND household_id = ?",
            [name.trim(), category, hasLots ? 1 : 0, unit, zone, zone == 'AMBIENT' ? 0 : 1, id, hh]);
        db.run('DELETE FROM item_allergen WHERE item_master_id = ?', [id]);
        for (final a in allergens) {
          db.run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, ?, 'CONTAINS')", [id, a]);
        }
        db.run('UPDATE inventory_item SET label = ? WHERE item_master_id = ? AND household_id = ?', [name.trim(), id, hh]);
      });

  void removeFood(String hh, String id) {
    if (db.count('SELECT COUNT(*) FROM inventory_item WHERE item_master_id = ? AND deleted_at IS NULL AND quantity > 0', [id]) > 0) {
      throw InventoryException('Use up or throw away the stock first.');
    }
    db.run("UPDATE item_master SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND household_id = ?", [id, hh]);
  }
}
