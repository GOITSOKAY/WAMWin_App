// Release gate (docs/CLIENT_CONFORMANCE.md): the full entry-module journey on a real device or emulator.
// Run: flutter test integration_test/app_flow_test.dart -d <device>   (phone and tablet)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wamwins/app/app.dart';
import 'package:wamwins/app/scope.dart';
import 'package:wamwins/core/db.dart';
import 'package:wamwins/security/secure_store.dart';

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $f');
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('register -> five profiling steps -> home -> sign out -> wrong password -> log in', (t) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/wamwins-it-${DateTime.now().microsecondsSinceEpoch}.db';
    final db = await AppDb.open(path: path);
    await t.pumpWidget(WamWinsApp(services: AppServices(db: db, secure: MemorySecureStore())));
    await pumpUntil(t, find.text('Create account'));

    await tapText(t, 'Create account');
    await pumpUntil(t, find.text('Create your account'));
    await t.enterText(find.widgetWithText(TextField, 'Your name'), 'Ana Santos');
    await t.enterText(find.widgetWithText(TextField, 'Email'), 'ana@example.com');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'Mango-Sunset-2026!');
    await t.tap(find.byType(Checkbox).first);
    await tapText(t, 'Create account');
    await pumpUntil(t, find.text('About you'));

    await tapText(t, 'Continue');                                   // about
    await pumpUntil(t, find.text('Your household'));
    await t.tap(find.bySemanticsLabel(RegExp('More Outdoor kitchen')));
    await tapText(t, 'Continue');                                   // household
    await pumpUntil(t, find.text('Kitchens & equipment'));
    await tapText(t, 'Stovetop / burner');
    await tapText(t, 'Continue');                                   // kitchens
    await pumpUntil(t, find.text('Family & health'));
    await tapText(t, 'Continue');                                   // family
    await pumpUntil(t, find.text('Food on hand'));
    await t.enterText(find.widgetWithText(TextField, 'Add food'), 'rice');
    await pumpUntil(t, find.text('White rice'));
    await tapText(t, 'White rice');
    await tapText(t, 'Continue');                                   // food
    await pumpUntil(t, find.text('Review your household'));
    await tapText(t, 'Create my household');
    await pumpUntil(t, find.textContaining('Ana'));
    expect(find.textContaining('is set up'), findsOneWidget);
    expect(find.text('Storage units'), findsOneWidget);

    await t.tap(find.byTooltip('Settings'));
    await pumpUntil(t, find.text('Sign out'));
    await tapText(t, 'Sign out');
    await pumpUntil(t, find.text('Log in'));
    await tapText(t, 'Log in');
    await pumpUntil(t, find.text('Welcome back'));
    await t.enterText(find.widgetWithText(TextField, 'Email'), 'ana@example.com');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'wrong-password-123');
    await tapText(t, 'Log in');
    await pumpUntil(t, find.text('Email or password is incorrect.'));
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'Mango-Sunset-2026!');
    await tapText(t, 'Log in');
    await pumpUntil(t, find.textContaining('is set up'));

    db.close();
    await File(path).delete();
  });
}
