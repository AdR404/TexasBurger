import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/services/app_auth_service.dart';
import 'package:texas_burger/services/user_role_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppAuthService authService;
  late UserRoleService roleService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = AppAuthService();
    roleService = UserRoleService();
    await authService.signOut();
  });

  tearDown(() async {
    await authService.signOut();
  });

  test('AppAuthService starts unauthenticated', () {
    expect(authService.isAuthenticated, isFalse);
    expect(authService.currentUser, isNull);
    expect(roleService.isUser, isTrue);
  });

  test('Rejects unknown credentials when Supabase Auth is unavailable', () async {
    final result = await authService.signIn(
      email: 'desconocido@correo.com',
      password: 'passwordIncorrecto',
    );

    expect(result.success, isFalse);
    expect(result.user, isNull);
    expect(authService.isAuthenticated, isFalse);
  });

  test('Rejects previous demo credentials', () async {
    for (final credentials in [
      ('admin@texasburger.com', 'admin123'),
      ('admin', 'admin'),
      ('cajero@texasburger.com', 'caja123'),
      ('cajero', 'caja'),
    ]) {
      final result = await authService.signIn(
        email: credentials.$1,
        password: credentials.$2,
      );
      expect(result.success, isFalse);
      expect(result.user, isNull);
    }
    expect(authService.isAuthenticated, isFalse);
    expect(roleService.isUser, isTrue);
  });

  test('Debug test accounts authenticate locally without persistence', () async {
    final cashier = await authService.signIn(
      email: AppAuthService.debugCashierEmail,
      password: AppAuthService.debugCashierPassword,
    );
    expect(cashier.success, isTrue);
    expect(cashier.user!.role, 'cajero');
    expect(roleService.isUser, isTrue);
    await authService.signOut();

    final admin = await authService.signIn(
      email: AppAuthService.debugAdminEmail,
      password: AppAuthService.debugAdminPassword,
    );
    expect(admin.success, isTrue);
    expect(admin.user!.role, 'admin');
    expect(roleService.isAdmin, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('texas_auth_current_user_v1'), isFalse);
    expect(prefs.containsKey('texas_auth_registered_users_v1'), isFalse);
  });

  test('Password reset validates email and never reports simulated success', () async {
    final fail = await authService.sendPasswordResetEmail(email: 'correo-falso');
    expect(fail.success, isFalse);

    final ok = await authService.sendPasswordResetEmail(email: 'admin@texasburger.com');
    expect(ok.success, isFalse);
    expect(ok.message, contains('no está disponible'));
  });

  test('SignOut resets the local role without a cached mock session', () async {
    roleService.setAuthenticatedRole('admin');
    expect(roleService.isAdmin, isTrue);
    await authService.signOut();
    expect(authService.isAuthenticated, isFalse);
    expect(authService.currentUser, isNull);
    expect(roleService.isUser, isTrue);
  });

  test('Clears legacy locally stored demo sessions and accounts', () async {
    SharedPreferences.setMockInitialValues({
      'texas_auth_current_user_v1': 'legacy demo session',
      'texas_auth_registered_users_v1': 'legacy demo accounts',
    });
    await authService.init();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('texas_auth_current_user_v1'), isFalse);
    expect(prefs.containsKey('texas_auth_registered_users_v1'), isFalse);
    expect(authService.isAuthenticated, isFalse);
  });
}

