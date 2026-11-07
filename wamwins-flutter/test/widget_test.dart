// Brand components render as specified (also prevents `flutter create` from adding a default sample test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamwins/app/theme.dart';
import 'package:wamwins/ui/brand.dart';

void main() {
  testWidgets('WAMWins™ wordmark and title render with the trademark', (t) async {
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Builder(builder: (c) => Column(children: [
      const Wordmark(),
      tmTitle(c, 'Welcome to WAMWins', align: TextAlign.center),
    ])))));
    expect(find.bySemanticsLabel('WAMWins'), findsWidgets);
    expect(find.textContaining('Welcome to WAMWins'), findsOneWidget);
    expect(find.text('™'), findsNWidgets(2));
  });

  testWidgets('phones show the app icon, tablets the desktop logo', (t) async {
    Future<String> logoAt(Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: BrandLogo()))));
      final img = t.widget<Image>(find.byType(Image));
      return (img.image as AssetImage).assetName;
    }
    expect(await logoAt(const Size(390, 844)), 'assets/brand/app-icon.png');            // phone
    expect(await logoAt(const Size(844, 390)), 'assets/brand/app-icon.png');            // phone, landscape
    expect(await logoAt(const Size(820, 1180)), 'assets/brand/logo-desktop.png');       // tablet
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
