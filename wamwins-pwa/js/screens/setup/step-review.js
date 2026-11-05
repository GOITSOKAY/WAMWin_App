import { h, toast, icon } from '../../core/dom.js';
import { deriveTree } from '../../inquiry/draft.js';
import { provision } from '../../inquiry/provisioning.js';
import { COOKING_ROLE, SKILL, ALLERGENS, DIETS } from '../../inquiry/questions.js';

const ROLE_TEXT = { ME: 'You do most of the cooking.', SHARED: 'Cooking is shared.', OTHER: 'Someone else does most of the cooking.' };
const SKILL_TEXT = { BEGINNER: 'Just starting out in the kitchen.', COMFORTABLE: 'Comfortable with everyday cooking.', CONFIDENT: 'Confident cook.' };
export function create({ draft, user, session, go }) {
  const t = deriveTree(draft);
  const name = (arr, c) => arr.find(x => x.code === c)?.name ?? '';
  const block = (title, step, ...body) => h('section', { class: 'q-block' },
    h('div', { class: 'row', style: { justifyContent: 'space-between' } }, h('h2', { text: title }),
      h('button', { type: 'button', class: 'btn-text', 'aria-label': `Change ${title.toLowerCase()}`, text: 'Change', onclick: () => go(`setup/${step}`) })), ...body);
  const el = h('div', {},
    block('You', 'about', h('p', { text: `${draft.about.displayName}. ${ROLE_TEXT[draft.about.cookingRole] || ''} ${SKILL_TEXT[draft.about.skill] || ''}`.trim() })),
    block('Household', 'household', h('p', { text: `${draft.household.name}, ${draft.household.size} ${draft.household.size === 1 ? 'person' : 'people'}, ${t.kitchens.length} kitchen${t.kitchens.length > 1 ? 's' : ''}.` })),
    block('Kitchens & equipment', 'kitchens', ...t.kitchens.map(k => h('p', {}, h('b', { style: { fontWeight: 500 }, text: `${k.name}: ` }),
      k.storage.length ? k.storage.map(s => s.name).join(', ') : 'no storage', k.equipment ? `; ${k.equipment} ${k.equipment === 1 ? 'appliance or tool' : 'appliances and tools'}` : ''))),
    block('Family & health', 'family', h('div', { class: 'stack-s' }, draft.family.map(m => h('div', { class: 'row' }, h('span', { text: m.name }),
      ...(m.allergies || []).map(c => h('span', { class: 'tag danger', text: `No ${name(ALLERGENS, c).toLowerCase()}` })),
      ...(m.diets || []).map(c => h('span', { class: 'tag blue', text: name(DIETS, c) })))))),
    block('Food on hand', 'food', h('p', { text: draft.food.length ? `${draft.food.length} food item${draft.food.length > 1 ? 's' : ''} ready to add.` : 'None yet. You can add food after setup.' })),
    h('section', { class: 'q-block' }, h('div', { class: 'panel brand on-brand' }, h('h2', { text: `WAMWins will set up ${t.moduleCount} parts for your household` }),
      h('p', { style: { color: '#DCE6FB' }, text: `${t.kitchens.length} kitchen${t.kitchens.length > 1 ? 's' : ''}, ${t.storageCount} storage unit${t.storageCount === 1 ? '' : 's'} with their shelves, ${t.members} family member${t.members === 1 ? '' : 's'}. Nothing you didn’t mention is created.` }),
      h('div', { class: 'module-pills' }, t.modules.filter(m => m.on).map(m => h('span', { class: 'on', text: m.name }))))));
  return {
    el,
    submit: async () => {
      const r = await provision(user, session, draft);
      toast(r.storage || r.kitchens ? 'Your household is ready.' : 'Your answers are updated.');
      go('home');
    },
  };
}
