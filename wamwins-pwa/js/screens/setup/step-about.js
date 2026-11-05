import { h, field, choices } from '../../core/dom.js';
import { COOKING_ROLE, SKILL, MEASURES } from '../../inquiry/questions.js';
import { Q } from '../../inquiry/draft.js';

export function create({ draft, user }) {
  const a = draft.about;
  a.displayName ??= user.display_name; a.cookingRole ??= 'ME'; a.skill ??= 'COMFORTABLE'; a.measures ??= 'METRIC';
  const name = h('input', { class: 'input', type: 'text', autocomplete: 'given-name', value: a.displayName, maxlength: 80 });
  name.oninput = () => { a.displayName = name.value; };
  const fName = field({ label: 'What should we call you?', input: name });
  const el = h('div', {},
    h('section', { class: 'q-block' }, fName),
    h('section', { class: 'q-block' }, h('h2', { text: 'Who does most of the cooking?' }), choices(COOKING_ROLE, a.cookingRole, v => { a.cookingRole = v; })),
    h('section', { class: 'q-block' }, h('h2', { text: 'How confident are you in the kitchen?' }), choices(SKILL, a.skill, v => { a.skill = v; })),
    h('section', { class: 'q-block' }, h('h2', { text: 'Which measurements do you use?' }), choices(MEASURES, a.measures, v => { a.measures = v; })));
  return {
    el,
    validate: () => { const ok = !!a.displayName?.trim(); fName.setError(ok ? '' : 'Enter your name.'); return ok ? null : 'Enter your name to continue.'; },
    answers: () => [[Q.ABOUT, '', { ...a, displayName: a.displayName.trim() }]],
  };
}
