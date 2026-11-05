import { h, field } from '../core/dom.js';
import { authLayout, passwordInput } from './auth-layout.js';
import { Auth, AuthError, passwordStrength, validEmail } from '../security/auth.js';

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
  const terms = h('input', { type: 'checkbox', id: 'c-terms', required: true });
  const health = h('input', { type: 'checkbox', id: 'c-health' });
  const formError = h('p', { class: 'form-error', role: 'alert' });
  const submit = h('button', { class: 'btn btn-primary btn-block', type: 'submit', text: 'Create account' });

  pw.input.addEventListener('input', () => {
    const s = passwordStrength(pw.input.value, [name.value, email.value.split('@')[0]]);
    meter.dataset.score = String(s.score); meter.firstChild.style.width = `${s.score * 25}%`;
    fPw.querySelector('.hint').textContent = pw.input.value ? s.message : 'At least 10 characters. A short phrase is easy to remember and hard to guess.';
  });
  const form = h('form', { class: 'stack', novalidate: true },
    fName, fEmail, fPw,
    h('div', {},
      h('label', { class: 'check', for: 'c-terms' }, terms, h('span', { text: 'I agree to the WAMWins Terms of Use and Privacy Policy.' })),
      h('label', { class: 'check', for: 'c-health' }, health,
        h('span', {}, 'Use my family’s allergies and diets to keep meal suggestions safe. ', h('span', { class: 'hint', text: 'Optional. You can change this later.' })))),
    formError, submit,
    h('p', { class: 'hint', style: { textAlign: 'center' }, text: 'Your account is saved securely on this device.' }));

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    formError.textContent = '';
    fName.setError(name.value.trim() ? '' : 'Enter your name.');
    fEmail.setError(validEmail(email.value) ? '' : 'Enter a valid email address, like name@example.com.');
    const s = passwordStrength(pw.input.value, [name.value, email.value.split('@')[0]]);
    fPw.setError(s.score >= 2 ? '' : s.message);
    if (!name.value.trim() || !validEmail(email.value) || s.score < 2) return form.querySelector('[aria-invalid="true"]')?.focus();
    if (!terms.checked) { formError.textContent = 'Please accept the Terms of Use and Privacy Policy to create an account.'; return terms.focus(); }
    submit.disabled = true; submit.textContent = 'Creating account…';
    try {
      await Auth.register({ name: name.value, email: email.value, password: pw.input.value,
        consents: { TERMS: true, PRIVACY_POLICY: true, HEALTH_DATA_PROCESSING: health.checked } });
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
