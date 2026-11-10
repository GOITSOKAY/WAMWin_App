import { h, toast } from '../../core/dom.js';
import { REF } from '../../inquiry/reference.js';
import { COOKING_ROLE, MEASURES, ALLERGENS, DIETS, KITCHENWARE_CATEGORIES } from '../../inquiry/questions.js';
import { deriveTree, sectionNames } from '../../inquiry/draft.js';
import { provision } from '../../inquiry/provisioning.js';

// Module 7 - Review My Household Entries. Six sections, each with a Change link; "Save Entries" provisions (idempotently).
export function create({ draft, user, session, go }) {
  const t = deriveTree(draft);
  const name = (list, code) => list.find(x => x.code === code)?.name ?? '';
  const block = (n, title, step, ...body) => h('section', { class: 'q-block review-block', 'aria-labelledby': `rv-${step}` },
    h('div', { class: 'review-head' }, h('h2', { id: `rv-${step}`, text: `${n}. ${title}` }),
      h('button', { type: 'button', class: 'btn-text', 'aria-label': `Change ${title}`, text: 'Change', onclick: () => go(`setup/${step}`) })), ...body);
  const p = (text) => h('p', { text });
  const a = draft.about, hh = draft.household;
  const people = draft.health.needed === 'YES' && draft.health.consent ? draft.health.people : [];
  const el = h('div', {},
    block(1, 'About You', 'about',
      p(`${a.displayName}. ${name(COOKING_ROLE, a.cookingRole)}${a.householdRole ? ` (${REF.householdRoles.find(r => r.code === a.householdRole)?.name})` : ''}. ${name(MEASURES, a.measures)} units.`),
      p(`${hh.name}${hh.nickname ? ` (“${hh.nickname}”)` : ''}: ${hh.size} ${hh.size === 1 ? 'person' : 'people'}, ${hh.eaters} eating from this kitchen.`)),
    block(2, 'Health Profiles', 'health',
      draft.health.needed !== 'YES' ? p('No special dietary management.')
        : !draft.health.consent ? p('Health details are not stored (permission not given).')
        : h('div', { class: 'stack-s' }, people.map(x => h('div', { class: 'row' }, h('b', { style: { fontWeight: 500 }, text: x.name }),
            ...x.allergies.map(c => h('span', { class: 'tag danger', text: `No ${name(ALLERGENS, c).toLowerCase()}` })),
            ...x.diets.map(c => h('span', { class: 'tag blue', text: name(DIETS, c) })),
            x.avoid?.length || x.prioritize?.length ? h('span', { class: 'hint', text: `${x.avoid?.length || 0} to avoid, ${x.prioritize?.length || 0} to prioritize` }) : null)))),
    block(3, 'Kitchens & Storages', 'kitchens', ...t.kitchens.map(k => h('div', {}, h('b', { style: { fontWeight: 500 }, text: k.name }),
      h('ul', { class: 'review-list' }, k.storage.map(s => h('li', { text: `${s.name}${sectionNames(s).length ? ` — ${sectionNames(s).length} sections` : ''}` })))))),
    block(4, 'Kitchen Appliances', 'appliances', p(draft.appliances.length ? draft.appliances.map(x => x.name).join(', ') : 'None added. You can add appliances later.')),
    block(5, 'Utensils & Kitchenware', 'kitchenware', draft.kitchenware.length
      ? h('ul', { class: 'review-list' }, KITCHENWARE_CATEGORIES.filter(c => draft.kitchenware.some(w => w.category === c.code)).map(c => h('li', { text: `${c.name}: ${draft.kitchenware.filter(w => w.category === c.code).map(w => `${w.name} ×${w.quantity}`).join(', ')}` })))
      : p('None added. You can add kitchenware later.')),
    block(6, 'Food Inventories', 'food', p(draft.food.length ? `${draft.food.length} food item${draft.food.length === 1 ? '' : 's'}: ${draft.food.slice(0, 6).map(f => f.name).join(', ')}${draft.food.length > 6 ? '…' : ''}` : 'None yet. You can add food later.')),
    h('div', { class: 'review-summary' }, h('h2', { text: `WAMWins will set up ${t.moduleCount} parts for your household` }),
      h('p', { text: `${t.kitchens.length} kitchen${t.kitchens.length === 1 ? '' : 's'}, ${t.storageCount} storage area${t.storageCount === 1 ? '' : 's'}, ${t.applianceCount} appliance${t.applianceCount === 1 ? '' : 's'}, ${t.healthProfiles} health profile${t.healthProfiles === 1 ? '' : 's'}. Nothing you didn’t enter is created.` }),
      h('div', { class: 'module-pills' }, t.modules.filter(m => m.on).map(m => h('span', { class: 'on', text: m.name })))));
  return {
    el,
    nextLabel: () => 'Save Entries',
    submit: async () => {
      await provision(user, session, draft);
      toast('Your entries are saved.');
      go('home', true);
    },
  };
}
