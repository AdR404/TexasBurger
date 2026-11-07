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

  test('Fails on invalid credentials', () async {
    final result = await authService.signIn(
      email: 'desconocido@correo.com',
      password: 'passwordIncorrecto',
    );

    expect(result.success, isFalse);
    expect(result.user, isNull);
    expect(authService.isAuthenticated, isFalse);
  });

  test('Signs in successfully with Cajero demo credentials and updates role', () async {
    final result = await authService.signIn(
      email: 'cajero@texasburger.com',
      password: 'caja123',
    );

    expect(result.success, isTrue);
    expect(result.user, isNotNull);
    expect(result.user!.role, equals('cajero'));
    expect(authService.isAuthenticated, isTrue);
    expect(authService.isAdmin, isFalse);
    expect(roleService.isUser, isTrue);
  });

  test('Signs in successfully with Admin demo credentials and activates Admin role', () async {
    final result = await authService.signIn(
      email: 'admin@texasburger.com',
      password: 'admin123',
    );

    expect(result.success, isTrue);
    expect(result.user, isNotNull);
    expect(result.user!.role, equals('admin'));
    expect(authService.isAuthenticated, isTrue);
    expect(authService.isAdmin, isTrue);
    expect(roleService.isAdmin, isTrue);
  });

  test('Validates registerUser fields', () async {
    // Nombre vacío
    final failName = await authService.registerUser(
      name: '',
      email: 'nuevo@texasburger.com',
      password: 'password123',
      role: 'cajero',
    );
    expect(failName.success, isFalse);

    // Correo inválido
    final failEmail = await authService.registerUser(
      name: 'Carlos Pérez',
      email: 'correo-invalido',
      password: 'password123',
      role: 'cajero',
    );
    expect(failEmail.success, isFalse);

    // Contraseña corta
    final failPass = await authService.registerUser(
      name: 'Carlos Pérez',
      email: 'carlos@texasburger.com',
      password: '123',
      role: 'cajero',
    );
    expect(failPass.success, isFalse);
  });

  test('Registers new collaborator and can sign in with new credentials', () async {
    final registerRes = await authService.registerUser(
      name: 'Elena Morales',
      email: 'elena@texasburger.com',
      password: 'miPasswordSeguro123',
      role: 'cajero',
      branchId: 'perimetral_sur',
      branchName: 'Perimetral Sur',
    );

    expect(registerRes.success, isTrue);
    expect(registerRes.user!.name, equals('Elena Morales'));

    // Ahora intentamos iniciar sesión con la nueva cuenta
    final loginRes = await authService.signIn(
      email: 'elena@texasburger.com',
      password: 'miPasswordSeguro123',
    );

    expect(loginRes.success, isTrue);
    expect(loginRes.user!.name, equals('Elena Morales'));
    expect(loginRes.user!.role, equals('cajero'));
  });

  test('Password reset request validates email and succeeds', () async {
    final fail = await authService.sendPasswordResetEmail(email: 'correo-falso');
    expect(fail.success, isFalse);

    final ok = await authService.sendPasswordResetEmail(email: 'admin@texasburger.com');
    expect(ok.success, isTrue);
    expect(ok.message, isNotEmpty);
  });

  test('SignOut clears current user and resets role', () async {
    await authService.signIn(
      email: 'admin@texasburger.com',
      password: 'admin123',
    );
    expect(authService.isAuthenticated, isTrue);
    expect(roleService.isAdmin, isTrue);

    await authService.signOut();
    expect(authService.isAuthenticated, isFalse);
    expect(authService.currentUser, isNull);
    expect(roleService.isUser, isTrue);
  });
}

