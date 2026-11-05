import { tx } from '../data/db.js';
import { REF } from '../inquiry/reference.js';

/**
 * Capability gate for the UI. Screens ask "can this household use X?" - never "which tier?".
 * A new household starts on WAMWins Basic (Tier 1); entitlements are rows, so a future tier
 * changes data, not screens. Platform guarantees (privacy, export, deletion, backup) are always on.
 */
const cache = new Map();
export async function entitled(householdId) {
  if (!householdId) return new Set();
  if (cache.has(householdId)) return cache.get(householdId);
  const rows = await tx(['subscription_entitlement'], 'readonly', t => t.byIndex('subscription_entitlement', 'household_id', householdId));
  const set = new Set(rows.filter(r => r.status === 'ENABLED').map(r => r.capability_code));
  cache.set(householdId, set);
  return set;
}
export async function canUse(householdId, code) { return (await entitled(householdId)).has(code); }
export function invalidate(householdId) { cache.delete(householdId); }

/** Writes the Basic subscription + resolved entitlements inside the caller's transaction. */
export async function startBasic(t, householdId, userId) {
  const subId = crypto.randomUUID();
  await t.insert('subscription', { id: subId, household_id: householdId, product_code: 'WAMWINS', tier_code: 'WAMWINS_BASIC', tier_number: 1,
    billing_user_id: userId, status: 'ACTIVE', source_code: 'SYSTEM_DEFAULT', started_at: new Date().toISOString() });
  for (const code of REF.tier1Capabilities)
    await t.insert('subscription_entitlement', { id: crypto.randomUUID(), subscription_id: subId, household_id: householdId,
      capability_id: REF.capabilityIds[code], capability_code: code, status: 'ENABLED', resolved_from: 'TIER' });
}
