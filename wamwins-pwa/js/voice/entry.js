import { h, icon } from '../core/dom.js';
import { tx } from '../data/db.js';
import { canUse } from '../tier/capabilities.js';
import { tierLockedFeatures } from '../components/tier-locked.js';
import { hasConsent, askConsent, recordConsent } from '../privacy/consent.js';

/**
 * Voice commands entry (tiny, always safe to import). VOICE_COMMANDS is a higher-tier capability: in WAMWins Basic
 * it is DISABLED, so only a locked notice is shown and the speech engine (voice/engine.js) is never loaded.
 * When a household is entitled, the engine still loads only after the person consents and taps the microphone.
 */
export const VOICE = 'VOICE_COMMANDS';
export const VOICE_LOCKED = [{ capability: VOICE, title: 'Voice Commands', icon: 'mic',
  text: 'Say “open inventory”, “what can we cook for dinner” or “do we have eggs” instead of tapping. Recordings are never kept.' }];
export const speechSupported = () => !!(window.SpeechRecognition || window.webkitSpeechRecognition);

async function householdOf(user) {
  return (await tx(['household_membership'], 'readonly', t => t.byIndex('household_membership', 'user_id', user.id))).find(m => m.status === 'ACTIVE')?.household_id ?? null;
}
export async function voiceAvailable(user) {
  const hh = await householdOf(user);
  return { hh, entitled: !!hh && await canUse(hh, VOICE), consented: await hasConsent(user.id, VOICE) };
}

/** Settings section: locked notice on Basic; consent + "Use voice commands" when entitled. */
export async function voiceSettings(ctx) {
  const { hh, entitled, consented } = await voiceAvailable(ctx.user);
  if (!entitled) return tierLockedFeatures(hh, VOICE_LOCKED, { heading: 'Voice commands (not in WAMWins Basic)' });
  const status = h('p', { class: 'hint' });
  const body = h('div', { class: 'stack-s' });
  const draw = (on) => {
    status.textContent = on ? 'On. The microphone listens only when you tap it.' : 'Off. Turn on to use your voice for simple commands.';
    body.replaceChildren(status, on
      ? h('div', { class: 'row' }, h('button', { type: 'button', class: 'btn btn-blue', onclick: () => ctx.go('voice') }, icon('mic', 20), h('span', { text: 'Use voice commands' })),
          h('button', { type: 'button', class: 'btn-text', text: 'Turn off', onclick: async () => { await recordConsent(ctx.user.id, VOICE, false, { method: 'SETTINGS' }); draw(false); } }))
      : h('button', { type: 'button', class: 'btn btn-ghost', text: 'Turn on voice commands', onclick: async () => draw(await askConsent(ctx.user.id, VOICE)) }),
      speechSupported() ? null : h('p', { class: 'hint', text: 'This browser can’t recognize speech. Try Chrome, Edge or Safari, or the WAMWins app.' }));
  };
  draw(consented);
  return h('section', { class: 'stack-s', 'aria-labelledby': 'v-h' }, h('h2', { id: 'v-h', text: 'Voice commands' }), body);
}

/** Top-bar microphone: rendered only when entitled AND consented AND the browser can recognize speech. */
export async function voiceButton(ctx) {
  const { entitled, consented } = await voiceAvailable(ctx.user);
  if (!entitled || !consented || !speechSupported()) return null;
  return h('button', { type: 'button', class: 'icon-btn voice-btn', 'aria-label': 'Voice command', onclick: () => ctx.go('voice') }, icon('mic'));
}
