import { h, icon, wordmark, brandLogo } from '../core/dom.js';
import { loadHousehold } from '../inquiry/provisioning.js';
import { tx } from '../data/db.js';
import { REF } from '../inquiry/reference.js';
import { canUse } from '../tier/capabilities.js';

const greet = () => { const hr = new Date().getHours(); return hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening'; };
const MODULE_NAMES = { HOUSEHOLD: 'Household', KITCHEN: 'Kitchens', EQUIPMENT: 'Appliances & tools', FAMILY: 'Family', HEALTH: 'Health & diet',
  INVENTORY: 'Inventory', SHOPPING: 'Shopping list', MATCHING: 'Meal matching', MEALS: 'Meal history' };

export async function mount(root, ctx) {
  const m = (await tx(['household_membership'], 'readonly', t => t.byIndex('household_membership', 'user_id', ctx.user.id))).find(x => x.status === 'ACTIVE');
  if (!m) { ctx.go('setup/about', true); return { dispose() {} }; }
  const d = await loadHousehold(m.household_id);                      // one household, read once, released on leave
  const itemName = (it) => REF.items.find(i => i.id === it.item_master_id)?.name ?? it.label ?? 'Food item';   // built-in list, else the household's own food
  const allergenName = (c) => REF.allergens.find(a => a.code === c)?.name ?? c;
  const dietName = (c) => REF.dietaryPatterns.find(a => a.code === c)?.name ?? c;

  const explorer = h('div', { class: 'explorer' }, d.kitchens.map((k, i) => {
    const units = d.storage.filter(s => s.kitchen_id === k.id).sort((a, b) => a.sort_order - b.sort_order);
    return h('details', { open: i === 0 },
      h('summary', {}, icon('home', 20), h('span', { text: k.name }), h('span', { class: 'hint', text: `${units.length} storage` }), h('span', { class: 'chev' }, icon('chev', 18))),
      h('div', { class: 'lvl2' }, units.length ? units.map(s => {
        const items = d.items.filter(it => it.storage_instance_id === s.id);
        return h('details', {},
          h('summary', {}, icon('box', 18), h('span', { text: s.name }), h('span', { class: 'hint', text: items.length ? `${items.length} item${items.length > 1 ? 's' : ''}` : 'empty' }), h('span', { class: 'chev' }, icon('chev', 16))),
          d.sections.filter(x => x.storage_instance_id === s.id).sort((a, b) => a.ordinal - b.ordinal).map(x => h('div', { class: 'sec' }, h('span', { text: x.name }))),
          items.map(it => h('div', { class: 'sec' }, h('span', { text: itemName(it) }), h('span', { text: `${it.quantity} ${(REF.units.find(u => u.code === it.unit_code)?.symbol) || ''}` }))));
      }) : h('p', { class: 'hint', text: 'No storage in this kitchen.' })));
  }));
  d.members.sort((a, b) => (b.linked_user_id === ctx.user.id) - (a.linked_user_id === ctx.user.id) || a.created_at.localeCompare(b.created_at));
  const family = h('div', { class: 'stack-s' }, d.members.map(mem => h('div', { class: 'member-head' },
    h('span', { class: 'avatar', 'aria-hidden': 'true', text: mem.display_name.split(/\s+/).map(p => p[0]).slice(0, 2).join('').toUpperCase() }),
    h('div', { class: 'who' }, h('b', { text: mem.display_name }),
      h('div', { class: 'chips', style: { gap: '4px', marginTop: '4px' } },
        ...d.allergies.filter(a => a.member_id === mem.id).map(a => h('span', { class: 'tag danger', text: `No ${allergenName(a.allergen_code).toLowerCase()}` })),
        ...d.diets.filter(a => a.member_id === mem.id).map(a => h('span', { class: 'tag blue', text: dietName(a.dietary_pattern_code) })))))));
  const ORDER = Object.keys(MODULE_NAMES);
  const canMatch = d.members.length > 0 && await canUse(m.household_id, 'MEAL_MATCHING');      // capability, never "which tier?"
  const inventoryBtn = (await canUse(m.household_id, 'MANUAL_INVENTORY'))
    ? h('button', { type: 'button', class: 'btn btn-ghost btn-block inventory-btn', onclick: () => ctx.go('inventory') }, icon('box', 20), h('span', { text: 'Open inventory' })) : null;
  const matchCta = canMatch ? h('section', { class: 'match-cta' },
    h('span', { class: 'ico' }, icon('chef')),
    h('p', { text: 'Find meals that are safe for everyone and use what you have.' }),
    h('button', { type: 'button', class: 'btn btn-primary', text: 'What can we cook?', onclick: () => ctx.go('match') })) : null;
  const mods = d.modules.filter(x => !x.resource_id && ORDER.includes(x.module_code)).sort((a, b) => ORDER.indexOf(a.module_code) - ORDER.indexOf(b.module_code));

  root.append(h('div', { class: 'frame' },
    h('header', { class: 'topbar' },
      h('span', { class: 'brand' }, brandLogo('bar'), h('span', { class: 'brand-text', 'aria-hidden': 'true' }, wordmark())),
      h('span', { class: 'spacer' }),
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Settings', onclick: () => ctx.go('settings') }, icon('settings'))),
    h('main', { class: 'content wide', id: 'main' },
      h('div', { class: 'hello' }, h('h1', { tabindex: '-1', text: `${greet()}, ${ctx.user.display_name.split(/\s+/)[0]}` }),
        h('p', { text: `${d.household.name} is set up. Here’s what WAMWins knows about your home.` })),
      h('div', { class: 'stats' },
        h('div', {}, h('b', { text: d.kitchens.length }), h('span', { text: d.kitchens.length === 1 ? 'Kitchen' : 'Kitchens' })),
        h('div', {}, h('b', { text: d.storage.length }), h('span', { text: 'Storage units' })),
        h('div', {}, h('b', { text: d.members.length }), h('span', { text: 'Family members' })),
        h('div', {}, h('b', { text: d.items.length }), h('span', { text: 'Foods on hand' }))),
      inventoryBtn,
      matchCta,
      h('div', { class: 'home-grid' },
        h('section', { class: 'panel', 'aria-labelledby': 'k-h' }, h('h2', { id: 'k-h', text: 'Your kitchens' }), explorer),
        h('div', { class: 'stack' },
          h('section', { class: 'panel', 'aria-labelledby': 'f-h' }, h('h2', { id: 'f-h', text: 'Family' }), family),
          h('section', { class: 'panel brand on-brand', 'aria-labelledby': 'm-h' }, h('h2', { id: 'm-h', text: 'Set up for your household' }),
            h('p', { style: { color: '#DCE6FB', fontSize: 'var(--step--1)' }, text: `${d.equipment.length} ${d.equipment.length === 1 ? 'appliance or tool' : 'appliances and tools'} recorded. These parts were created from your answers:` }),
            h('div', { class: 'module-pills' }, mods.map(x => h('span', { class: 'on', text: MODULE_NAMES[x.module_code] || x.display_name })))),
          h('button', { type: 'button', class: 'btn btn-ghost btn-block', text: 'Update my answers', onclick: () => ctx.go('setup/about') }))))));
  return { dispose() {} };
}
