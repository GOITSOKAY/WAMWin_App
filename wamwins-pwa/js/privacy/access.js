import { tx, ALL_STORES } from '../data/db.js';
import { ACCESS_CATEGORIES } from './notices.js';

/**
 * Who may see a person's health details, which ones, and until when.
 *   - The person themselves (family_member.linked_user_id).
 *   - The household OWNER/ADMIN for profiles they manage: children and adults without their own account.
 *   - Anyone else ONLY through an access grant: grantee, categories, VIEW or VIEW_EDIT, starts_at, expires_at.
 *     Outside [starts_at, expires_at) or after revoked_at the grant gives nothing. Expiry needs no job to run:
 *     every check compares with the current time.
 * Same rules on the server (Postgres privacy.can_view_health, used by row-level security) and in Flutter.
 */
export const HEALTH_TABLE_CATEGORY = {
  member_allergy: 'ALLERGIES', member_intolerance: 'ALLERGIES', member_dietary_requirement: 'DIETS',
  member_health_food_requirement: 'HEALTH_GOALS', member_food_rule: 'FOOD_RULES', member_preference: 'MEAL_PREFERENCES',
};
const MINOR = new Set(['INFANT', 'TODDLER', 'CHILD', 'TEEN']);
export const isMinor = (member) => MINOR.has(member?.age_band);

export function grantStatus(g, now = Date.now()) {
  if (g.revoked_at) return 'REVOKED';
  if (Date.parse(g.starts_at) > now) return 'SCHEDULED';
  if (g.expires_at && Date.parse(g.expires_at) <= now) return 'EXPIRED';
  return 'ACTIVE';
}

/** The viewer's relationship to a member's data: 'SELF' | 'GUARDIAN' | 'GRANT' | null. */
export function relation({ userId, membership, member, grants, category, now = Date.now(), write = false }) {
  if (!member) return null;
  if (member.linked_user_id && member.linked_user_id === userId) return 'SELF';
  const manager = membership && ['OWNER', 'ADMIN'].includes(membership.role_code) && membership.status === 'ACTIVE';
  if (manager && (!member.linked_user_id || isMinor(member))) return 'GUARDIAN';
  const ok = (grants ?? []).some(g => g.subject_member_id === member.id && g.grantee_user_id === userId && grantStatus(g, now) === 'ACTIVE'
    && (!category || g.categories.includes(category)) && (!write || g.access_level === 'VIEW_EDIT'));
  return ok ? 'GRANT' : null;
}
export const canView = (ctx) => relation(ctx) !== null;
export const canManageSharing = (ctx) => ['SELF', 'GUARDIAN'].includes(relation({ ...ctx, category: null }));

export async function loadGrants(householdId) {
  return tx(['privacy_access_grant'], 'readonly', t => t.byIndex('privacy_access_grant', 'household_id', householdId));
}
export async function createGrant({ householdId, subject, grantedBy, grantee, categories, accessLevel = 'VIEW', startsAt, expiresAt, purpose }) {
  if (!categories?.length) throw new Error('Choose at least one kind of detail to share.');
  if (!['VIEW', 'VIEW_EDIT'].includes(accessLevel)) throw new Error('Unknown access level.');
  if (!categories.every(c => ACCESS_CATEGORIES.some(a => a.code === c))) throw new Error('Unknown detail type.');
  if (expiresAt && Date.parse(expiresAt) <= Date.parse(startsAt)) throw new Error('Access must end after it starts.');
  const row = { id: crypto.randomUUID(), household_id: householdId, subject_member_id: subject.id, subject_name: subject.display_name,
    grantee_user_id: grantee.userId ?? null, grantee_name: grantee.name, grantee_email: grantee.email ?? null,
    categories: [...new Set(categories)], access_level: accessLevel, starts_at: startsAt, expires_at: expiresAt ?? null,
    purpose: purpose || null, granted_by_user_id: grantedBy, granted_at: new Date().toISOString(), revoked_at: null, revoked_by_user_id: null };
  await tx(['privacy_access_grant', 'privacy_access_log'], 'readwrite', async t => {
    await t.add('privacy_access_grant', row);
    await t.add('privacy_access_log', logRow(householdId, grantedBy, subject.id, 'GRANT_CREATED', categories, row.id));
  });
  return row;
}
export async function revokeGrant(grant, userId) {
  await tx(['privacy_access_grant', 'privacy_access_log'], 'readwrite', async t => {
    const g = await t.get('privacy_access_grant', grant.id);
    if (!g || g.revoked_at) return;
    await t.put('privacy_access_grant', { ...g, revoked_at: new Date().toISOString(), revoked_by_user_id: userId });
    await t.add('privacy_access_log', logRow(g.household_id, userId, g.subject_member_id, 'GRANT_REVOKED', g.categories, g.id));
  });
}
const logRow = (householdId, actor, subjectId, action, categories, grantId = null) => ({ id: crypto.randomUUID(), household_id: householdId,
  actor_user_id: actor, subject_member_id: subjectId, action, categories, grant_id: grantId, at: new Date().toISOString() });
