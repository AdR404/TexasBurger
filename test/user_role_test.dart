import 'package:flutter_test/flutter_test.dart';
import 'package:texas_burger/services/user_role_service.dart';
import 'support/auth_fixtures.dart';

void main() {
  test('UserRoleService derives admin from an authenticated profile only', () {
    final service = UserRoleService();
    clearTestSession();

    // Default debe ser usuario
    expect(service.isUser, isTrue);
    expect(service.isAdmin, isFalse);
    expect(service.currentRole, equals(UserRole.user));

    expect(service.loginAdmin('admin', 'admin'), isFalse);
    expect(service.isUser, isTrue);

    authenticateAsTestUser();
    expect(service.isAdmin, isTrue);
    expect(service.isUser, isFalse);

    clearTestSession();
    expect(service.isUser, isTrue);
    expect(service.isAdmin, isFalse);
  });
}
