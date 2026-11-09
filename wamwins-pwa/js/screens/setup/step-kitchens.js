import { h, icon, clear, stepper, field } from '../../core/dom.js';
import { REF } from '../../inquiry/reference.js';
import { KITCHEN_KINDS, STORAGE_TYPES, STORAGE_HINT } from '../../inquiry/questions.js';
import { newKitchen, newStorage, sectionNames } from '../../inquiry/draft.js';
import { labelWithInfo, infoButton } from '../../components/info.js';
import { referencePhotos } from '../../components/reference-image.js';
import { tierLockedFeatures, STORAGE_LOCKED } from '../../components/tier-locked.js';

// Module 3 - Kitchens & Storages. Each kitchen is a parent; each storage unit its child; sections nest without a
// fixed depth (Main Kitchen -> Refrigerator -> Upper Shelf -> Bin -> item). Only selected/answered structures are created.
const NODE_KINDS = [{ code: 'ZONE', name: 'Section' }, { code: 'SHELF', name: 'Shelf' }, { code: 'DRAWER', name: 'Drawer' }, { code: 'BIN', name: 'Bin' },
  { code: 'COMPARTMENT', name: 'Division' }, { code: 'CONTAINER', name: 'Container' }];
const kindName = (code) => NODE_KINDS.find(k => k.code === code)?.name ?? 'Section';

