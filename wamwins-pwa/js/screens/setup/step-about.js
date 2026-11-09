import { h, field, choices, stepper } from '../../core/dom.js';
import { COOKING_ROLE, SKILL, MEASURES, HOUSEHOLD_ROLES, DEFAULT_MEASURES } from '../../inquiry/questions.js';
import { ensureHousehold } from '../../inquiry/provisioning.js';
import { labelWithInfo } from '../../components/info.js';

// Module 1 - About You (merges the former "About you" and "Your household" steps). Kitchen setup is Module 3.
export function create({ draft, user, session }) {
  const a = draft.about, hh = draft.household;
  a.displayName ??= user.display_name; a.cookingRole ??= 'ME'; a.skill ??= 'COMFORTABLE'; a.measures ??= DEFAULT_MEASURES;
  hh.size ??= 2; hh.eaters ??= hh.size;
  if (!hh.name) { const first = (a.displayName || '').trim().split(/\s+/)[0]; hh.name = first ? `${first}’s household` : 'My household'; }

  const name = h('input', { class: 'input', type: 'text', autocomplete: 'given-name', value: a.displayName, maxlength: 80 });
  name.oninput = () => { a.displayName = name.value; };
  const fName = field({ label: 'What should we call you?', hint: 'Your first name or the name you prefer.', input: name });

  const roleBox = h('div');
  const drawRole = () => {
    roleBox.replaceChildren(a.cookingRole === 'ME' ? h('section', { class: 'q-block' },
      h('h2', { text: 'What is your role in the household?' }), h('p', { class: 'hint', text: 'Optional. It helps WAMWins understand who plans and cooks.' }),
      choices(HOUSEHOLD_ROLES.map(r => ({ code: r.code, name: r.name })), a.householdRole, v => { a.householdRole = v; })) : null);
  };
  drawRole();

  const hhName = h('input', { class: 'input', type: 'text', value: hh.name, maxlength: 80 });
  hhName.oninput = () => { hh.name = hhName.value; };
  const fHh = field({ label: 'Household name', hint: 'Shown to people you invite later.', input: hhName });
  const nick = h('input', { class: 'input', type: 'text', value: hh.nickname ?? '', maxlength: 40, placeholder: 'e.g. The Garcias' });
  nick.oninput = () => { hh.nickname = nick.value; };
  const count = (label, hint, key, min) => h('div', { class: 'counter' }, h('div', {}, h('div', { class: 'name', text: label }), h('div', { class: 'hint', text: hint })),
    stepper({ value: hh[key], min, max: 30, label, onChange: v => { hh[key] = v; } }));

  const el = h('div', {},
    h('section', { class: 'q-block' }, fName),
    h('section', { class: 'q-block' }, h('h2', { text: 'Who does most of the cooking?' }),
      choices(COOKING_ROLE, a.cookingRole, v => { a.cookingRole = v; drawRole(); }),
      h('p', { class: 'hint', text: 'If you share the cooking, you can name the other cooks later in your family profiles.' })),
    roleBox,
    h('section', { class: 'q-block' }, h('h2', { text: 'How confident are you in the kitchen?' }), choices(SKILL, a.skill, v => { a.skill = v; })),
    h('section', { class: 'q-block' }, labelWithInfo('Which measurements do you use?', { title: 'Measurements', body: 'U.S. customary units (ounces, pounds, cups, tablespoons, teaspoons) are the default. Choose metric if you prefer grams and milliliters; you can change this later.' }),
      choices(MEASURES, a.measures, v => { a.measures = v; })),
    h('section', { class: 'q-block' }, h('h2', { text: 'Your household' }), fHh, field({ label: 'Household nickname (optional)', input: nick }),
      count('How many people belong to the household?', 'Including you', 'size', 1),
      count('How many people regularly eat from this kitchen?', 'Including guests who eat with you often', 'eaters', 0)));
  return {
    el,
    validate: () => {
      const okName = !!a.displayName?.trim(), okHh = !!hh.name?.trim();
      fName.setError(okName ? '' : 'Enter your name.'); fHh.setError(okHh ? '' : 'Enter a household name.');
      if (!okName) return 'Enter your name to continue.';
      if (!okHh) return 'Enter a household name to continue.';
      if (!(hh.size >= 1)) return 'At least one person belongs to the household.';
      if (a.cookingRole !== 'ME') delete a.householdRole;
      a.displayName = a.displayName.trim(); hh.name = hh.name.trim();
      return null;
    },
    // the household (+ owner membership + WAMWins Basic entitlements) exists from Module 1 on, so photos and resume work
    afterSave: () => ensureHousehold(user, session, hh),
  };
}
