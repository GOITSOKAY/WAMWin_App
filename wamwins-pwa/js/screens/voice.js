import { h, icon, clear, toast } from '../core/dom.js';
import { tx } from '../data/db.js';
import { REF } from '../inquiry/reference.js';
import { voiceAvailable, speechSupported, VOICE, VOICE_LOCKED } from '../voice/entry.js';
import { askConsent, modal } from '../privacy/consent.js';
import { tierLockedFeatures } from '../components/tier-locked.js';

// Voice commands screen. Gate order: capability (tier) -> consent -> browser support -> tap to listen.
// The engine module is imported only after all three pass (nothing loads in WAMWins Basic).
const EXAMPLES = ['Open inventory', 'What can we cook for dinner?', 'Do we have eggs?', 'Add 2 pounds of chicken breast', 'Open Privacy & sharing'];

export async function mount(root, ctx) {
  const body = h('div', { class: 'stack-l' });
  root.append(h('div', { class: 'frame' },
    h('header', { class: 'topbar' },
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Back to home', onclick: () => ctx.go('home') }, icon('back')),
      h('h1', { tabindex: '-1', style: { fontSize: 'var(--step-1)' }, text: 'Voice commands' })),
    h('main', { class: 'content', id: 'main' }, body)));
  let { hh, entitled, consented } = await voiceAvailable(ctx.user);
  if (!entitled) {
    body.append(h('p', { text: 'Voice commands are part of a higher WAMWins tier. Everything they do can also be done by tapping in WAMWins Basic.' }),
      await tierLockedFeatures(hh, VOICE_LOCKED, { heading: 'Voice commands (not in WAMWins Basic)' }));
    return { dispose() {} };
  }
  if (!consented) {
    consented = await askConsent(ctx.user.id, VOICE);
    if (!consented) { body.append(h('p', { text: 'Voice commands stay off. You can turn them on any time in Settings.' })); return { dispose() {} }; }
  }
  if (!speechSupported()) { body.append(h('p', { text: 'This browser can’t recognize speech. Try Chrome, Edge or Safari, or the WAMWins app.' })); return { dispose() {} }; }

  let engine = null, busy = false, disposed = false;
  const heard = h('p', { class: 'voice-heard', 'aria-live': 'polite' });
  const answer = h('div', { class: 'voice-answer', 'aria-live': 'polite' });
  const mic = h('button', { type: 'button', class: 'voice-mic', 'aria-label': 'Tap and say one command', 'aria-pressed': 'false' }, icon('mic', 40));
  const status = h('p', { class: 'hint', text: 'Tap the microphone and say one command. It stops listening by itself.' });

  async function stockAnswer(name) {
    const q = name.toLowerCase().replace(/s$/, '');
    const [items, mine] = await tx(['inventory_item', 'item_master'], 'readonly', async t => [await t.byIndex('inventory_item', 'household_id', hh), await t.byIndex('item_master', 'household_id', hh)]);
    const label = (it) => REF.items.find(i => i.id === it.item_master_id)?.name ?? mine.find(m => m.id === it.item_master_id)?.canonical_name ?? it.label ?? '';
    const hits = items.filter(i => !i.deleted_at && i.quantity > 0 && label(i).toLowerCase().includes(q));
    const sym = (c) => REF.units.find(u => u.code === c)?.symbol ?? '';
    return hits.length ? `Yes: ${hits.slice(0, 4).map(i => `${label(i)}, ${+i.quantity.toFixed(2)} ${sym(i.unit_code)}`.trim()).join('; ')}.` : `I couldn’t find ${name} in your inventory.`;
  }
  function confirmAdd(intent) {
    return new Promise(resolve => {
      const yes = h('button', { type: 'button', class: 'btn btn-primary', text: 'Open Add food' }), no = h('button', { type: 'button', class: 'btn btn-ghost', text: 'Cancel' });
      const { done } = modal({ title: 'Add food?', body: [h('p', { text: `You said: add ${intent.quantity ? `${intent.quantity} ` : ''}${intent.name}.` }),
        h('p', { class: 'hint', text: 'Nothing is saved yet. WAMWins opens your inventory so you can check the details and save.' })], actions: [no, yes], onClose: v => resolve(v === true) });
      yes.onclick = () => done(true); no.onclick = () => done(false); yes.focus();
    });
  }
  async function run(intent) {
    switch (intent.kind) {
      case 'NAVIGATE': answer.textContent = `${intent.say}…`; return setTimeout(() => !disposed && ctx.go(intent.route), 400);
      case 'MATCH': answer.textContent = 'Opening meal ideas…'; return setTimeout(() => !disposed && ctx.go('match'), 400);
      case 'STOCK': answer.textContent = await stockAnswer(intent.name); return;
      case 'ADD': if (await confirmAdd(intent)) ctx.go(`inventory/q:${encodeURIComponent(intent.name)}`); else answer.textContent = 'Nothing was added.'; return;
      case 'NONE': answer.textContent = 'I didn’t catch that. Try again.'; return;
      default: answer.textContent = 'Sorry, I can’t do that yet. Try one of the examples below.';
    }
  }
  mic.onclick = async () => {
    if (busy) return;
    busy = true; mic.classList.add('listening'); mic.setAttribute('aria-pressed', 'true'); status.textContent = 'Listening…'; heard.textContent = ''; answer.textContent = '';
    try {
      engine ??= await import('../voice/engine.js');
      const { transcript } = await engine.listenOnce({ lang: ctx.user.locale === 'es' ? 'es-US' : 'en-US', onPartial: t => { heard.textContent = t; } });
      heard.textContent = transcript ? `“${transcript}”` : '';
      await run(engine.parseCommand(transcript));          // the transcript is not stored anywhere
    } catch (e) { answer.textContent = e.message; }
    finally { busy = false; mic.classList.remove('listening'); mic.setAttribute('aria-pressed', 'false'); status.textContent = 'Tap the microphone and say one command.'; }
  };
  body.append(h('section', { class: 'voice-panel' }, mic, status, heard, answer),
    h('section', { class: 'stack-s' }, h('h2', { text: 'Things you can say' }), h('ul', { class: 'voice-examples' }, EXAMPLES.map(x => h('li', { text: `“${x}”` })))),
    h('p', { class: 'hint' }, icon('shield', 16), h('span', { text: ' WAMWins keeps no recordings and no voiceprints. Voice never reads health details aloud. Turn voice off in Settings.' })));
  mic.focus();
  return { dispose() { disposed = true; } };
}
