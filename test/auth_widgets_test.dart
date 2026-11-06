import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  testWidgets('LoginScreen shows quick test accounts only in debug', (tester) async {
    await tester.pumpWidget(buildTestable(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar Sesión'), findsWidgets);
    expect(find.text('Punto de Venta y Control Operativo'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(
      find.text('Cuentas locales de prueba (solo debug)'),
      kDebugMode ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('Admin de prueba'),
      kDebugMode ? findsOneWidget : findsNothing,
    );

    if (kDebugMode) {
      await tester.ensureVisible(find.text('Admin de prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin de prueba'));
      await tester.pumpAndSettle();
      final emailField = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(emailField.controller!.text, AppAuthService.debugAdminEmail);
    }
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

}