/** Accounting of disclosures: every view of someone else's health details through a grant is logged. */
export async function logView(householdId, userId, members, grants, categories, now = Date.now()) {
  const viewed = members.filter(m => relation({ userId, membership: null, member: m, grants, category: null, now }) === 'GRANT');
  if (!viewed.length) return;
  await tx(['privacy_access_log'], 'readwrite', async t => {
    for (const m of viewed) {
      const g = grants.find(x => x.subject_member_id === m.id && x.grantee_user_id === userId && grantStatus(x, now) === 'ACTIVE');
      await t.add('privacy_access_log', logRow(householdId, userId, m.id, 'VIEWED', categories.filter(c => g.categories.includes(c)), g.id));
    }
  });
}
export async function accessLog(householdId) {
  return (await tx(['privacy_access_log'], 'readonly', t => t.byIndex('privacy_access_log', 'household_id', householdId))).sort((a, b) => b.at.localeCompare(a.at));
}

/** Deletes one person's health details (withdrawn consent or a deletion request). Logged, never silent. */
export async function deleteHealthDetails(householdId, memberIds, userId) {
  const tables = Object.keys(HEALTH_TABLE_CATEGORY);
  let n = 0;
  await tx([...tables, 'privacy_access_log'], 'readwrite', async t => {
    for (const s of tables) for (const row of await t.byIndex(s, 'household_id', householdId))
      if (memberIds.includes(row.member_id)) { await t.del(s, row.id); n++; }
    for (const id of memberIds) await t.add('privacy_access_log', logRow(householdId, userId, id, 'HEALTH_DELETED', Object.values(HEALTH_TABLE_CATEGORY)));
  });
  return n;
}

/** Privacy requests (access, correction, deletion, appeal...). Due in 45 days, as state laws require. */
export async function fileRequest({ userId, householdId, type, details }) {
  const now = new Date();
  const row = { id: crypto.randomUUID(), user_id: userId, household_id: householdId, request_type: type, details: details || null,
    status: 'RECEIVED', requested_at: now.toISOString(), due_at: new Date(now.getTime() + 45 * 86400000).toISOString() };
  await tx(['privacy_request'], 'readwrite', t => t.add('privacy_request', row));
  return row;
}
export async function listRequests(userId) {
  return (await tx(['privacy_request'], 'readonly', t => t.byIndex('privacy_request', 'user_id', userId))).sort((a, b) => b.requested_at.localeCompare(a.requested_at));
}

/** Download a copy: everything this account and its household hold, as JSON (no password hashes, no session tokens). */
export async function exportData(user, householdId) {
  const SKIP = new Set(['auth_identity', 'session', 'media_blob', 'local_mutation_outbox', 'app_meta']);
  const stores = (await ALL_STORES()).filter(s => !SKIP.has(s));
  const out = { exported_at: new Date().toISOString(), format: 'wamwins-export-1', account: { id: user.id, email: user.email, display_name: user.display_name }, data: {} };
  await tx(stores, 'readonly', async t => {
    for (const s of stores) {
      let rows;
      if (s === 'user_account') rows = [await t.get(s, user.id)].filter(Boolean);
      else if (['consent_record', 'questionnaire_session', 'privacy_request'].includes(s)) rows = await t.byIndex(s, 'user_id', user.id);
      else if (householdId) { try { rows = await t.byIndex(s, 'household_id', householdId); } catch { rows = []; } }
      else rows = [];
      if (s === 'household' && householdId) rows = [await t.get(s, householdId)].filter(Boolean);
      if (s === 'answer') { rows = []; for (const q of await t.byIndex('questionnaire_session', 'user_id', user.id)) rows.push(...await t.byIndex('answer', 'session_id', q.id)); }
      if (rows?.length) out.data[s] = rows;
    }
  });
  return out;
}

/** Retention: meal and matching history older than 24 months is deleted (Privacy Notice, "How long we keep it"). */
export async function applyRetention(householdId, now = Date.now()) {
  const cutoff = new Date(now - 730 * 86400000).toISOString();
  const stores = ['match_run', 'match_run_member', 'match_result', 'match_result_factor', 'match_result_item', 'match_exclusion', 'meal_record', 'meal_participant', 'consumption_record'];
  let n = 0;
  await tx(stores, 'readwrite', async t => {
    for (const s of stores) for (const r of await t.byIndex(s, 'household_id', householdId))
      if ((r.created_at ?? r.recorded_at ?? r.started_at ?? '') && (r.created_at ?? r.recorded_at ?? r.started_at) < cutoff) { await t.del(s, r.id); n++; }
  });
  return n;
}
