import { h, icon, clear, toast, field } from '../core/dom.js';
import { tx, get } from '../data/db.js';
import { ACCESS_CATEGORIES, ACCESS_DURATIONS, CONSENT } from '../privacy/notices.js';
import { askConsent, recordConsent, consentHistory, legalLinks, modal } from '../privacy/consent.js';
import { loadGrants, createGrant, revokeGrant, grantStatus, relation, accessLog, deleteHealthDetails, exportData, fileRequest, listRequests } from '../privacy/access.js';

// Privacy & sharing: consents, who can see each person's health details (and until when), access history,
// download/delete, and privacy requests. Free on every plan (platform guarantee).
const fmt = (iso) => iso ? new Date(iso).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
const catName = (c) => ACCESS_CATEGORIES.find(a => a.code === c)?.name ?? c;
const STATUS = { ACTIVE: ['ok', 'Active'], SCHEDULED: ['blue', 'Starts later'], EXPIRED: ['', 'Expired'], REVOKED: ['', 'Ended'] };
const CONSENT_ROWS = [
  ['TERMS', 'Terms of Use'], ['PRIVACY_POLICY', 'Privacy Notice'], ['HEALTH_DATA_PROCESSING', 'Collect and use health details'],
  ['MEDIA_PROCESSING', 'Reference photos'], ['VOICE_COMMANDS', 'Voice commands'],
];
const REQUESTS = [['ACCESS', 'Tell me what information you hold about me'], ['RECIPIENTS', 'List the people and companies that received my health data'],
  ['CORRECTION', 'Correct my information'], ['DELETION', 'Delete my information'], ['APPEAL', 'Appeal a decision on an earlier request'], ['OTHER', 'Something else']];
const toLocal = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);

