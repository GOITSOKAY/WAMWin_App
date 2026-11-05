import { tx, get } from '../data/db.js';

/**
 * Authentication port. LocalAuthAdapter keeps accounts on this device (offline-first) with
 * PBKDF2-SHA-256 password hashing (310,000 iterations, per-user salt), constant-time comparison,
 * progressive lockout and hashed session tokens. When the WAM Digital identity API is connected,
 * a remote adapter implements the same four methods; screens do not change.
 */
const ITERATIONS = 310000;
const SESSION_KEY = 'wamwins.session';
const COMMON = ['password', '1234567890', 'qwertyuiop', 'iloveyou', 'password123', 'wamwins', 'letmein', 'welcome123', 'abc1234567', '0987654321'];
const enc = new TextEncoder();
const hex = (buf) => [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const unb64 = (s) => Uint8Array.from(atob(s), c => c.charCodeAt(0));

export class AuthError extends Error { constructor(code, message) { super(message); this.code = code; } }

function requireCrypto() {
  if (!window.isSecureContext || !crypto?.subtle)
    throw new AuthError('INSECURE', 'Open WAMWins over https (or localhost) so your password can be protected.');
}
async function pbkdf2(password, salt, iterations = ITERATIONS) {
  const key = await crypto.subtle.importKey('raw', enc.encode(password.normalize('NFKC')), 'PBKDF2', false, ['deriveBits']);
  return crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, 256);
}
function equal(a, b) { if (a.length !== b.length) return false; let d = 0; for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i]; return d === 0; }
const sha256 = async (s) => hex(await crypto.subtle.digest('SHA-256', enc.encode(s)));
export const normalizeEmail = (e) => String(e || '').trim().toLowerCase();
export const validEmail = (e) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(normalizeEmail(e));

/** 0-4 strength with plain-language feedback. Minimum accepted: 10 characters and score >= 2. */
export function passwordStrength(pw, context = []) {
  if (!pw) return { score: 0, message: 'Use at least 10 characters.' };
  const lower = pw.toLowerCase();
  if (pw.length < 10) return { score: 1, message: `Add ${10 - pw.length} more character${10 - pw.length === 1 ? '' : 's'}.` };
  if (COMMON.some(c => lower.includes(c)) || context.filter(Boolean).some(c => c.length > 2 && lower.includes(c.toLowerCase())))
    return { score: 1, message: 'Avoid common words, your name or your email.' };
  const kinds = [/[a-z]/, /[A-Z]/, /\d/, /[^A-Za-z0-9]/].filter(r => r.test(pw)).length;
  const score = Math.min(4, (pw.length >= 14 ? 2 : 1) + (kinds >= 3 ? 2 : kinds === 2 ? 1 : 0));
  return { score, message: score >= 3 ? 'Strong password.' : score === 2 ? 'Good. A longer phrase is even stronger.' : 'Mix letters with numbers or symbols.' };
}

