/**
 * Voice command engine (loaded on demand, only when VOICE_COMMANDS is entitled and consented).
 * - One command per tap: continuous = false; the microphone stops after one phrase or 8 seconds.
 * - On-device recognition is requested where the browser supports it (processLocally); otherwise the browser's
 *   own speech service is used (disclosed in the consent text).
 * - No audio is ever recorded or stored by WAMWins; the transcript lives only in memory for this command.
 * - No voiceprints, no speaker identification (BIPA / CUBI / state biometric laws).
 * - Voice never reads anyone's health details aloud, and never changes data without an on-screen confirmation.
 */
const NAV = [
  [/\b(inventory|pantry|food list|my food)\b/, 'inventory', 'Opening inventory'],
  [/\b(privacy|sharing|consent)\b/, 'privacy', 'Opening Privacy & sharing'],
  [/\bsettings?\b/, 'settings', 'Opening settings'],
  [/\b(home|dashboard|start)\b/, 'home', 'Going home'],
];
const NUM = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, twelve: 12, dozen: 12 };

/** Pure: text -> intent. Exported for tests. */
export function parseCommand(raw) {
  const t = String(raw ?? '').toLowerCase().replace(/[.,!?]/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t) return { kind: 'NONE' };
  if (/\b(what can (we|i) (cook|make|eat)|find (a )?meals?|meal ideas?|suggest (a )?meals?|what'?s for (dinner|lunch|breakfast))\b/.test(t)) {
    const slot = (t.match(/\b(breakfast|lunch|dinner|snack|dessert)\b/) ?? [])[1];
    return { kind: 'MATCH', slot: slot ? slot.toUpperCase() : null };
  }
  let m = t.match(/^(?:please )?add (?:(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten|twelve|dozen) )?(?:(?:pounds?|lbs?|ounces?|oz|cups?|cans?|bags?|boxes?|packs?|pieces?|dozen) (?:of )?)?(.+)$/);
  if (m) {
    const name = m[2].replace(/^(of|some) /, '').replace(/ to (the )?(inventory|list|pantry|fridge|refrigerator)$/, '').trim();
    if (name) return { kind: 'ADD', name, quantity: m[1] ? (Number(m[1]) || NUM[m[1]]) : null };
  }
  m = t.match(/\bhow (?:much|many) (.+?) (?:do|does) (?:we|i) have\b/);
  if (m) return { kind: 'STOCK', name: m[1].trim() };
  m = t.match(/\b(?:do (?:we|i) have(?: any)?|how (?:much|many)(?: \w+)? (?:do (?:we|i) have)?|is there(?: any)?|are there(?: any)?) (.+?)(?: left| in the house| at home)?$/);
  if (m) return { kind: 'STOCK', name: m[1].replace(/^(any|some) /, '').trim() };
  for (const [re, route, say] of NAV) if (/\b(open|go to|show|take me to|view)\b/.test(t) && re.test(t)) return { kind: 'NAVIGATE', route, say };
  return { kind: 'UNKNOWN', text: t };
}

/** Listens for one phrase. Resolves { transcript } or rejects with a readable message. */
export function listenOnce({ lang = 'en-US', onPartial } = {}) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) return Promise.reject(new Error('This browser can’t recognize speech.'));
  return new Promise((resolve, reject) => {
    const rec = new SR();
    rec.lang = lang; rec.continuous = false; rec.interimResults = true; rec.maxAlternatives = 1;
    try { if ('processLocally' in rec) rec.processLocally = true; } catch { /* not supported: browser service is used */ }
    let finalText = '', settled = false;
    const stop = setTimeout(() => { try { rec.stop(); } catch {} }, 8000);
    const done = (fn, v) => { if (settled) return; settled = true; clearTimeout(stop); fn(v); };
    rec.onresult = (e) => {
      let interim = '';
      for (const r of e.results) (r.isFinal ? (finalText += r[0].transcript) : (interim += r[0].transcript));
      onPartial?.(finalText || interim);
    };
    rec.onerror = (e) => done(reject, new Error(e.error === 'not-allowed' || e.error === 'service-not-allowed'
      ? 'Microphone access is off. Allow the microphone for this site, then try again.'
      : e.error === 'no-speech' ? 'I didn’t hear anything. Tap the microphone and try again.' : 'Voice recognition stopped. Please try again.'));
    rec.onend = () => done(resolve, { transcript: finalText.trim() });
    rec.start();
  });
}
