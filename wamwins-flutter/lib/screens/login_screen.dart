import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../security/auth_service.dart';
import '../ui/widgets.dart';
import 'auth_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(), _pw = TextEditingController();
  bool _remember = true, _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = AppScope.of(context);
    if (_email.text.trim().isEmpty || _pw.text.isEmpty) return setState(() => _error = 'Enter your email and password.');
    setState(() { _busy = true; _error = null; });
    try {
      await s.auth.login(email: _email.text, password: _pw.text, remember: _remember);
      s.router.reset('');
    } on AuthException catch (e) {
      _pw.clear();
      setState(() { _error = e.message; _busy = false; });
    } catch (_) {
      setState(() { _error = 'Log in failed. Please try again.'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    return AuthLayout(children: [
      Semantics(header: true, child: Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium)),
      const SizedBox(height: 20),
      AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, autofillHints: const [AutofillHints.email],
            decoration: wamField(context).copyWith(labelText: 'Email')),
        const SizedBox(height: 14),
        PasswordField(controller: _pw, label: 'Password', onSubmitted: (_) => _submit()),
      ])),
      CheckboxListTile(value: _remember, onChanged: (v) => setState(() => _remember = v ?? true), contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading, title: const Text('Keep me signed in on this device')),
      ErrorBanner(_error),
      const SizedBox(height: 12),
      PrimaryButton(label: _busy ? 'Logging in…' : 'Log in', busy: _busy, onPressed: _submit),
      TextButton(onPressed: () => s.toast('Password reset by email arrives with WAMWins cloud sign-in. Until then, accounts stay on this device.'),
          child: const Text('Forgot your password?')),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('New to WAMWins?', style: TextStyle(color: p.text2)),
        TextButton(onPressed: () => s.router.go('register', replace: true), child: const Text('Create account')),
      ]),
    ]);
  }
}
