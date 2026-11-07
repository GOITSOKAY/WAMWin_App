import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../security/auth_service.dart';
import '../ui/widgets.dart';
import 'auth_layout.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController(), _email = TextEditingController(), _pw = TextEditingController();
  bool _terms = false, _health = false, _busy = false;
  String? _nameErr, _emailErr, _pwErr, _formErr;
  PasswordStrength _strength = passwordStrength('');

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = AppScope.of(context);
    final strength = passwordStrength(_pw.text, [_name.text, _email.text.split('@').first]);
    setState(() {
      _formErr = null;
      _nameErr = _name.text.trim().isEmpty ? 'Enter your name.' : null;
      _emailErr = validEmail(_email.text) ? null : 'Enter a valid email address, like name@example.com.';
      _pwErr = strength.score >= 2 ? null : strength.message;
      if (_nameErr == null && _emailErr == null && _pwErr == null && !_terms) _formErr = 'Please accept the Terms of Use and Privacy Policy to create an account.';
    });
    if (_nameErr != null || _emailErr != null || _pwErr != null || _formErr != null) return;
    setState(() => _busy = true);
    try {
      await s.auth.register(name: _name.text, email: _email.text, password: _pw.text,
          consents: {'TERMS': true, 'PRIVACY_POLICY': true, 'HEALTH_DATA_PROCESSING': _health});
      s.router.reset('setup/about');
    } on AuthException catch (e) {
      setState(() { _formErr = e.message; _busy = false; });
    } catch (_) {
      setState(() { _formErr = 'Your account could not be created. Please try again.'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final meterColor = _strength.score >= 3 ? p.ok : _strength.score == 2 ? Brand.yellow600 : p.danger;
    return AuthLayout(children: [
      Semantics(header: true, child: Text('Create your account', style: Theme.of(context).textTheme.headlineMedium)),
      const SizedBox(height: 20),
      AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _name, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.name],
            onChanged: (_) { if (_nameErr != null) setState(() => _nameErr = null); },
            decoration: wamField(context).copyWith(labelText: 'Your name', errorText: _nameErr)),
        const SizedBox(height: 14),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, autofillHints: const [AutofillHints.email],
            onChanged: (_) { if (_emailErr != null) setState(() => _emailErr = null); },
            decoration: wamField(context).copyWith(labelText: 'Email', errorText: _emailErr)),
        const SizedBox(height: 14),
        PasswordField(controller: _pw, label: 'Password', newPassword: true, error: _pwErr,
            hint: _pw.text.isEmpty ? 'At least 10 characters. A short phrase is easy to remember and hard to guess.' : _strength.message,
            onChanged: (v) => setState(() { _strength = passwordStrength(v, [_name.text, _email.text.split('@').first]); _pwErr = null; })),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: _strength.score / 4, minHeight: 6,
            backgroundColor: p.surface2, color: meterColor, semanticsLabel: 'Password strength')),
      ])),
      const SizedBox(height: 8),
      CheckboxListTile(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false), contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading, title: const Text('I agree to the WAMWins Terms of Use and Privacy Policy.')),
      CheckboxListTile(value: _health, onChanged: (v) => setState(() => _health = v ?? false), contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Use my family’s allergies and diets to keep meal suggestions safe.'),
          subtitle: const Text('Optional. You can change this later.')),
      const SizedBox(height: 8),
      ErrorBanner(_formErr),
      const SizedBox(height: 12),
      PrimaryButton(label: _busy ? 'Creating account…' : 'Create account', busy: _busy, onPressed: _submit),
      const SizedBox(height: 10),
      Text('Your account is saved securely on this device.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Already have an account?', style: TextStyle(color: p.text2)),
        TextButton(onPressed: () => s.router.go('login', replace: true), child: const Text('Log in')),
      ]),
    ]);
  }
}
