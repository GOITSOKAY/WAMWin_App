import { h, field, toast } from '../core/dom.js';
import { authLayout, passwordInput } from './auth-layout.js';
import { Auth, AuthError } from '../security/auth.js';

export async function mount(root, ctx) {
  const email = h('input', { class: 'input', type: 'email', autocomplete: 'username', inputmode: 'email', required: true });
  const pw = passwordInput('login-password', 'current-password');
  const fEmail = field({ label: 'Email', input: email });
  const fPw = field({ label: 'Password', input: pw.input });
  fPw.replaceChild(pw.wrap, pw.input); pw.wrap.prepend(pw.input);   // field() moved the input; put it back inside the show/hide wrapper
  const remember = h('input', { type: 'checkbox', id: 'remember', checked: true });
  const formError = h('p', { class: 'form-error', role: 'alert' });
  const submit = h('button', { class: 'btn btn-primary btn-block', type: 'submit', text: 'Log in' });
  const form = h('form', { class: 'stack', novalidate: true }, fEmail, fPw,
    h('label', { class: 'check', for: 'remember' }, remember, h('span', { text: 'Keep me signed in on this device' })),
    formError, submit,
    h('button', { type: 'button', class: 'btn-text', text: 'Forgot your password?', onclick: () =>
      toast('Password reset by email arrives with WAMWins cloud sign-in. Until then, accounts stay on this device.') }));
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    formError.textContent = '';
    if (!email.value.trim() || !pw.input.value) { formError.textContent = 'Enter your email and password.'; return; }
    submit.disabled = true; submit.textContent = 'Logging in…';
    try { await Auth.login({ email: email.value, password: pw.input.value, remember: remember.checked }); ctx.go(''); }
    catch (err) {
      formError.textContent = err instanceof AuthError ? err.message : 'Log in failed. Please try again.';
      pw.input.value = ''; pw.input.focus();
      submit.disabled = false; submit.textContent = 'Log in';
    }
  });
  root.append(authLayout(h('h1', { tabindex: '-1', text: 'Welcome back' }), form,
    h('p', { class: 'auth-switch' }, 'New to WAMWins? ', h('button', { type: 'button', class: 'btn-text', text: 'Create account', onclick: () => ctx.go('register') }))));
  email.focus();
  return { dispose() {} };
}
