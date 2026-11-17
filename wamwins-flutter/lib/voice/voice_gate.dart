import '../app/scope.dart';
import '../core/db.dart';
import '../privacy/privacy_service.dart';

/// Voice commands gate (tiny; never imports the speech engine). VOICE_COMMANDS is a higher-tier capability:
/// DISABLED in WAMWins Basic, so only a locked notice is shown and voice_screen.dart / speech_to_text never start.
class VoiceGate {
  static const capability = 'VOICE_COMMANDS';
  static bool entitled(AppServices s, DbRow user) {
    final hh = s.profile.householdIdFor(user['id'] as String);
    return hh != null && s.capabilities.canUse(hh, capability);
  }
  static bool consented(AppServices s, DbRow user) => PrivacyService(s.db).hasConsent(user['id'] as String, capability);
  static bool showMic(AppServices s, DbRow user) => entitled(s, user) && consented(s, user);
}