export const LocalAuthAdapter = {
  async register({ name, email, password, consents }) {
    requireCrypto();
    const mail = normalizeEmail(email);
    if (!name?.trim()) throw new AuthError('NAME', 'Enter your name.');
    if (!validEmail(mail)) throw new AuthError('EMAIL', 'Enter a valid email address, like name@example.com.');
    const strength = passwordStrength(password, [name, mail.split('@')[0]]);
    if (strength.score < 2) throw new AuthError('PASSWORD', strength.message);
    if (!consents?.TERMS || !consents?.PRIVACY_POLICY) throw new AuthError('CONSENT', 'Please accept the Terms and Privacy Policy to create an account.');
    if (await tx(['user_account'], 'readonly', t => t.oneByIndex('user_account', 'email', mail)))
      throw new AuthError('EXISTS', 'An account with this email already exists on this device. Log in instead.');
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const hash = await pbkdf2(password, salt);
    const userId = crypto.randomUUID(), now = new Date().toISOString();
    await tx(['user_account', 'auth_identity', 'consent_record'], 'readwrite', async t => {
      await t.add('user_account', { id: userId, email: mail, display_name: name.trim(), locale: navigator.language || 'en',
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC', status: 'ACTIVE', created_at: now, updated_at: now, row_version: 1 });
      await t.add('auth_identity', { id: crypto.randomUUID(), user_id: userId, provider: 'PASSWORD', provider_subject: mail,
        secret_hash: b64(hash), salt: b64(salt), kdf: 'PBKDF2-SHA256', iterations: ITERATIONS, failed_attempts: 0, locked_until: null, created_at: now });
      for (const [type, granted] of Object.entries(consents))
        await t.add('consent_record', { id: crypto.randomUUID(), user_id: userId, consent_type: type, document_version: '1', granted: !!granted, recorded_at: now });
    });
    await startSessionSafe(userId, true);
    return userId;
  },
  async login({ email, password, remember }) {
    requireCrypto();
    const mail = normalizeEmail(email);
    const generic = new AuthError('CREDENTIALS', 'Email or password is incorrect.');
    const ident = await tx(['auth_identity'], 'readonly', t => t.oneByIndex('auth_identity', 'provider_subject', mail));
    if (!ident) { await pbkdf2(password || 'x', new Uint8Array(16)); throw generic; }          // same timing as a real check
    if (ident.locked_until && Date.parse(ident.locked_until) > Date.now()) {
      const s = Math.ceil((Date.parse(ident.locked_until) - Date.now()) / 1000);
      throw new AuthError('LOCKED', `Too many attempts. Try again in ${s} second${s === 1 ? '' : 's'}.`);
    }
    const hash = new Uint8Array(await pbkdf2(password || '', unb64(ident.salt), ident.iterations));
    if (!equal(hash, unb64(ident.secret_hash))) {
      const fails = (ident.failed_attempts || 0) + 1;
      const lock = fails >= 5 ? new Date(Date.now() + 30000 * 2 ** Math.min(fails - 5, 6)).toISOString() : null;   // 30 s, doubling
      await tx(['auth_identity'], 'readwrite', t => t.put('auth_identity', { ...ident, failed_attempts: fails, locked_until: lock }));
      throw generic;
    }
    await tx(['auth_identity'], 'readwrite', t => t.put('auth_identity', { ...ident, failed_attempts: 0, locked_until: null, last_used_at: new Date().toISOString() }));
    await startSessionSafe(ident.user_id, !!remember);
    return ident.user_id;
  },
  async currentUser() {
    const token = localStorage.getItem(SESSION_KEY) || sessionStorage.getItem(SESSION_KEY);
    if (!token) return null;
    const session = await get('session', await sha256(token));
    if (!session || Date.parse(session.expires_at) < Date.now()) { this.logout(); return null; }
    return get('user_account', session.user_id);
  },
  async logout() {
    const token = localStorage.getItem(SESSION_KEY) || sessionStorage.getItem(SESSION_KEY);
    localStorage.removeItem(SESSION_KEY); sessionStorage.removeItem(SESSION_KEY);
    if (token) { const th = await sha256(token); await tx(['session'], 'readwrite', t => t.del('session', th)); }
  },
};
async function startSessionSafe(userId, remember) {
  const token = hex(crypto.getRandomValues(new Uint8Array(32)));
  const tokenHash = await sha256(token);
  const now = Date.now();
  await tx(['session'], 'readwrite', t => t.put('session', { token_hash: tokenHash, user_id: userId, created_at: new Date(now).toISOString(),
    expires_at: new Date(now + (remember ? 30 : 1) * 86400000).toISOString() }));
  (remember ? localStorage : sessionStorage).setItem(SESSION_KEY, token);
  (remember ? sessionStorage : localStorage).removeItem(SESSION_KEY);
}
export const Auth = LocalAuthAdapter;
