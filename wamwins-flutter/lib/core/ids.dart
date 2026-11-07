import 'package:uuid/uuid.dart';

const _uuid = Uuid();
/// Client-generated UUIDs: records can be created offline and synced idempotently.
String newId() => _uuid.v4();
String nowIso() => DateTime.now().toUtc().toIso8601String();
String todayIso() => DateTime.now().toIso8601String().substring(0, 10);
String addDaysIso(String isoDay, int days) => DateTime.parse('${isoDay}T00:00:00Z').add(Duration(days: days)).toIso8601String().substring(0, 10);
