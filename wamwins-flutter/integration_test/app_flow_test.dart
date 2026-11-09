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
    await pumpUntil(t, find.text('Create Account'));
    expect(find.text('WAMWins is installed on this device'), findsOneWidget);

    await tapText(t, 'Create Account');
    await pumpUntil(t, find.text('Create your account'));
    await t.enterText(find.widgetWithText(TextField, 'Your name'), 'Ana Santos');
    await t.enterText(find.widgetWithText(TextField, 'Email'), 'ana@example.com');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'Mango-Sunset-2026!');
    await t.tap(find.byType(Checkbox).first);
    await tapText(t, 'Create account');
    await pumpUntil(t, find.text('About You'));
    expect(find.text('Step 1 of 7: About You'), findsOneWidget);

    await tapText(t, 'Mother');
    await tapText(t, 'Continue');                                   // Module 1
    await pumpUntil(t, find.text('Health Profiles'));
    await tapText(t, 'No');
    await tapText(t, 'Continue');                                   // Module 2
    await pumpUntil(t, find.text('Kitchens & Storages'));
    await tapText(t, 'Barn Kitchen');
    expect(find.text('Other Kitchen'), findsNothing);
    await tapText(t, 'Continue');                                   // Module 3
    await pumpUntil(t, find.text('Kitchen Appliances'));
    await tapText(t, 'Cooktop');
    await tapText(t, 'Continue');                                   // Module 4
    await pumpUntil(t, find.text('Utensils & Kitchenware'));
    await tapText(t, 'Skip for now');                               // Module 5
    await pumpUntil(t, find.text('Food Inventories'));
    await t.enterText(find.widgetWithText(TextField, 'Add food'), 'ri');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('White rice'), findsNothing, reason: 'no suggestions below 3 characters');
    await t.enterText(find.widgetWithText(TextField, 'Add food'), 'ric');
    await pumpUntil(t, find.text('White rice'));
    await tapText(t, 'White rice');
    await tapText(t, 'Continue');                                   // Module 6
    await pumpUntil(t, find.text('Review My Household Entries'));
    await tapText(t, 'Save Entries');
    await pumpUntil(t, find.text('Here is what WAMWins knows about your kitchen stuff!'));
    expect(find.text('Storage units'), findsOneWidget);

    await t.tap(find.byTooltip('Settings'));
    await pumpUntil(t, find.text('Sign out'));
    await tapText(t, 'Sign out');
    await pumpUntil(t, find.text('Log In'));
    await tapText(t, 'Log In');
    await pumpUntil(t, find.text('Welcome back'));
    await t.enterText(find.widgetWithText(TextField, 'Email'), 'ana@example.com');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'wrong-password-123');
    await tapText(t, 'Log in');
    await pumpUntil(t, find.text('Email or password is incorrect.'));
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'Mango-Sunset-2026!');
    await tapText(t, 'Log in');
    await pumpUntil(t, find.text('Here is what WAMWins knows about your kitchen stuff!'));

    db.close();
    await File(path).delete();
  });
}
