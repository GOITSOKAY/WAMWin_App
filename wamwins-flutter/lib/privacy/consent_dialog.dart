import 'package:flutter/material.dart';

import '../app/scope.dart';
import 'notices.dart';
import 'privacy_service.dart';

/// Consent pop-up (same rules as the web client): nothing pre-ticked, the agree button stays off until the box is
/// ticked, declining is as easy as agreeing, and both answers are recorded with a hash of the exact words shown.
/// Dismissing without an answer records nothing. Returns true only when the person agreed.
Future<bool> askConsent(BuildContext context, String userId, String type, {String? subjectRef, String? subjectName, List<String> extra = const []}) async {
  final def = consentDefs[type]!;
  final privacy = PrivacyService(AppScope.of(context).db);
  final shown = [def.title, if (subjectName != null) subjectName, def.lead, ...def.list, ...extra, def.check];
  final answer = await showDialog<bool>(context: context, barrierDismissible: true, builder: (ctx) {
    var ticked = false;
    return StatefulBuilder(builder: (ctx, setState) => AlertDialog(
      title: Text(def.title),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (subjectName != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [const Icon(Icons.person_outline, size: 18), const SizedBox(width: 6), Text(subjectName, style: const TextStyle(fontWeight: FontWeight.w700))])),
        Text(def.lead),
        const SizedBox(height: 8),
        for (final x in def.list) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(x))])),
        for (final x in extra) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(x)),
        TextButton(onPressed: () => showLegalDoc(ctx, def.doc), child: Text('Read the ${legalDocs[def.doc]!.title}')),
        CheckboxListTile(value: ticked, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => ticked = v ?? false), title: Text(def.check)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(def.decline)),
        FilledButton(onPressed: ticked ? () => Navigator.of(ctx).pop(true) : null, child: Text(def.agree)),
      ],
    ));
  });
  if (answer != null) privacy.recordConsent(userId, type, answer, subjectRef: subjectRef, shown: shown);
  return answer == true;
}

/// Shows a legal document (Privacy Notice, Consumer Health Data Privacy Policy, Terms of Use).
Future<void> showLegalDoc(BuildContext context, String code) {
  final d = legalDocs[code]!;
  return showDialog<void>(context: context, builder: (ctx) => AlertDialog(
    title: Text(d.title),
    scrollable: true,
    content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${legal.operator} · ${legal.product} · Version ${d.version}', style: Theme.of(ctx).textTheme.bodySmall),
      for (final s in d.sections) ...[
        if (s.h != null) Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(s.h!, style: const TextStyle(fontWeight: FontWeight.w700))),
        for (final p in s.p) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(p)),
        for (final x in s.list) Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(x))])),
      ],
    ]),
    actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
  ));
}

/// Links to the three notices (registration, settings).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});
  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.center, children: [
        for (final e in const [('PRIVACY_NOTICE', 'Privacy Notice'), ('CONSUMER_HEALTH_DATA_POLICY', 'Consumer Health Data Policy'), ('TERMS', 'Terms of Use')])
          TextButton(onPressed: () => showLegalDoc(context, e.$1), child: Text(e.$2)),
      ]);
}
