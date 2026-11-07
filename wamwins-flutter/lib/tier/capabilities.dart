import '../core/db.dart';
import '../core/ids.dart';

/// Screens ask "can this household use X?" - never "which tier?" (conformance rule A3/C4).
class Capabilities {
  Capabilities(this.db);
  final AppDb db;

  bool canUse(String householdId, String code) =>
      db.first('''SELECT 1 AS x FROM capability c WHERE c.code = ? AND (c.is_platform_guaranteed = 1 OR EXISTS (
                    SELECT 1 FROM subscription_entitlement se JOIN subscription s ON s.id = se.subscription_id
                     WHERE se.household_id = ? AND se.capability_id = c.id AND se.is_entitled = 1
                       AND s.status IN ('TRIAL','ACTIVE','PAST_DUE')))''', [code, householdId]) != null;

  /// New household -> WAMWins Basic subscription + resolved entitlements and limits.
  /// Same resolution order as the cloud and the reference: PLATFORM_GUARANTEE > OVERRIDE > TIER.
  /// Call inside a transaction.
  void startBasic(String householdId, String userId) {
    final tier = db.first("SELECT id, product_id FROM product_tier WHERE tier_code = 'WAMWINS_BASIC' AND effective_to IS NULL")!;
    final subId = newId();
    db.run("INSERT INTO subscription(id, household_id, product_id, product_tier_id, billing_user_id, status, source_code) VALUES (?, ?, ?, ?, ?, 'ACTIVE', 'SYSTEM_DEFAULT')",
        [subId, householdId, tier['product_id'], tier['id'], userId]);
    db.run("INSERT INTO subscription_tier_history(id, subscription_id, household_id, from_tier_id, to_tier_id, reason, changed_by_user_id) VALUES (?, ?, ?, NULL, ?, 'INITIAL', ?)",
        [newId(), subId, householdId, tier['id'], userId]);
    final resolved = db.select('''
      SELECT c.id AS capability_id,
             CASE WHEN c.is_platform_guaranteed = 1 THEN 'ENABLED' ELSE COALESCE(tc.status, 'UNDEFINED') END AS status,
             CASE WHEN c.is_platform_guaranteed = 1 THEN 'PLATFORM_GUARANTEE' ELSE 'TIER' END AS resolved_from
        FROM capability c
        LEFT JOIN tier_capability tc ON tc.capability_id = c.id AND tc.tier_id = ? AND tc.effective_to IS NULL
       WHERE c.active = 1''', [tier['id']]);
    for (final r in resolved) {
      db.run('INSERT INTO subscription_entitlement(id, subscription_id, household_id, capability_id, status, resolved_from) VALUES (?, ?, ?, ?, ?, ?)',
          [newId(), subId, householdId, r['capability_id'], r['status'], r['resolved_from']]);
    }
    db.run('''INSERT INTO subscription_entitlement_parameter(entitlement_id, parameter_definition_id, integer_value, decimal_value, boolean_value, text_value)
              SELECT se.id, p.parameter_definition_id, p.integer_value, p.decimal_value, p.boolean_value, p.text_value
                FROM subscription_entitlement se
                JOIN tier_capability tc ON tc.capability_id = se.capability_id AND tc.tier_id = ? AND tc.effective_to IS NULL
                JOIN tier_capability_parameter p ON p.tier_capability_id = tc.id
               WHERE se.subscription_id = ? AND se.status = 'ENABLED' ''', [tier['id'], subId]);
  }
}
