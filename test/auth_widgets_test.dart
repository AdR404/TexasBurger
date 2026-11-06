import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/screens/auth/admin_register_user_screen.dart';
import 'package:texas_burger/screens/auth/forgot_password_screen.dart';
import 'package:texas_burger/screens/auth/login_screen.dart';
import 'package:texas_burger/services/app_auth_service.dart';
import 'package:texas_burger/services/user_role_service.dart';
import 'package:texas_burger/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserRoleService().switchToUser();
  });

  Widget buildTestable(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: child,
    );
  }

  testWidgets('LoginScreen renders fields, buttons, and demo chips', (tester) async {
    await tester.pumpWidget(buildTestable(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar Sesión'), findsWidgets);
    expect(find.text('Punto de Venta y Control Operativo'), findsOneWidget);
    expect(find.text('Correo o Usuario'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(find.text('Admin (demo)'), findsOneWidget);
    expect(find.text('Cajero (demo)'), findsOneWidget);

    // Tapping demo chip fills inputs
    final adminChip = find.text('Admin (demo)');
    await tester.ensureVisible(adminChip);
    await tester.pumpAndSettle();
    await tester.tap(adminChip);
    await tester.pumpAndSettle();

    expect(find.text('admin@texasburger.com'), findsOneWidget);
  });

  testWidgets('ForgotPasswordScreen renders input and validation', (tester) async {
    await tester.pumpWidget(buildTestable(const ForgotPasswordScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Recuperación de Acceso'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(find.text('Enviar enlace de recuperación'), findsOneWidget);

    // Intentar enviar sin correo
    await tester.tap(find.text('Enviar enlace de recuperación'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa tu correo electrónico.'), findsOneWidget);
  });

  testWidgets('AdminRegisterUserScreen shows restricted view when user is not admin', (tester) async {
    UserRoleService().switchToUser();
    await AppAuthService().signOut();

    await tester.pumpWidget(buildTestable(const AdminRegisterUserScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Acceso Restringido'), findsOneWidget);
  });

  testWidgets('AdminRegisterUserScreen renders registration form when user is admin', (tester) async {
    UserRoleService().loginAdmin('admin', 'admin');

    await tester.pumpWidget(buildTestable(const AdminRegisterUserScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Registro de Usuarios'), findsOneWidget);
    expect(find.text('Nombre Completo'), findsOneWidget);
    expect(find.text('Correo Electrónico de Acceso'), findsOneWidget);
    expect(find.text('Rol Asignado'), findsOneWidget);
    expect(find.text('Sucursal'), findsOneWidget);
    expect(find.text('Contraseña Inicial'), findsOneWidget);
    expect(find.text('Confirmar Contraseña'), findsOneWidget);
    expect(find.text('Registrar Colaborador'), findsOneWidget);
  });
}

