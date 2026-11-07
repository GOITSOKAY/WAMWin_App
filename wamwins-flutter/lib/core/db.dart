import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

typedef DbRow = Map<String, Object?>;

/// The on-device WAMWins database.
///
/// Rule B1 (docs/CLIENT_CONFORMANCE.md): it is built ONLY from the shared SQLite migration files,
/// bundled unchanged in assets/db/migrations (see tool/sync_shared.mjs), and recorded in the same
/// `schema_migration_history` table as every other client. The triggers inside those files enforce
/// the inventory ledger, append-only history, module states and tier guarantees on this device too.
/// SQLite is bundled by sqlite3_flutter_libs (the shared schema needs SQLite >= 3.37).
class AppDb {
  AppDb._(this._db, this.path);
  final Database _db;
  final String? path;
  int _depth = 0;

  static Future<AppDb> open({String? path, AssetBundle? bundle}) async {
    if (!kIsTestPath(path) && Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final dbPath = path ?? p.join((await getApplicationSupportDirectory()).path, 'wamwins.db');
    final db = dbPath == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(dbPath);
    db.execute('PRAGMA foreign_keys = ON;');
    if (dbPath != ':memory:') db.execute('PRAGMA journal_mode = WAL;');
    final version = db.select('SELECT sqlite_version() AS v').first['v'] as String;
    final parts = version.split('.').map(int.parse).toList();
    if (parts[0] < 3 || (parts[0] == 3 && parts[1] < 37)) {
      db.dispose();
      throw StateError('SQLite $version is too old for WAMWins (3.37 or newer is required).');
    }
    final app = AppDb._(db, dbPath == ':memory:' ? null : dbPath);
    await app._migrate(bundle ?? rootBundle);
    return app;
  }

  static bool kIsTestPath(String? path) => path == ':memory:';

  Future<void> _migrate(AssetBundle bundle) async {
    _db.execute('CREATE TABLE IF NOT EXISTS schema_migration_history (migration_id TEXT PRIMARY KEY, scope TEXT NOT NULL, '
        "applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))) STRICT");
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final files = manifest.listAssets().where((a) => a.startsWith('assets/db/migrations/') && a.endsWith('.sql')).toList()..sort();
    final done = select('SELECT migration_id FROM schema_migration_history').map((r) => r['migration_id'] as String).toSet();
    for (final asset in files) {
      final id = p.basename(asset).replaceFirst('__', '/');      // "001_core__001_core.sql" -> "001_core/001_core.sql"
      if (done.contains(id)) continue;
      final sql = await bundle.loadString(asset, cache: false);
      transaction(() {
        _db.execute(sql);
        run('INSERT INTO schema_migration_history(migration_id, scope) VALUES (?, ?)', [id, 'BASE']);
      });
    }
  }

  /// Optional modules install their tables the first time they are entitled and used (additive only).
  Future<void> migrateModule(String dir, {AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final files = manifest.listAssets().where((a) => a.startsWith('assets/db/modules/${dir}__') && a.endsWith('.sql')).toList()..sort();
    for (final asset in files) {
      final id = 'modules/${p.basename(asset).replaceFirst('__', '/')}';
      if (first('SELECT 1 AS x FROM schema_migration_history WHERE migration_id = ?', [id]) != null) continue;
      final sql = await b.loadString(asset, cache: false);
      transaction(() {
        _db.execute(sql);
        run('INSERT INTO schema_migration_history(migration_id, scope) VALUES (?, ?)', [id, 'MODULE:$dir']);
      });
    }
  }

  List<DbRow> select(String sql, [List<Object?> params = const []]) =>
      [for (final r in _db.select(sql, params)) Map<String, Object?>.from(r)];
  DbRow? first(String sql, [List<Object?> params = const []]) {
    final rows = select(sql, params);
    return rows.isEmpty ? null : rows.first;
  }
  int count(String sql, [List<Object?> params = const []]) => (first(sql, params)?.values.first as int?) ?? 0;
  void run(String sql, [List<Object?> params = const []]) => _db.execute(sql, params);

  /// All-or-nothing unit of work (nested calls use savepoints).
  T transaction<T>(T Function() body) {
    final sp = 'sp_$_depth';
    _db.execute(_depth == 0 ? 'BEGIN IMMEDIATE' : 'SAVEPOINT $sp');
    _depth++;
    try {
      final result = body();
      _depth--;
      _db.execute(_depth == 0 ? 'COMMIT' : 'RELEASE $sp');
      return result;
    } catch (_) {
      _depth--;
      _db.execute(_depth == 0 ? 'ROLLBACK' : 'ROLLBACK TO $sp; RELEASE $sp');
      rethrow;
    }
  }

  void close() => _db.dispose();

  /// "Delete all WAMWins data on this device".
  Future<void> deleteFile() async {
    close();
    if (path == null) return;
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
  }
}
