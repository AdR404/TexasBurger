import 'package:flutter_test/flutter_test.dart';
import 'package:texas_burger/services/user_role_service.dart';

void main() {
  test('UserRoleService defaults to user and validates simulated credentials', () {
    final service = UserRoleService();

    // Default debe ser usuario
    expect(service.isUser, isTrue);
    expect(service.isAdmin, isFalse);
    expect(service.currentRole, equals(UserRole.user));

    // Fallar con credenciales incorrectas
    final fail = service.loginAdmin('user', '1234');
    expect(fail, isFalse);
    expect(service.isUser, isTrue);

    // Éxito con admin / admin
    final ok = service.loginAdmin('admin', 'admin');
    expect(ok, isTrue);
    expect(service.isAdmin, isTrue);
    expect(service.isUser, isFalse);

    // Cambiar de vuelta a usuario
    service.switchToUser();
    expect(service.isUser, isTrue);
    expect(service.isAdmin, isFalse);
  });
}
