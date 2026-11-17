import 'package:flutter_test/flutter_test.dart';
import 'package:wamwins/voice/voice_commands.dart';

// Same phrases and results as the web client (frontend/www/js/voice/engine.js).
void main() {
  test('voice commands parse to the same intents as the web client', () {
    expect(parseCommand('add 2 pounds of chicken breast').name, 'chicken breast');
    expect(parseCommand('add 2 pounds of chicken breast').quantity, 2);
    expect(parseCommand('Add eggs').name, 'eggs');
    expect(parseCommand('What can we cook for dinner?').slot, 'DINNER');
    expect(parseCommand('do we have milk').kind, 'STOCK');
    expect(parseCommand('how many eggs do we have').name, 'eggs');
    expect(parseCommand('open inventory').route, 'inventory');
    expect(parseCommand('sing a song').kind, 'UNKNOWN');
  });
}
