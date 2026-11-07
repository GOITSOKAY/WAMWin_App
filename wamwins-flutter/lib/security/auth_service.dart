import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/db.dart';
import '../core/ids.dart';
import 'crypto.dart';
import 'secure_store.dart';

class AuthException implements Exception {
  AuthException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class PasswordStrength {
  const PasswordStrength(this.score, this.message);
  final int score;
  final String message;
}

const _common = ['password', '1234567890', 'qwertyuiop', 'iloveyou', 'password123', 'wamwins', 'letmein', 'welcome123', 'abc1234567', '0987654321'];
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
String normalizeEmail(String e) => e.trim().toLowerCase();
bool validEmail(String e) => _emailRe.hasMatch(normalizeEmail(e));

/// Identical rules and messages to the web client (frontend/www/js/security/auth.js).
PasswordStrength passwordStrength(String pw, [List<String> context = const []]) {
  if (pw.isEmpty) return const PasswordStrength(0, 'Use at least 10 characters.');
  final lower = pw.toLowerCase();
  if (pw.length < 10) {
    final n = 10 - pw.length;
    return PasswordStrength(1, 'Add $n more character${n == 1 ? '' : 's'}.');
  }
  if (_common.any(lower.contains) || context.where((c) => c.length > 2).any((c) => lower.contains(c.toLowerCase()))) {
    return const PasswordStrength(1, 'Avoid common words, your name or your email.');
  }
  final kinds = [RegExp('[a-z]'), RegExp('[A-Z]'), RegExp(r'\d'), RegExp('[^A-Za-z0-9]')].where((r) => r.hasMatch(pw)).length;
  final score = ((pw.length >= 14 ? 2 : 1) + (kinds >= 3 ? 2 : kinds == 2 ? 1 : 0)).clamp(0, 4).toInt();
  return PasswordStrength(score, score >= 3 ? 'Strong password.' : score == 2 ? 'Good. A longer phrase is even stronger.' : 'Mix letters with numbers or symbols.');
}

/// Device-local accounts (offline-first) until WAM Digital cloud sign-in is connected: PBKDF2-SHA-256
/// 310,000 iterations with a per-user salt (computed off the UI thread), constant-time check,
/// progressive lockout, and a session token kept in the OS keystore (only its hash in the database).
/// A cloud adapter will implement the same methods; screens do not change.
class AuthService {
  AuthService(this.db, this.secure);
  final AppDb db;
  final SecureStore secure;
  static const iterations = 310000;
  static const _sessionKey = 'wamwins.session';

  static Future<List<int>> _hash(String password, List<int> salt, int iterations) =>
      Isolate.run(() => pbkdf2Sha256(password, Uint8ListFrom(salt), iterations).toList());

  Future<String> register({required String name, required String email, required String password, required Map<String, bool> consents}) async {
    final mail = normalizeEmail(email);
    if (name.trim().isEmpty) throw AuthException('NAME', 'Enter your name.');
    if (!validEmail(mail)) throw AuthException('EMAIL', 'Enter a valid email address, like name@example.com.');
    final s = passwordStrength(password, [name, mail.split('@').first]);
    if (s.score < 2) throw AuthException('PASSWORD', s.message);
    if (consents['TERMS'] != true || consents['PRIVACY_POLICY'] != true) {
      throw AuthException('CONSENT', 'Please accept the Terms of Use and Privacy Policy to create an account.');
    }
    if (db.first('SELECT 1 AS x FROM local_auth_identity WHERE provider_subject = ?', [mail]) != null) {
      throw AuthException('EXISTS', 'An account with this email already exists on this device. Log in instead.');
    }
    final salt = randomBytes(16);
    final hash = await _hash(password, salt, iterations);
    final userId = newId();
    db.transaction(() {
      db.run("INSERT INTO user_account(id, email, display_name, locale, timezone) VALUES (?, ?, ?, 'en', ?)",
          [userId, mail, name.trim(), DateTime.now().timeZoneName]);
      db.run('INSERT INTO local_auth_identity(id, user_id, provider_subject, secret_hash, salt, iterations) VALUES (?, ?, ?, ?, ?, ?)',
          [newId(), userId, mail, base64.encode(hash), base64.encode(salt), iterations]);
      consents.forEach((type, granted) => db.run(
          "INSERT INTO consent_record(id, user_id, consent_type, document_version, granted) VALUES (?, ?, ?, '1', ?)",
          [newId(), userId, type, granted ? 1 : 0]));
    });
    await _startSession(userId, remember: true);
    return userId;
  }

  Future<String> login({required String email, required String password, bool remember = true}) async {
    final mail = normalizeEmail(email);
    final generic = AuthException('CREDENTIALS', 'Email or password is incorrect.');
    final ident = db.first('SELECT * FROM local_auth_identity WHERE provider_subject = ?', [mail]);
    if (ident == null) {
      await _hash(password.isEmpty ? 'x' : password, List<int>.filled(16, 0), iterations);   // same timing as a real check
      throw generic;
    }
    final lockedUntil = ident['locked_until'] as String?;
    if (lockedUntil != null && DateTime.parse(lockedUntil).isAfter(DateTime.now().toUtc())) {
      final secs = DateTime.parse(lockedUntil).difference(DateTime.now().toUtc()).inSeconds + 1;
      throw AuthException('LOCKED', 'Too many attempts. Try again in $secs second${secs == 1 ? '' : 's'}.');
    }
    final hash = await _hash(password, base64.decode(ident['salt'] as String), ident['iterations'] as int);
    if (!constantTimeEquals(hash, base64.decode(ident['secret_hash'] as String))) {
      final fails = (ident['failed_attempts'] as int) + 1;
      final lock = fails >= 5 ? DateTime.now().toUtc().add(Duration(seconds: 30 * (1 << (fails - 5).clamp(0, 6).toInt()))).toIso8601String() : null;
      db.run('UPDATE local_auth_identity SET failed_attempts = ?, locked_until = ? WHERE id = ?', [fails, lock, ident['id']]);
      throw generic;
    }
    db.run('UPDATE local_auth_identity SET failed_attempts = 0, locked_until = NULL, last_used_at = ? WHERE id = ?', [nowIso(), ident['id']]);
    await _startSession(ident['user_id'] as String, remember: remember);
    return ident['user_id'] as String;
  }

  Future<void> _startSession(String userId, {required bool remember}) async {
    final token = hexOf(randomBytes(32));
    final expires = DateTime.now().toUtc().add(Duration(days: remember ? 30 : 1)).toIso8601String();
    db.run('INSERT INTO local_session(token_hash, user_id, expires_at) VALUES (?, ?, ?)', [sha256Hex(token), userId, expires]);
    await secure.write(_sessionKey, token);
  }

  Future<DbRow?> currentUser() async {
    final token = await secure.read(_sessionKey);
    if (token == null) return null;
    final s = db.first('SELECT * FROM local_session WHERE token_hash = ?', [sha256Hex(token)]);
    if (s == null || DateTime.parse(s['expires_at'] as String).isBefore(DateTime.now().toUtc())) {
      await logout();
      return null;
    }
    return db.first('SELECT * FROM user_account WHERE id = ?', [s['user_id']]);
  }

  Future<void> logout() async {
    final token = await secure.read(_sessionKey);
    await secure.delete(_sessionKey);
    if (token != null) db.run('DELETE FROM local_session WHERE token_hash = ?', [sha256Hex(token)]);
  }
}

// ignore: non_constant_identifier_names
Uint8List Uint8ListFrom(List<int> l) => Uint8List.fromList(l);