export async function mount(root, ctx) {
  const user = ctx.user;
  const membership = (await tx(['household_membership'], 'readonly', t => t.byIndex('household_membership', 'user_id', user.id))).find(m => m.status === 'ACTIVE');
  const hh = membership?.household_id ?? null;
  const body = h('div', { class: 'stack-l' });

  async function draw() {
    const [members, grants, history, log, requests, memberships] = await Promise.all([
      hh ? tx(['family_member'], 'readonly', t => t.byIndex('family_member', 'household_id', hh)).then(r => r.filter(m => !m.deleted_at)) : [],
      hh ? loadGrants(hh) : [], consentHistory(user.id), hh ? accessLog(hh) : [], listRequests(user.id),
      hh ? tx(['household_membership'], 'readonly', t => t.byIndex('household_membership', 'household_id', hh)) : []]);
    const people = await Promise.all(memberships.filter(m => m.status === 'ACTIVE' && m.user_id !== user.id).map(async m => ({ userId: m.user_id, name: (await get('user_account', m.user_id))?.display_name ?? 'Household member' })));
    const managed = members.filter(m => ['SELF', 'GUARDIAN'].includes(relation({ userId: user.id, membership, member: m, grants, category: null })));
    const sharedWithMe = grants.filter(g => g.grantee_user_id === user.id);
    const nameOf = (id) => members.find(m => m.id === id)?.display_name ?? 'a family member';
    const latest = (type) => history.filter(r => r.consent_type === type && !r.subject_ref).at(-1);

    // ---- consents
    const consentList = h('div', { class: 'settings-list consent-status' }, CONSENT_ROWS.map(([type, label]) => {
      const r = latest(type), on = !!r?.granted;
      const action = type === 'TERMS' || type === 'PRIVACY_POLICY' ? null
        : on ? h('button', { type: 'button', class: 'btn-text', text: 'Withdraw', onclick: () => withdraw(type, label) })
        : h('button', { type: 'button', class: 'btn-text', text: 'Give consent', onclick: async () => { if (await askConsent(user.id, type)) { toast('Consent saved.'); draw(); } } });
      return h('div', {}, h('span', {}, h('b', { style: { fontWeight: 500 }, text: label }),
        h('span', { class: 'hint', style: { display: 'block' }, text: r ? `${on ? 'Given' : 'Not given'} ${fmt(r.recorded_at)} · version ${r.document_version ?? '1'}` : 'Not asked yet' })), action);
    }));

    // ---- who can see health details
    const sharing = managed.length ? managed.map(m => {
      const mine = grants.filter(g => g.subject_member_id === m.id).sort((a, b) => b.granted_at.localeCompare(a.granted_at));
      const rel = relation({ userId: user.id, membership, member: m, grants, category: null });
      return h('article', { class: 'member grant-card', 'aria-label': `Access to ${m.display_name}’s health details` },
        h('div', { class: 'member-head' }, h('span', { class: 'avatar', 'aria-hidden': 'true', text: m.display_name.slice(0, 1).toUpperCase() }),
          h('div', { class: 'who' }, h('b', { text: m.linked_user_id === user.id ? `${m.display_name} (you)` : m.display_name }),
            h('span', { class: 'hint', text: rel === 'SELF' ? 'Your details. Only you and the people below can see them.' : 'You manage this profile. Only you and the people below can see these details.' }))),
        mine.length ? h('ul', { class: 'grant-list' }, mine.map(g => {
          const st = grantStatus(g), [cls, label] = STATUS[st];
          return h('li', { 'data-grant': g.id }, h('div', {},
            h('b', { text: g.grantee_name }), h('span', { class: `tag ${cls}`, text: label }),
            h('span', { class: 'hint', style: { display: 'block' }, text: `${g.access_level === 'VIEW_EDIT' ? 'Can view and edit' : 'Can view'}: ${g.categories.map(catName).join(', ')}` }),
            h('span', { class: 'hint', style: { display: 'block' }, text: `From ${fmt(g.starts_at)} ${g.expires_at ? `until ${fmt(g.expires_at)}` : 'until you end it'}${g.purpose ? ` · ${g.purpose}` : ''}` })),
            ['ACTIVE', 'SCHEDULED'].includes(st) ? h('button', { type: 'button', class: 'btn-text', style: { color: 'var(--danger)' }, text: 'End access', onclick: async () => { await revokeGrant(g, user.id); toast(`${g.grantee_name} can no longer see ${m.display_name}’s details.`); draw(); } }) : null);
        })) : h('p', { class: 'hint', text: 'Nobody else has access.' }),
        h('button', { type: 'button', class: 'btn btn-ghost', 'data-give': m.id, onclick: () => giveAccess(m, people) }, icon('plus', 18), h('span', { text: 'Give access' })));
    }) : [h('p', { class: 'hint', text: 'Health profiles you manage will appear here.' })];

    const logList = log.slice(0, 25).map(l => h('li', {}, h('span', { class: 'hint', text: fmt(l.at) }), ' ',
      h('span', { text: `${l.actor_user_id === user.id ? 'You' : (people.find(p => p.userId === l.actor_user_id)?.name ?? 'Someone')} ${{ VIEWED: 'viewed', GRANT_CREATED: 'gave access to', GRANT_REVOKED: 'ended access to', HEALTH_DELETED: 'deleted' }[l.action] ?? l.action} ${nameOf(l.subject_member_id)}’s ${l.categories.map(c => catName(c).toLowerCase()).join(', ')}` })));

    clear(body).append(
      h('section', { class: 'panel', 'aria-labelledby': 'pv-c' }, h('h2', { id: 'pv-c', text: 'Your consents' }),
        h('p', { class: 'hint', text: 'You can withdraw any optional consent. Other features keep working.' }), consentList),
      h('section', { class: 'panel', 'aria-labelledby': 'pv-s' }, h('h2', { id: 'pv-s', text: 'Who can see health details' }),
        h('p', { class: 'hint', text: 'Choose who can see each person’s food and health details, which details, and for how long. Access ends automatically at the time you set.' }),
        h('div', { class: 'stack' }, sharing)),
      sharedWithMe.length ? h('section', { class: 'panel', 'aria-labelledby': 'pv-w' }, h('h2', { id: 'pv-w', text: 'Shared with you' }),
        h('ul', { class: 'grant-list' }, sharedWithMe.map(g => h('li', {}, h('div', {}, h('b', { text: g.subject_name }), h('span', { class: `tag ${STATUS[grantStatus(g)][0]}`, text: STATUS[grantStatus(g)][1] }),
          h('span', { class: 'hint', style: { display: 'block' }, text: `${g.categories.map(catName).join(', ')} · ${g.expires_at ? `until ${fmt(g.expires_at)}` : 'until they end it'}` })))))) : null,
      h('section', { class: 'panel', 'aria-labelledby': 'pv-l' }, h('h2', { id: 'pv-l', text: 'Access history' }),
        h('p', { class: 'hint', text: 'Every time someone views health details through shared access, it is recorded here.' }),
        logList.length ? h('ul', { class: 'access-log' }, logList) : h('p', { class: 'hint', text: 'No activity yet.' })),
      h('section', { class: 'panel', 'aria-labelledby': 'pv-d' }, h('h2', { id: 'pv-d', text: 'Your data' }),
        h('div', { class: 'stack-s' },
          h('button', { type: 'button', class: 'btn btn-ghost btn-block', id: 'pv-export', onclick: download }, icon('download', 20), h('span', { text: 'Download a copy of my data' })),
          managed.length ? h('button', { type: 'button', class: 'btn btn-ghost btn-block', onclick: () => deleteHealth(managed) }, icon('trash', 20), h('span', { text: 'Delete health details…' })) : null,
          h('button', { type: 'button', class: 'btn-text', text: 'Delete my account and all data on this device', onclick: () => ctx.go('settings') }))),
      h('section', { class: 'panel', 'aria-labelledby': 'pv-r' }, h('h2', { id: 'pv-r', text: 'Make a privacy request' }), requestForm(),
        requests.length ? h('ul', { class: 'grant-list' }, requests.map(r => h('li', {}, h('div', {}, h('b', { text: REQUESTS.find(x => x[0] === r.request_type)?.[1] ?? r.request_type }),
          h('span', { class: 'tag blue', text: r.status === 'RECEIVED' ? 'Received' : r.status }),
          h('span', { class: 'hint', style: { display: 'block' }, text: `Sent ${fmt(r.requested_at)} · answer due by ${fmt(r.due_at)}` }))))) : null),
      h('section', { class: 'stack-s' }, h('h2', { text: 'Notices' }), legalLinks()));
  }

  async function withdraw(type, label) {
    const health = type === 'HEALTH_DATA_PROCESSING';
    const ok = await confirmBox(`Withdraw “${label}”?`, health
      ? ['Health details you manage will be deleted, and shared access to them will end. Meal matching will no longer use them.', 'This can’t be undone. You can add details again later with new consent.']
      : ['The feature will stop until you give consent again.'], health ? 'Withdraw and delete' : 'Withdraw');
    if (!ok) return;
    await recordConsent(user.id, type, false, { method: 'SETTINGS' });
    if (health && hh) {
      const [members, grants] = await Promise.all([tx(['family_member'], 'readonly', t => t.byIndex('family_member', 'household_id', hh)), loadGrants(hh)]);
      const ids = members.filter(m => ['SELF', 'GUARDIAN'].includes(relation({ userId: user.id, membership, member: m, grants, category: null }))).map(m => m.id);
      for (const g of grants.filter(g => ids.includes(g.subject_member_id) && ['ACTIVE', 'SCHEDULED'].includes(grantStatus(g)))) await revokeGrant(g, user.id);
      await deleteHealthDetails(hh, ids, user.id);
    }
    toast('Consent withdrawn.'); draw();
  }

  function giveAccess(member, people) {
    const PERSON_NEW = '__new__';
    const who = h('select', { class: 'input', id: 'ga-who' }, people.map(p => h('option', { value: p.userId, text: p.name })), h('option', { value: PERSON_NEW, text: 'Someone else (by email)' }));
    const name = h('input', { class: 'input', id: 'ga-name', maxlength: 80, autocomplete: 'off' }), email = h('input', { class: 'input', id: 'ga-email', type: 'email', maxlength: 254, autocomplete: 'off' });
    const fName = field({ label: 'Their name', input: name }), fEmail = field({ label: 'Their email', hint: 'They can see the details once they sign in with this email.', input: email });
    const newBox = h('div', { class: 'stack-s' }, fName, fEmail);
    const syncWho = () => { newBox.hidden = who.value !== PERSON_NEW; };
    who.onchange = syncWho; if (!people.length) who.value = PERSON_NEW; syncWho();
    const cats = ACCESS_CATEGORIES.map(c => h('input', { type: 'checkbox', id: `ga-${c.code}`, value: c.code, checked: ['ALLERGIES', 'DIETS'].includes(c.code) }));
    const level = h('select', { class: 'input', id: 'ga-level' }, h('option', { value: 'VIEW', text: 'View only' }), h('option', { value: 'VIEW_EDIT', text: 'View and edit' }));
    const start = h('input', { class: 'input', type: 'datetime-local', id: 'ga-start', value: toLocal(new Date()) });
    const dur = h('select', { class: 'input', id: 'ga-dur' }, ACCESS_DURATIONS.map(d => h('option', { value: d.code, text: d.name, selected: d.code === 'P7D' })));
    const end = h('input', { class: 'input', type: 'datetime-local', id: 'ga-end', value: toLocal(new Date(Date.now() + 7 * 86400000)) });
    const endWrap = field({ label: 'Ends', input: end });
    const noneNote = h('p', { class: 'hint', style: { color: 'var(--danger)' }, text: 'Access will last until you end it. Setting an end date is safer.' });
    const syncDur = () => { endWrap.hidden = dur.value !== 'CUSTOM'; noneNote.hidden = dur.value !== 'NONE'; };
    dur.onchange = syncDur; syncDur();
    const purpose = h('input', { class: 'input', id: 'ga-purpose', maxlength: 120, placeholder: 'e.g. babysitting this weekend' });
    const err = h('p', { class: 'form-error', role: 'alert' });
    const go = h('button', { type: 'button', class: 'btn btn-primary', text: 'Continue' });
    const cancel = h('button', { type: 'button', class: 'btn btn-ghost', text: 'Cancel' });
    const { done } = modal({ title: `Give access to ${member.display_name}’s details`, body: [
      field({ label: 'Who', input: who }), newBox,
      h('fieldset', { class: 'stack-s' }, h('legend', { class: 'label', text: 'Which details' }), ACCESS_CATEGORIES.map((c, i) => h('label', { class: 'check', for: `ga-${c.code}` }, cats[i], h('span', { text: c.name })))),
      field({ label: 'Access', input: level }), field({ label: 'Starts', input: start }), field({ label: 'For how long', input: dur }), endWrap, noneNote,
      field({ label: 'Reason (optional)', input: purpose }), err], actions: [cancel, go] });
    cancel.onclick = () => done(null);
    go.onclick = async () => {
      err.textContent = '';
      const isNew = who.value === PERSON_NEW;
      const grantee = isNew ? { name: name.value.trim(), email: email.value.trim().toLowerCase() } : { userId: who.value, name: people.find(p => p.userId === who.value)?.name };
      if (isNew && (!grantee.name || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(grantee.email))) { err.textContent = 'Enter their name and a valid email.'; return; }
      const categories = cats.filter(c => c.checked).map(c => c.value);
      if (!categories.length) { err.textContent = 'Choose at least one kind of detail.'; return; }
      const startsAt = new Date(start.value || Date.now());
      const d = ACCESS_DURATIONS.find(x => x.code === dur.value);
      const expiresAt = dur.value === 'NONE' ? null : dur.value === 'CUSTOM' ? new Date(end.value) : new Date(startsAt.getTime() + d.days * 86400000);
      if (expiresAt && !(expiresAt > startsAt)) { err.textContent = 'The end must be after the start.'; return; }
      if (expiresAt && expiresAt <= new Date()) { err.textContent = 'The end is already in the past.'; return; }
      done(null);
      const summary = h('div', { class: 'consent-summary' },
        h('p', {}, h('b', { text: grantee.name }), ` will ${level.value === 'VIEW_EDIT' ? 'be able to view and edit' : 'be able to view'} ${member.display_name}’s:`),
        h('ul', {}, categories.map(c => h('li', { text: catName(c) }))),
        h('p', { text: `From ${fmt(startsAt.toISOString())} ${expiresAt ? `until ${fmt(expiresAt.toISOString())}` : 'until you end it'}.` }));
      if (!(await askConsent(user.id, 'HEALTH_DATA_SHARING', { subjectRef: member.id, extra: [summary] }))) { toast('Nothing was shared.'); return; }
      try {
        await createGrant({ householdId: hh, subject: member, grantedBy: user.id, grantee, categories, accessLevel: level.value,
          startsAt: startsAt.toISOString(), expiresAt: expiresAt?.toISOString() ?? null, purpose: purpose.value.trim() });
        toast(`${grantee.name} now has access${expiresAt ? ` until ${fmt(expiresAt.toISOString())}` : ''}.`); draw();
      } catch (e) { toast(e.message || 'Access could not be saved.'); }
    };
    who.focus();
  }

  function confirmBox(title, paras, okLabel) {
    return new Promise(resolve => {
      const ok = h('button', { type: 'button', class: 'btn btn-danger', text: okLabel }), no = h('button', { type: 'button', class: 'btn btn-ghost', text: 'Cancel' });
      const { done } = modal({ title, body: paras.map(p => h('p', { text: p })), actions: [no, ok], onClose: v => resolve(v === true) });
      ok.onclick = () => done(true); no.onclick = () => done(false); no.focus();
    });
  }

  async function deleteHealth(managed) {
    const sel = h('select', { class: 'input', id: 'dh-who' }, h('option', { value: '__all__', text: 'Everyone I manage' }), managed.map(m => h('option', { value: m.id, text: m.display_name })));
    const ok = await new Promise(resolve => {
      const yes = h('button', { type: 'button', class: 'btn btn-danger', text: 'Delete health details' }), no = h('button', { type: 'button', class: 'btn btn-ghost', text: 'Cancel' });
      const { done } = modal({ title: 'Delete health details', body: [h('p', { text: 'Allergies, intolerances, diets, health-related goals, food rules and preferences will be deleted. Shared access to them ends. This can’t be undone.' }),
        field({ label: 'Whose details', input: sel })], actions: [no, yes], onClose: v => resolve(v === true) });
      yes.onclick = () => done(true); no.onclick = () => done(false);
    });
    if (!ok) return;
    const ids = sel.value === '__all__' ? managed.map(m => m.id) : [sel.value];
    for (const g of (await loadGrants(hh)).filter(g => ids.includes(g.subject_member_id) && ['ACTIVE', 'SCHEDULED'].includes(grantStatus(g)))) await revokeGrant(g, user.id);
    const n = await deleteHealthDetails(hh, ids, user.id);
    toast(n ? `Deleted ${n} health detail${n === 1 ? '' : 's'}.` : 'There were no health details to delete.'); draw();
  }

  async function download() {
    const data = await exportData(user, hh);
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const a = h('a', { href: URL.createObjectURL(blob), download: `wamwins-my-data-${new Date().toISOString().slice(0, 10)}.json` });
    document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 5000);
    toast('Your data was downloaded. Keep the file somewhere safe: it contains health details.');
  }

  function requestForm() {
    const type = h('select', { class: 'input', id: 'pr-type' }, REQUESTS.map(([c, t]) => h('option', { value: c, text: t })));
    const details = h('textarea', { class: 'input', id: 'pr-details', rows: 3, maxlength: 1000 });
    const send = h('button', { type: 'button', class: 'btn btn-blue', text: 'Send request', onclick: async () => {
      const r = await fileRequest({ userId: user.id, householdId: hh, type: type.value, details: details.value.trim() });
      toast(`Request received. We will answer by ${fmt(r.due_at)}.`); draw();
    } });
    return h('div', { class: 'stack-s' }, h('p', { class: 'hint', text: 'Most things you can do yourself above. For anything else, send a request: we answer within 45 days.' }),
      field({ label: 'What do you need?', input: type }), field({ label: 'Details (optional)', input: details }), send);
  }

  root.append(h('div', { class: 'frame' },
    h('header', { class: 'topbar' },
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Back to settings', onclick: () => ctx.go('settings') }, icon('back')),
      h('h1', { tabindex: '-1', style: { fontSize: 'var(--step-1)' }, text: 'Privacy & sharing' })),
    h('main', { class: 'content', id: 'main' }, body)));
  await draw();
  return { dispose() {} };
}
