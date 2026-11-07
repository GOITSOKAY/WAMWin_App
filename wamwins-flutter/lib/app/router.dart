import 'package:flutter/foundation.dart';

/// Path-based navigation with the same routes as the web client:
/// welcome, login, register, setup/<step>, home, settings. One screen is alive at a time.
class AppRouter extends ChangeNotifier {
  final List<String> _stack = [''];
  String get current => _stack.last;
  String get name => current.split('/').first;
  String get arg => current.contains('/') ? current.split('/')[1] : '';
  static const publicRoutes = {'welcome', 'login', 'register'};

  void go(String path, {bool replace = false}) {
    if (replace) {
      _stack[_stack.length - 1] = path;
    } else {
      _stack.add(path);
    }
    notifyListeners();
  }

  /// Android back button: returns false when there is nowhere to go back to (the app then closes).
  bool back() {
    if (_stack.length <= 1) return false;
    _stack.removeLast();
    notifyListeners();
    return true;
  }

  void reset(String path) {
    _stack..clear()..add(path);
    notifyListeners();
  }
}
