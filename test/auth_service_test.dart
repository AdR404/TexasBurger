import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/services/app_auth_service.dart';
import 'package:texas_burger/services/user_role_service.dart';
import 'support/auth_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppAuthService authService;
  late UserRoleService roleService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = AppAuthService();
    roleService = UserRoleService();
    clearTestSession();
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

  test('rejects credentials without a configured Supabase session', () async {
    final result = await authService.signIn(
      email: 'desconocido@correo.com',
      password: 'passwordIncorrecto',
    );
    final legacyAdmin = await authService.signIn(
      email: 'admin@texasburger.com',
      password: 'admin123',
    );

    expect(result.success, isFalse);
    expect(legacyAdmin.success, isFalse);
    expect(authService.isAuthenticated, isFalse);
    expect(roleService.isAdmin, isFalse);
  });

  test('registration requires an authenticated administrator', () async {
    final result = await authService.registerUser(
      name: 'Elena Morales',
      email: 'elena@texasburger.com',
      password: 'miPasswordSeguro123',
      role: 'cajero',
      branchId: 'perimetral_sur',
      branchName: 'Perimetral Sur',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('administrativa'));
  });

  test('password recovery requires a configured Supabase client', () async {
    final result = await authService.sendPasswordResetEmail(
      email: 'admin@texasburger.com',
    );

    expect(result.success, isFalse);
  });

  test('verified session determines role and signOut clears it', () async {
    authenticateAsTestUser();
    expect(authService.isAuthenticated, isTrue);
    expect(authService.isAdmin, isTrue);
    expect(roleService.isAdmin, isTrue);

    await authService.signOut();
    expect(authService.isAuthenticated, isFalse);
    expect(authService.currentUser, isNull);
    expect(roleService.isUser, isTrue);
  });
}
