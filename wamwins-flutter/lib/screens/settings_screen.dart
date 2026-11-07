import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../core/db.dart';
import '../inquiry/catalog.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.user});
  final DbRow user;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _confirm = TextEditingController();
  bool _showDelete = false;
  String? _confirmErr;
  @override
  void dispose() { _confirm.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final theme = switch (s.themeMode.value) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' };
    Widget row(String a, String b) => Container(constraints: const BoxConstraints(minHeight: 56), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
        child: Row(children: [Text(a), const Spacer(), Flexible(child: Text(b, textAlign: TextAlign.end, style: TextStyle(color: p.text2)))]));
    return Scaffold(
      appBar: wamAppBar(context, leading: IconButton(tooltip: 'Back to home', icon: const Icon(Icons.arrow_back), onPressed: () => s.router.go('home', replace: true)),
          title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.all(20), children: [ContentWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Account', style: Theme.of(context).textTheme.titleLarge),
        row('Name', widget.user['display_name'] as String),
        row('Email', widget.user['email'] as String),
        const SizedBox(height: 28),
        Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ChoiceList(options: const [Option('system', 'Match my device'), Option('light', 'Light'), Option('dark', 'Dark')],
            value: theme, onChanged: (v) => setState(() => s.setTheme(v))),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your data stays private', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Your household information is protected by several layers of security. Only people you invite into your household can see it, and health details are visible only to members you allow.'),
            const SizedBox(height: 8),
            Text('Your password is stored only as a protected one-way code, so it can’t be read back, even from this device.', style: Theme.of(context).textTheme.bodySmall),
          ])),
        const SizedBox(height: 24),
        GhostButton(onPressed: () async { await s.auth.logout(); s.toast('Signed out.'); s.router.reset('welcome'); }, child: const Text('Sign out')),
        const SizedBox(height: 8),
        if (!_showDelete) TextButton(onPressed: () => setState(() => _showDelete = true), style: TextButton.styleFrom(foregroundColor: p.danger),
            child: const Text('Delete all WAMWins data on this device…')),
        if (_showDelete) ...[
          const SizedBox(height: 8),
          TextField(controller: _confirm, decoration: wamField(context).copyWith(labelText: 'Type DELETE to confirm', errorText: _confirmErr)),
          const SizedBox(height: 10),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: p.dangerBg, foregroundColor: p.danger, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
            onPressed: () async {
              if (_confirm.text.trim() != 'DELETE') return setState(() => _confirmErr = 'Type DELETE in capital letters.');
              await s.auth.logout();
              await s.secure.deleteAll();
              s.db.transaction(() {
                for (final r in s.db.select("SELECT id FROM household WHERE owner_user_id = ?", [widget.user['id']])) {
                  s.db.run("UPDATE household SET status = 'PENDING_DELETION' WHERE id = ?", [r['id']]);
                  s.db.run('DELETE FROM household WHERE id = ?', [r['id']]);
                }
                s.db.run('DELETE FROM user_account WHERE id = ?', [widget.user['id']]);
                s.db.run("DELETE FROM local_setting WHERE key LIKE 'profile.%'");
              });
              s.toast('All WAMWins data was deleted from this device.');
              s.router.reset('welcome');
            },
            child: const Text('Delete all data on this device')),
        ],
      ]))]),
    );
  }
}

