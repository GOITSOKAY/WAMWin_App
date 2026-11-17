import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../core/db.dart';
import '../privacy/consent_dialog.dart';
import '../ui/tier_locked.dart';
import '../ui/widgets.dart';
import 'voice_commands.dart';
import 'voice_gate.dart';

const voiceLocked = [LockedFeature('VOICE_COMMANDS', 'Voice Commands', Icons.mic_none,
    'Say “open inventory”, “what can we cook for dinner” or “do we have eggs” instead of tapping. Recordings are never kept.')];

/// Voice commands (higher tier). Gate order: capability -> consent -> tap to listen for ONE command.
/// On-device recognition is requested (onDevice: true); WAMWins keeps no audio, no transcripts and no voiceprints,
/// never reads health details aloud, and never changes data without an on-screen confirmation.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key, required this.user});
  final DbRow user;
  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  SpeechToText? _stt;                                   // created only after every gate passes
  bool _listening = false;
  String _heard = '', _answer = '';

  Future<void> _listen() async {
    final s = AppScope.of(context);
    if (!VoiceGate.consented(s, widget.user) && !await askConsent(context, widget.user['id'] as String, VoiceGate.capability)) return;
    _stt ??= SpeechToText();
    if (!await _stt!.initialize(onError: (e) => setState(() { _listening = false; _answer = 'Voice recognition stopped. Please try again.'; }))) {
      return setState(() => _answer = 'Microphone or speech recognition is off. Allow it in your phone settings, then try again.');
    }
    setState(() { _listening = true; _heard = ''; _answer = ''; });
    await _stt!.listen(listenFor: const Duration(seconds: 8), pauseFor: const Duration(seconds: 2),
        listenOptions: SpeechListenOptions(onDevice: true, partialResults: true, cancelOnError: true, listenMode: ListenMode.confirmation),
        onResult: (r) {
          setState(() => _heard = r.recognizedWords);
          if (r.finalResult) { setState(() => _listening = false); _run(parseCommand(r.recognizedWords)); }   // transcript not stored
        });
  }

  Future<void> _run(VoiceIntent i) async {
    final s = AppScope.of(context);
    final hh = s.profile.householdIdFor(widget.user['id'] as String);
    switch (i.kind) {
      case 'NAVIGATE': setState(() => _answer = '${i.say}…'); s.router.go(i.route!);
      case 'MATCH': setState(() => _answer = 'Opening meal ideas…'); s.router.go('match');
      case 'STOCK':
        final q = '%${i.name!.toLowerCase().replaceFirst(RegExp(r's$'), '')}%';
        final hits = s.db.select('SELECT m.canonical_name AS n, i.quantity AS q, u.symbol AS u FROM inventory_item i JOIN item_master m ON m.id = i.item_master_id '
            'LEFT JOIN unit_of_measure u ON u.code = i.unit_code WHERE i.household_id = ? AND i.quantity > 0 AND i.deleted_at IS NULL AND lower(m.canonical_name) LIKE ? LIMIT 4', [hh, q]);
        setState(() => _answer = hits.isEmpty ? 'I couldn’t find ${i.name} in your inventory.' : 'Yes: ${hits.map((h) => '${h['n']}, ${h['q']} ${h['u'] ?? ''}'.trim()).join('; ')}.');
      case 'ADD':
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Add food?'),
            content: Text('You said: add ${i.quantity != null ? '${i.quantity} ' : ''}${i.name}.\n\nNothing is saved yet. WAMWins opens your inventory so you can check the details and save.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Add food'))]));
        if (ok == true) { s.router.go('inventory'); } else { setState(() => _answer = 'Nothing was added.'); }
      case 'NONE': setState(() => _answer = 'I didn’t catch that. Try again.');
      default: setState(() => _answer = 'Sorry, I can’t do that yet. Try one of the examples below.');
    }
  }

  @override
  void dispose() { _stt?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final hh = s.profile.householdIdFor(widget.user['id'] as String);
    final entitled = VoiceGate.entitled(s, widget.user);
    return Scaffold(
      appBar: wamAppBar(context, leading: IconButton(tooltip: 'Back to home', icon: const Icon(Icons.arrow_back), onPressed: () => s.router.go('home', replace: true)),
          title: const Text('Voice commands', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.all(20), children: [ContentWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!entitled) ...[
          const Text('Voice commands are part of a higher WAMWins tier. Everything they do can also be done by tapping in WAMWins Basic.'),
          const SizedBox(height: 12),
          TierLockedFeatures(householdId: hh, features: voiceLocked),
        ] else ...[
          Center(child: Semantics(button: true, label: 'Tap and say one command', child: InkResponse(onTap: _listening ? null : _listen, child: CircleAvatar(radius: 48,
              backgroundColor: _listening ? p.danger : Brand.blue, child: const Icon(Icons.mic, size: 44, color: Colors.white))))),
          const SizedBox(height: 12),
          Text(_listening ? 'Listening…' : 'Tap the microphone and say one command. It stops listening by itself.', textAlign: TextAlign.center, style: TextStyle(color: p.text2)),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(_heard.isEmpty ? '' : '“$_heard”', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          Semantics(liveRegion: true, child: Text(_answer, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w500))),
          const SizedBox(height: 24),
          Text('Things you can say', style: Theme.of(context).textTheme.titleLarge),
          for (final x in const ['Open inventory', 'What can we cook for dinner?', 'Do we have eggs?', 'Add 2 pounds of chicken breast', 'Open Privacy & sharing']) Text('•  “$x”'),
          const SizedBox(height: 16),
          Text('WAMWins keeps no recordings and no voiceprints. Voice never reads health details aloud. Turn voice off in Settings.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ]))]),
    );
  }
}
