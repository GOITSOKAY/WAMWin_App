import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../core/db.dart';
import '../privacy/consent_dialog.dart';
import '../privacy/notices.dart';
import '../privacy/privacy_service.dart';
import '../ui/widgets.dart';

/// Privacy & sharing (same content and rules as the web client, frontend/www/js/screens/privacy.js):
/// consents with withdraw, who can see each person's health details and until when, access history,
/// download a copy, delete health details, privacy requests. Free on every plan.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.user});
  final DbRow user;
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late PrivacyService _p;
  late String _uid;
  String? _hh;
  DbRow? _membership;

  static const _consentRows = [('TERMS', 'Terms of Use'), ('PRIVACY_POLICY', 'Privacy Notice'), ('HEALTH_DATA_PROCESSING', 'Collect and use health details'),
    ('MEDIA_PROCESSING', 'Reference photos'), ('VOICE_COMMANDS', 'Voice commands')];
  static const _requests = [('ACCESS', 'Tell me what information you hold about me'), ('RECIPIENTS', 'List the people and companies that received my health data'),
    ('CORRECTION', 'Correct my information'), ('DELETION', 'Delete my information'), ('APPEAL', 'Appeal a decision on an earlier request'), ('OTHER', 'Something else')];
  static const _status = {'ACTIVE': 'Active', 'SCHEDULED': 'Starts later', 'EXPIRED': 'Expired', 'REVOKED': 'Ended'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _p = PrivacyService(s.db);
    _uid = widget.user['id'] as String;
    _membership = _p.membershipOf(_uid);
    _hh = _membership?['household_id'] as String?;
  }

  String _fmt(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso).toLocal();
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${mo[d.month - 1]} ${d.day}, ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  String _cat(String c) => accessCategories.firstWhere((a) => a.code == c, orElse: () => AccessCategory(c, c)).name;

  List<DbRow> get _members => _hh == null ? const [] : AppScope.of(context).db.select(
      'SELECT id, household_id, display_name, linked_user_id, age_band FROM family_member WHERE household_id = ? AND deleted_at IS NULL ORDER BY created_at', [_hh]);
  List<DbRow> _managed(List<DbRow> grants) => _members.where((m) =>
      const {'SELF', 'GUARDIAN'}.contains(PrivacyService.relation(userId: _uid, membership: _membership, member: m, grants: grants))).toList();

  Future<bool> _confirm(String title, String body, String ok) async => await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(title), content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok))])) == true;

  Future<void> _withdraw(String type, String label) async {
    final health = type == 'HEALTH_DATA_PROCESSING';
    if (!await _confirm('Withdraw “$label”?', health
        ? 'Health details you manage will be deleted, and shared access to them will end. Meal matching will no longer use them. This can’t be undone.'
        : 'The feature will stop until you give consent again.', health ? 'Withdraw and delete' : 'Withdraw')) { return; }
    _p.recordConsent(_uid, type, false, method: 'SETTINGS');
    if (health && _hh != null) {
      final grants = _p.grants(_hh!), ids = _managed(grants).map((m) => m['id'] as String).toList();
      for (final g in grants.where((g) => ids.contains(g['subject_member_id']) && const {'ACTIVE', 'SCHEDULED'}.contains(PrivacyService.grantStatus(g)))) { _p.revokeGrant(g, _uid); }
      _p.deleteHealthDetails(_hh!, ids, _uid);
    }
    if (!mounted) return;
    AppScope.of(context).toast('Consent withdrawn.');
    setState(() {});
  }

  Future<void> _giveAccess(DbRow member) async {
    final s = AppScope.of(context);
    final people = s.db.select("SELECT u.id, u.display_name FROM household_membership m JOIN user_account u ON u.id = m.user_id "
        "WHERE m.household_id = ? AND m.status = 'ACTIVE' AND m.user_id <> ?", [_hh, _uid]);
    String who = people.isEmpty ? '__new__' : people.first['id'] as String, level = 'VIEW', dur = 'P7D';
    final name = TextEditingController(), email = TextEditingController(), purpose = TextEditingController();
    final cats = <String>{'ALLERGIES', 'DIETS'};
    String? err;
    final result = await showDialog<Map<String, Object?>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: Text('Give access to ${member['display_name']}’s details'),
      scrollable: true,
      content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: who, decoration: const InputDecoration(labelText: 'Who'), items: [
          for (final p in people) DropdownMenuItem(value: p['id'] as String, child: Text(p['display_name'] as String)),
          const DropdownMenuItem(value: '__new__', child: Text('Someone else (by email)'))], onChanged: (v) => set(() => who = v!)),
        if (who == '__new__') ...[
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Their name')),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Their email', helperText: 'They can see the details once they sign in with this email.')),
        ],
        const SizedBox(height: 12), const Text('Which details', style: TextStyle(fontWeight: FontWeight.w500)),
        for (final c in accessCategories) CheckboxListTile(value: cats.contains(c.code), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            title: Text(c.name), onChanged: (v) => set(() => v == true ? cats.add(c.code) : cats.remove(c.code))),
        DropdownButtonFormField<String>(value: level, decoration: const InputDecoration(labelText: 'Access'), items: const [
          DropdownMenuItem(value: 'VIEW', child: Text('View only')), DropdownMenuItem(value: 'VIEW_EDIT', child: Text('View and edit'))], onChanged: (v) => set(() => level = v!)),
        DropdownButtonFormField<String>(value: dur, decoration: const InputDecoration(labelText: 'For how long'),
            items: [for (final d in accessDurations.where((d) => d.code != 'CUSTOM')) DropdownMenuItem(value: d.code, child: Text(d.name))], onChanged: (v) => set(() => dur = v!)),
        if (dur == 'NONE') Text('Access will last until you end it. Setting an end date is safer.', style: TextStyle(color: Palette.of(ctx).danger)),
        TextField(controller: purpose, maxLength: 120, decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. babysitting this weekend')),
        if (err != null) Text(err!, style: TextStyle(color: Palette.of(ctx).danger)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () {
        if (who == '__new__' && (name.text.trim().isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email.text.trim()))) return set(() => err = 'Enter their name and a valid email.');
        if (cats.isEmpty) return set(() => err = 'Choose at least one kind of detail.');
        Navigator.pop(ctx, {'who': who});
      }, child: const Text('Continue'))],
    )));
    if (result == null || !mounted) return;
    final start = DateTime.now();
    final days = accessDurations.firstWhere((d) => d.code == dur).days;
    final end = days == null ? null : start.add(Duration(days: days));
    final granteeName = who == '__new__' ? name.text.trim() : people.firstWhere((p) => p['id'] == who)['display_name'] as String;
    final ok = await askConsent(context, _uid, 'HEALTH_DATA_SHARING', subjectRef: member['id'] as String, extra: [
      '$granteeName will ${level == 'VIEW_EDIT' ? 'be able to view and edit' : 'be able to view'} ${member['display_name']}’s: ${cats.map(_cat).join(', ')}.',
      'From ${_fmt(start.toUtc().toIso8601String())} ${end == null ? 'until you end it' : 'until ${_fmt(end.toUtc().toIso8601String())}'}.']);
    if (!mounted) return;
    if (!ok) return s.toast('Nothing was shared.');
    _p.createGrant(householdId: _hh!, subject: member, grantedBy: _uid, granteeUserId: who == '__new__' ? null : who, granteeEmail: who == '__new__' ? email.text.trim() : null,
        granteeName: granteeName, categories: cats.toList(), accessLevel: level, startsAt: start, expiresAt: end, purpose: purpose.text.trim().isEmpty ? null : purpose.text.trim());
    s.toast('$granteeName now has access${end == null ? '' : ' until ${_fmt(end.toUtc().toIso8601String())}'}.');
    setState(() {});
  }

  Future<void> _download() async {
    final s = AppScope.of(context);
    final f = File('${(await getTemporaryDirectory()).path}/wamwins-my-data-${DateTime.now().toIso8601String().substring(0, 10)}.json');
    await f.writeAsString(_p.exportJson(widget.user, _hh));
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/json')], text: 'My WAMWins data');
    s.toast('Keep the file somewhere safe: it contains health details.');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final pal = Palette.of(context);
    final grants = _hh == null ? <DbRow>[] : _p.grants(_hh!);
    final managed = _managed(grants);
    final history = _p.consentHistory(_uid);
    Widget panel(String title, List<Widget> children) => Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(title, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), ...children]));
    final reqType = ValueNotifier<String>('ACCESS');
    final reqDetails = TextEditingController();
    return Scaffold(
      appBar: wamAppBar(context, leading: IconButton(tooltip: 'Back to settings', icon: const Icon(Icons.arrow_back), onPressed: () => s.router.go('settings', replace: true)),
          title: const Text('Privacy & sharing', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.all(20), children: [ContentWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        panel('Your consents', [
          Text('You can withdraw any optional consent. Other features keep working.', style: TextStyle(color: pal.text2)),
          for (final (type, label) in _consentRows) Builder(builder: (_) {
            final r = history.where((x) => x['consent_type'] == type && x['subject_ref'] == null).lastOrNull;
            final on = r?['granted'] == 1;
            return ListTile(contentPadding: EdgeInsets.zero, title: Text(label),
              subtitle: Text(r == null ? 'Not asked yet' : '${on ? 'Given' : 'Not given'} ${_fmt(r['recorded_at'] as String)} · version ${r['document_version']}'),
              trailing: const {'TERMS', 'PRIVACY_POLICY'}.contains(type) ? null : on
                  ? TextButton(onPressed: () => _withdraw(type, label), child: const Text('Withdraw'))
                  : TextButton(onPressed: () async { if (await askConsent(context, _uid, type)) setState(() {}); }, child: const Text('Give consent')));
          }),
        ]),
        panel('Who can see health details', [
          Text('Choose who can see each person’s food and health details, which details, and for how long. Access ends automatically at the time you set.', style: TextStyle(color: pal.text2)),
          for (final m in managed) Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(m['linked_user_id'] == _uid ? '${m['display_name']} (you)' : m['display_name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final g in grants.where((g) => g['subject_member_id'] == m['id'])) Builder(builder: (_) {
              final st = PrivacyService.grantStatus(g);
              return ListTile(contentPadding: EdgeInsets.zero, title: Text('${g['grantee_name']} · ${_status[st]}'),
                subtitle: Text('${g['access_level'] == 'VIEW_EDIT' ? 'Can view and edit' : 'Can view'}: ${PrivacyService.categoriesOf(g).map(_cat).join(', ')}\n'
                    'From ${_fmt(g['starts_at'] as String)} ${g['expires_at'] == null ? 'until you end it' : 'until ${_fmt(g['expires_at'] as String)}'}'),
                trailing: const {'ACTIVE', 'SCHEDULED'}.contains(st)
                    ? TextButton(style: TextButton.styleFrom(foregroundColor: pal.danger), onPressed: () { _p.revokeGrant(g, _uid); setState(() {}); }, child: const Text('End access')) : null);
            }),
            if (!grants.any((g) => g['subject_member_id'] == m['id'])) Text('Nobody else has access.', style: TextStyle(color: pal.text2)),
            Align(alignment: Alignment.centerLeft, child: GhostButton(expand: false, onPressed: () => _giveAccess(m), child: const Text('Give access'))),
          ])),
        ]),
        panel('Access history', [
          for (final l in _hh == null ? const <DbRow>[] : _p.accessLog(_hh!))
            Text('${_fmt(l['at'] as String)} · ${l['action'].toString().replaceAll('_', ' ').toLowerCase()}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        panel('Your data', [
          GhostButton(onPressed: _download, child: const Text('Download a copy of my data')),
          const SizedBox(height: 8),
          if (managed.isNotEmpty) GhostButton(onPressed: () async {
            if (!await _confirm('Delete health details', 'Allergies, intolerances, diets, health-related goals, food rules and preferences of everyone you manage will be deleted. Shared access to them ends. This can’t be undone.', 'Delete')) return;
            final ids = managed.map((m) => m['id'] as String).toList();
            for (final g in grants.where((g) => ids.contains(g['subject_member_id']) && const {'ACTIVE', 'SCHEDULED'}.contains(PrivacyService.grantStatus(g)))) { _p.revokeGrant(g, _uid); }
            final n = _p.deleteHealthDetails(_hh!, ids, _uid);
            s.toast(n > 0 ? 'Deleted $n health details.' : 'There were no health details to delete.');
            setState(() {});
          }, child: const Text('Delete health details…')),
        ]),
        panel('Make a privacy request', [
          Text('Most things you can do yourself above. For anything else, send a request: we answer within 45 days.', style: TextStyle(color: pal.text2)),
          ValueListenableBuilder(valueListenable: reqType, builder: (_, v, __) => DropdownButtonFormField<String>(value: v, isExpanded: true,
              decoration: const InputDecoration(labelText: 'What do you need?'), items: [for (final (c, t) in _requests) DropdownMenuItem(value: c, child: Text(t))], onChanged: (x) => reqType.value = x!)),
          TextField(controller: reqDetails, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Details (optional)')),
          FilledButton(onPressed: () { final r = _p.fileRequest(userId: _uid, householdId: _hh, type: reqType.value, details: reqDetails.text.trim());
            s.toast('Request received. We will answer by ${_fmt(r['due_at'] as String)}.'); setState(() {}); }, child: const Text('Send request')),
          for (final r in _p.requests(_uid)) Text('${_requests.firstWhere((x) => x.$1 == r['request_type'], orElse: () => (r['request_type'] as String, r['request_type'] as String)).$2} · due ${_fmt(r['due_at'] as String)}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        const LegalLinks(),
      ]))]),
    );
  }
}
