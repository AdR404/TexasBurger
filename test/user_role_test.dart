import 'package:flutter_test/flutter_test.dart';
import 'package:texas_burger/services/user_role_service.dart';

void main() {
  test('UserRoleService reflects an authenticated role and resets on sign out', () {
    final service = UserRoleService();

    // Default debe ser usuario
    expect(service.isUser, isTrue);
    expect(service.isAdmin, isFalse);
    expect(service.currentRole, equals(UserRole.user));

    service.setAuthenticatedRole('admin');
    expect(service.isAdmin, isTrue);
    expect(service.isUser, isFalse);

    // Cambiar de vuelta a usuario
    service.switchToUser();
    expect(service.isUser, isTrue);
    expect(service.isAdmin, isFalse);
  });
}
