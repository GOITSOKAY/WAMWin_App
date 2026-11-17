import { h, field } from '../core/dom.js';
import { authLayout, passwordInput } from './auth-layout.js';
import { Auth, AuthError, passwordStrength, validEmail } from '../security/auth.js';
import { legalLinks, openDoc } from '../privacy/consent.js';

export async function mount(root, ctx) {
  const name = h('input', { class: 'input', type: 'text', autocomplete: 'name', required: true, maxlength: 80 });
  const email = h('input', { class: 'input', type: 'email', autocomplete: 'email', inputmode: 'email', required: true, maxlength: 254 });
  const pw = passwordInput('reg-password', 'new-password');
  const meter = h('div', { class: 'meter', 'data-score': '0', 'aria-hidden': 'true' }, h('span'));
  const fName = field({ label: 'Your name', input: name });
  const fEmail = field({ label: 'Email', input: email });
  const fPw = field({ label: 'Password', hint: 'At least 10 characters. A short phrase is easy to remember and hard to guess.', input: pw.input });
  fPw.replaceChild(pw.wrap, pw.input); pw.wrap.prepend(pw.input);   // field() moved the input; put it back inside the show/hide wrapper
  fPw.insertBefore(meter, fPw.querySelector('.field-error'));
  // Nothing pre-ticked. Health-data consent is asked separately, at the moment health details are first entered.
  const age = h('input', { type: 'checkbox', id: 'c-age', required: true });
  const terms = h('input', { type: 'checkbox', id: 'c-terms', required: true });
  const privacy = h('input', { type: 'checkbox', id: 'c-privacy', required: true });
  const link = (code, text) => h('button', { type: 'button', class: 'btn-text inline', text, onclick: () => openDoc(code) });
  const formError = h('p', { class: 'form-error', role: 'alert' });
  const submit = h('button', { class: 'btn btn-primary btn-block', type: 'submit', text: 'Create account' });

  pw.input.addEventListener('input', () => {
    const s = passwordStrength(pw.input.value, [name.value, email.value.split('@')[0]]);
    meter.dataset.score = String(s.score); meter.firstChild.style.width = `${s.score * 25}%`;
    fPw.querySelector('.hint').textContent = pw.input.value ? s.message : 'At least 10 characters. A short phrase is easy to remember and hard to guess.';
  });
  const form = h('form', { class: 'stack', novalidate: true },
    fName, fEmail, fPw,
    h('fieldset', { class: 'stack-s' }, h('legend', { class: 'sr-only', text: 'Agreements' }),
      h('label', { class: 'check', for: 'c-age' }, age, h('span', { text: 'I am 18 or older.' })),
      h('label', { class: 'check', for: 'c-terms' }, terms, h('span', {}, 'I agree to the ', link('TERMS', 'Terms of Use'), '.')),
      h('label', { class: 'check', for: 'c-privacy' }, privacy, h('span', {}, 'I have read the ', link('PRIVACY_NOTICE', 'Privacy Notice'), ' and the ', link('CONSUMER_HEALTH_DATA_POLICY', 'Consumer Health Data Privacy Policy'), '.'))),
    h('p', { class: 'hint', text: 'We never sell your information or use it for ads. We ask for separate permission before saving any health or allergy details.' }),
    formError, submit,
    h('p', { class: 'hint', style: { textAlign: 'center' }, text: 'Your account is stored on this device and protected by your password.' }),
    legalLinks());

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    formError.textContent = '';
    fName.setError(name.value.trim() ? '' : 'Enter your name.');
    fEmail.setError(validEmail(email.value) ? '' : 'Enter a valid email address, like name@example.com.');
    const s = passwordStrength(pw.input.value, [name.value, email.value.split('@')[0]]);
    fPw.setError(s.score >= 2 ? '' : s.message);
    if (!name.value.trim() || !validEmail(email.value) || s.score < 2) return form.querySelector('[aria-invalid="true"]')?.focus();
    if (!age.checked) { formError.textContent = 'WAMWins accounts are for adults 18 and older. A parent or guardian can add children to a household.'; return age.focus(); }
    if (!terms.checked || !privacy.checked) { formError.textContent = 'Please agree to the Terms of Use and confirm you have read the Privacy Notice to create an account.'; return (terms.checked ? privacy : terms).focus(); }
    submit.disabled = true; submit.textContent = 'Creating account…';
    try {
      await Auth.register({ name: name.value, email: email.value, password: pw.input.value,
        consents: { AGE_18_PLUS: true, TERMS: true, PRIVACY_POLICY: true } });
      ctx.go('setup/about');
    } catch (err) {
      formError.textContent = err instanceof AuthError ? err.message : 'Your account could not be created. Please try again.';
      if (err?.code === 'EXISTS') formError.append(' ', h('button', { type: 'button', class: 'btn-text', text: 'Log in', onclick: () => ctx.go('login') }));
      submit.disabled = false; submit.textContent = 'Create account';
    }
  });
  root.append(authLayout(
    h('div', { class: 'row', style: { justifyContent: 'space-between' } }, h('h1', { tabindex: '-1', text: 'Create your account' })),
    form,
    h('p', { class: 'auth-switch' }, 'Already have an account? ', h('button', { type: 'button', class: 'btn-text', text: 'Log in', onclick: () => ctx.go('login') }))));
  name.focus();
  return { dispose() {} };
}
