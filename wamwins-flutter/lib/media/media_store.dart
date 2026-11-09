import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/db.dart';
import '../core/ids.dart';

/// Manual reference photos (ACTIVE in WAMWins Basic). Metadata in location_media; image bytes in media_blob (kept out of
/// the metadata rows). WAMWins Basic never interprets images - nothing here analyzes them.
class MediaStore {
  MediaStore(this.db);
  final AppDb db;

  static Future<Uint8List> thumbnail(Uint8List bytes, {int width = 320}) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      return bytes;
    }
  }

  Future<String> add({required String householdId, required String userId, required String locationKey, required Uint8List bytes, required String mime,
      String? title, String? caption}) async {
    final thumb = await thumbnail(bytes);
    final id = newId(), blob = newId(), thumbId = newId();
    db.transaction(() {
      db.run('INSERT INTO media_blob(id, household_id, mime_type, bytes) VALUES (?, ?, ?, ?)', [blob, householdId, mime, bytes]);
      db.run("INSERT INTO media_blob(id, household_id, mime_type, bytes) VALUES (?, ?, 'image/png', ?)", [thumbId, householdId, thumb]);
      db.run("INSERT INTO location_media(id, household_id, location_draft_key, media_type, blob_ref, thumbnail_ref, mime_type, byte_size, title, caption, uploaded_by_user_id, source_type) "
          "VALUES (?, ?, ?, 'IMAGE', ?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
          [id, householdId, locationKey, 'db:media_blob/$blob', 'db:media_blob/$thumbId', mime, bytes.length, title, caption, userId]);
    });
    return id;
  }

  List<DbRow> forLocation(String householdId, String locationKey) => db.select(
      'SELECT id, title, caption, blob_ref, thumbnail_ref, mime_type FROM location_media WHERE household_id = ? AND location_draft_key = ? AND active = 1 AND archived_at IS NULL ORDER BY created_at',
      [householdId, locationKey]);

  Uint8List? bytes(String ref) => db.first('SELECT bytes FROM media_blob WHERE id = ?', [ref.replaceFirst('db:media_blob/', '')])?['bytes'] as Uint8List?;

  void archive(String id) => db.run("UPDATE location_media SET active = 0, archived_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [id]);
}