export async function create({ draft, user, session, refresh }) {
  let active = draft.kitchens[0]?.key, drawId = 0;
  const body = h('div');
  const disposers = [];
  const hh = session.household_id;

  function sectionTree(storage, nodes, depth = 0) {
    const ul = h('ul', { class: 'sec-tree', 'aria-label': depth ? 'Inside' : 'Your own sections' });
    nodes.forEach((n, i) => {
      const nameIn = h('input', { class: 'input input-sm', value: n.name, maxlength: 60, 'aria-label': `${kindName(n.kind)} name` });
      nameIn.oninput = () => { n.name = nameIn.value; refresh(); };
      const add = n.kind === 'CONTAINER' ? null : h('button', { type: 'button', class: 'btn-text', 'aria-label': `Add inside ${n.name}`, onclick: () => addNode(storage, (n.children ??= [])) },
        icon('plus', 16), h('span', { text: 'Inside' }));
      const del = h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${n.name}`, onclick: () => { nodes.splice(i, 1); draw(); refresh(); } }, icon('trash', 18));
      ul.append(h('li', {}, h('div', { class: 'sec-row' }, h('span', { class: 'tag', text: kindName(n.kind) }), nameIn, add, del),
        n.children?.length ? sectionTree(storage, n.children, depth + 1) : null));
    });
    return ul;
  }
  function addNode(storage, list) {
    const pick = h('select', { class: 'input input-sm', 'aria-label': 'Kind' }, NODE_KINDS.map(k => h('option', { value: k.code, text: k.name })));
    const name = h('input', { class: 'input input-sm', maxlength: 60, placeholder: 'e.g. Upper shelf, Bin A', 'aria-label': 'Name' });
    const ok = h('button', { type: 'button', class: 'btn btn-primary btn-sm', text: 'Add' });
    const row = h('div', { class: 'sec-add' }, pick, name, ok, h('button', { type: 'button', class: 'btn-text', text: 'Cancel', onclick: () => row.remove() }));
    ok.onclick = () => {
      const kind = pick.value;
      list.push({ key: crypto.randomUUID(), kind, name: name.value.trim() || `${kindName(kind)} ${list.length + 1}`, children: [] }); draw(); refresh();
    };
    body.querySelector(`[data-storage="${storage.key}"] .sec-adders`)?.append(row);
    name.focus();
  }

  function storageCard(k, s, idx) {
    const qs = REF.sectionQuestions.filter(q => q.storage_type_code === s.type);
    s.counts ??= {}; s.custom ??= [];
    const nameIn = h('input', { class: 'input', value: s.name, maxlength: 60, id: `st-name-${s.key}` });
    nameIn.oninput = () => { s.name = nameIn.value; refresh(); };
    const follow = qs.map(q => q.input_kind === 'TOGGLE'
      ? h('label', { class: 'check' }, Object.assign(h('input', { type: 'checkbox', checked: !!s.counts[q.code] }), { onchange: (e) => { s.counts[q.code] = e.target.checked ? 1 : 0; refresh(); } }), h('span', { text: q.label }))
      : h('div', { class: 'counter compact' }, h('div', {}, h('div', { class: 'name', text: q.label })),
          stepper({ value: s.counts[q.code] ?? 0, min: 0, max: q.max_value, label: `${q.label} in ${s.name}`, onChange: v => { s.counts[q.code] = v; refresh(); } })));
    const photos = hh ? referencePhotos({ hh, userId: user.id, locationKey: `storage:${s.key}`, locationName: s.name, onChange: refresh }) : null;
    if (photos) disposers.push(photos.dispose);
    const n = sectionNames(s).length;
    return h('article', { class: 'storage-card', 'data-storage': s.key, 'aria-label': s.name },
      h('div', { class: 'member-head' }, h('span', { class: 'avatar sq', 'aria-hidden': 'true' }, icon('box', 18)),
        h('div', { class: 'who' }, h('b', { text: STORAGE_TYPES.find(t => t.code === s.type)?.name ?? s.type }), h('span', { class: 'hint', text: n ? `${n} section${n === 1 ? '' : 's'}` : 'No sections yet' })),
        h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${s.name}`, onclick: () => { k.storage.splice(idx, 1); draft.food = draft.food.filter(f => f.storageKey !== s.key); draw(); refresh(); } }, icon('trash', 20))),
      field({ label: 'Name', input: nameIn }),
      s.legacy && !qs.some(q => s.counts[q.code]) ? h('p', { class: 'hint', text: `Sections already set up: ${sectionNames(s).join(', ') || 'main area'}.` }) : null,
      qs.length ? h('div', { class: 'stack-s' }, h('p', { class: 'label with-info' }, h('span', { text: 'What’s inside?' }),
        infoButton({ label: 'Storage sections', title: 'Storage sections', body: ['Sections are the places inside a storage unit, like shelves, crisper drawers or bins. They help you find food quickly: “Refrigerator → Upper shelf → Bin”.',
          'Only the sections you choose are created. Add your own below, and put sections or containers inside other sections as deep as you need.'] })), ...follow) : null,
      sectionTree(s, s.custom),
      h('div', { class: 'sec-adders' }, h('button', { type: 'button', class: 'btn-text', onclick: () => addNode(s, s.custom) }, icon('plus', 16), h('span', { text: 'Add a section, shelf, bin or container' }))),
      photos?.el);
  }

  function draw() {
    disposers.splice(0).forEach(d => d());
    clear(body);
    const mine = ++drawId;
    const k = draft.kitchens.find(x => x.key === active) ?? draft.kitchens[0];
    active = k?.key;
    body.append(h('section', { class: 'q-block' },
      labelWithInfo('Which kitchens do you have?', { title: 'Kitchens', body: 'Add each separate cooking area. Rename any kitchen to match what you call it at home.' }),
      h('div', { class: 'tabs', role: 'tablist', 'aria-label': 'Kitchens' }, draft.kitchens.map(x => h('button', { type: 'button', role: 'tab', 'aria-selected': String(x.key === active), text: x.name || 'Kitchen',
        onclick: () => { active = x.key; draw(); } }))),
      h('p', { class: 'label', text: 'Add a kitchen' }),
      h('div', { class: 'chips', role: 'group', 'aria-label': 'Add a kitchen' }, KITCHEN_KINDS.map(kk => h('button', { type: 'button', class: 'chip',
        onclick: () => { const nk = newKitchen(kk.code, draft.kitchens); draft.kitchens.push(nk); active = nk.key; draw(); refresh(); } }, icon('plus', 14), h('span', { text: kk.name }))))));
    if (!k) return;
    const kName = h('input', { class: 'input', value: k.name, maxlength: 60, id: `k-name-${k.key}` });
    kName.oninput = () => { k.name = kName.value; const tab = body.querySelector('[role=tab][aria-selected=true]'); if (tab) tab.textContent = k.name || 'Kitchen'; refresh(); };
    const kPhotos = hh ? referencePhotos({ hh, userId: user.id, locationKey: `kitchen:${k.key}`, locationName: k.name, onChange: refresh }) : null;
    if (kPhotos) disposers.push(kPhotos.dispose);
    const addRow = h('div', { class: 'chips', role: 'group', 'aria-label': 'Add a storage area' }, STORAGE_TYPES.map(t => h('button', { type: 'button', class: 'chip', title: STORAGE_HINT[t.code] ?? '',
      onclick: () => { k.storage.push(newStorage(k, t.code)); draw(); refresh(); setTimeout(() => body.querySelector(`[data-storage="${k.storage.at(-1).key}"]`)?.scrollIntoView?.({ block: 'nearest' }), 0); } },
      icon('plus', 14), h('span', { text: t.name }))));
    body.append(h('section', { class: 'q-block' },
      h('div', { class: 'row', style: { justifyContent: 'space-between' } }, h('h2', { text: k.name || 'Kitchen' }),
        draft.kitchens.length > 1 ? h('button', { type: 'button', class: 'btn-text', text: 'Remove this kitchen', onclick: () => {
          draft.kitchens = draft.kitchens.filter(x => x !== k);
          const gone = new Set(k.storage.map(s => s.key));
          draft.food = draft.food.filter(f => !gone.has(f.storageKey)); draft.appliances = draft.appliances.filter(a => a.kitchenKey !== k.key);
          draft.kitchenware = draft.kitchenware.filter(w => w.kitchenKey !== k.key);
          active = draft.kitchens[0].key; draw(); refresh(); } }) : null),
      field({ label: 'Kitchen name', hint: `${KITCHEN_KINDS.find(x => x.code === k.kind)?.name ?? 'Kitchen'}. Rename it if you like.`, input: kName }),
      kPhotos?.el),
      h('section', { class: 'q-block' }, h('h2', { text: 'What storage areas do you have?' }), h('p', { class: 'hint', text: 'Tap to add each one. Add two if you have two.' }), addRow,
        h('div', { class: 'stack' }, k.storage.map((s, i) => storageCard(k, s, i)))));
    tierLockedFeatures(hh, STORAGE_LOCKED).then(el => { if (el && mine === drawId) body.append(el); });
  }
  draw();
  return {
    el: body,
    validate: () => {
      if (!draft.kitchens.length) return 'Add at least one kitchen.';
      if (draft.kitchens.some(k => !k.name?.trim())) return 'Every kitchen needs a name.';
      if (draft.kitchens.some(k => k.storage.some(s => !s.name?.trim()))) return 'Every storage area needs a name.';
      return null;
    },
    dispose: () => disposers.forEach(d => d()),
  };
}
