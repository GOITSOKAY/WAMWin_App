import 'package:flutter/material.dart';

import '../core/db.dart';
import '../inquiry/profile_store.dart';
import '../security/auth_service.dart';
import '../security/secure_store.dart';
import '../tier/capabilities.dart';
import 'router.dart';

/// App-wide services (no household data lives here - screens load what they need and release it).
class AppServices {
  AppServices({required this.db, required this.secure})
      : auth = AuthService(db, secure),
        capabilities = Capabilities(db),
        router = AppRouter() {
    profile = ProfileStore(db, capabilities);
    final saved = db.first("SELECT value FROM local_setting WHERE key = 'app.theme'")?['value'] as String?;
    themeMode.value = switch (saved) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
  }
  final AppDb db;
  final SecureStore secure;
  final AuthService auth;
  final Capabilities capabilities;
  final AppRouter router;
  late final ProfileStore profile;
  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  void setTheme(String v) {
    db.run("INSERT INTO local_setting(key, value) VALUES ('app.theme', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [v]);
    themeMode.value = switch (v) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
  }

  void toast(String message) => messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;
  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;
  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}
