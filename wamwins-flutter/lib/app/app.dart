import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/db.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/match_screen.dart';
import '../screens/register_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/setup/setup_screen.dart';
import '../screens/welcome_screen.dart';
import '../ui/brand.dart';
import 'scope.dart';
import 'theme.dart';

class WamWinsApp extends StatelessWidget {
  const WamWinsApp({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => AppScope(
        services: services,
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: services.themeMode,
          builder: (_, mode, __) => MaterialApp(
            title: 'WAMWins',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: services.messengerKey,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: mode,
            home: const RootView(),
          ),
        ),
      );
}

/// Entry module: decides which screen to show (same guards as the web client).
///   no session          -> welcome / login / register
///   profiling not done  -> setup/<saved step>
///   done                -> home
/// Each screen is built only while shown. A screen that fails shows "Try again" - never a blank app.
class RootView extends StatefulWidget {
  const RootView({super.key});
  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> {
  Widget? _screen;
  DbRow? _user;
  Object? _error;
  int _resolveId = 0;
  late AppServices s;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    s = AppScope.of(context);
    s.router.removeListener(_resolve);
    s.router.addListener(_resolve);
    if (_screen == null && _error == null) _resolve();
  }

  @override
  void dispose() {
    s.router.removeListener(_resolve);
    super.dispose();
  }

  String _resume(DbRow user) {
    final id = user['id'] as String;
    return s.profile.isComplete(id) ? 'home' : 'setup/${s.profile.currentStep(id)}';
  }

  Future<void> _resolve() async {
    final id = ++_resolveId;
    try {
      final user = await s.auth.currentUser();
      if (id != _resolveId || !mounted) return;
      final name = s.router.name;
      const known = {'welcome', 'login', 'register', 'setup', 'home', 'settings', 'match', 'inventory'};
      if (user == null && !const {'welcome', 'login', 'register'}.contains(name)) return s.router.go('welcome', replace: true);
      if (user != null && (const {'welcome', 'login', 'register', ''}.contains(name) || !known.contains(name))) return s.router.go(_resume(user), replace: true);
      if (user != null && (name == 'home' || name == 'match' || name == 'inventory') && _resume(user) != 'home') return s.router.go(_resume(user), replace: true);
      // Capability gate: the screen exists only when the household's plan includes it (never "which tier?").
      if (user != null && name == 'inventory' && !s.capabilities.canUse(s.profile.householdIdFor(user['id'] as String)!, 'MANUAL_INVENTORY')) {
        return s.router.go('home', replace: true);
      }
      if (user != null && name == 'match' && !s.capabilities.canUse(s.profile.householdIdFor(user['id'] as String)!, 'MEAL_MATCHING')) {
        return s.router.go('home', replace: true);
      }
      setState(() {
        _user = user;
        _error = null;
        _screen = switch (name) {
          'welcome' => const WelcomeScreen(),
          'login' => const LoginScreen(),
          'register' => const RegisterScreen(),
          'setup' => SetupScreen(key: ValueKey('setup/${s.router.arg}'), user: user!, step: s.router.arg),
          'home' => HomeScreen(key: const ValueKey('home'), user: user!),
          'settings' => SettingsScreen(user: user!),
          'match' => MatchScreen(key: const ValueKey('match'), user: user!),
          'inventory' => InventoryScreen(key: const ValueKey('inventory'), user: user!),
          _ => const WelcomeScreen(),
        };
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null
        ? _ErrorView(message: '$_error', onRetry: () { setState(() => _error = null); _resolve(); })
        : _screen ?? const _Boot();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!s.router.back()) SystemNavigator.pop();
      },
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: KeyedSubtree(key: ValueKey('${s.router.current}|${_user?['id']}|${_error != null}'), child: body)),
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        BrandLogo(heroSize: 112), SizedBox(height: 16), Text('Loading WAMWins…'),
      ])));
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const BrandLogo(heroSize: 72),
        const SizedBox(height: 16),
        Text('This screen couldn’t open', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ])))));
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light),
      home: Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('WAMWins can’t start: $message', textAlign: TextAlign.center))))));
}
