import 'package:flutter_test/flutter_test.dart';
import 'package:wamwins/privacy/privacy_service.dart';

// Person-level access rule (same as web privacy/access.js and PostgreSQL privacy.relation in V028).
void main() {
  final now = DateTime.utc(2026, 11, 16, 12);
  final owner = {'role_code': 'OWNER', 'status': 'ACTIVE'}, member = {'role_code': 'MEMBER', 'status': 'ACTIVE'};
  final ben = {'id': 'ben', 'linked_user_id': null, 'age_band': 'CHILD'};
  final carl = {'id': 'carl', 'linked_user_id': 'u-carl', 'age_band': 'ADULT'};
  final grant = {'subject_member_id': 'ben', 'grantee_user_id': 'u-dee', 'categories': '["ALLERGIES"]', 'access_level': 'VIEW',
    'starts_at': '2026-11-16T00:00:00Z', 'expires_at': '2026-11-17T00:00:00Z', 'revoked_at': null};
  String? rel(String uid, Map<String, Object?>? m, Map<String, Object?> who, {String? cat, DateTime? at, bool write = false}) =>
      PrivacyService.relation(userId: uid, membership: m, member: who, grants: [grant], category: cat, now: at ?? now, write: write);

  test('owner is guardian of a child, not of another adult with an account', () {
    expect(rel('u-ana', owner, ben), 'GUARDIAN');
    expect(rel('u-ana', owner, carl), isNull);
    expect(rel('u-carl', member, carl), 'SELF');
  });
  test('grant: only the granted person and category, view only, until it expires', () {
    expect(rel('u-dee', member, ben, cat: 'ALLERGIES'), 'GRANT');
    expect(rel('u-dee', member, ben, cat: 'DIETS'), isNull);
    expect(rel('u-dee', member, carl, cat: 'ALLERGIES'), isNull);
    expect(rel('u-dee', member, ben, cat: 'ALLERGIES', write: true), isNull);
    expect(rel('u-dee', member, ben, cat: 'ALLERGIES', at: DateTime.utc(2026, 11, 18)), isNull);
  });
}
