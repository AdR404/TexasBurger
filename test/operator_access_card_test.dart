import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/services/app_auth_service.dart';
import 'package:texas_burger/services/operator_auth_service.dart';
import 'package:texas_burger/services/operator_session.dart';
import 'package:texas_burger/theme/app_theme.dart';
import 'package:texas_burger/widgets/operator_access_card.dart';
import 'support/auth_fixtures.dart';

class _FakeOperatorAuth implements OperatorAuthGateway {
  @override
  String? get currentOperatorId => 'test-admin';

  @override
  String? get validOperatorId => 'test-admin';

  @override
  String? get email => 'admin@test.texasburger.invalid';

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> verifySession() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OperatorSession session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authenticateAsTestUser();
    session = OperatorSession(
      _FakeOperatorAuth(),
      await SharedPreferences.getInstance(),
      projectId: 'test-project',
    );
    await session.initialize();
  });

  tearDown(() {
    session.dispose();
    clearTestSession();
  });

  testWidgets('shows account permissions without displaying technical IDs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ListView(children: [OperatorAccessCard(session: session)]),
        ),
      ),
    );

    expect(find.text('Conectado'), findsNWidgets(2));
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('admin@test.texasburger.invalid'), findsOneWidget);
    expect(find.text('Autorizado'), findsOneWidget);
    expect(find.text('Activos'), findsOneWidget);
    expect(find.text('Supabase'), findsNothing);
    expect(find.text('test-admin'), findsNothing);
    expect(find.text('Comprobar conexión y permisos'), findsOneWidget);
    expect(find.text('Cerrar sesión en este equipo'), findsOneWidget);
  });

  testWidgets('confirms that signing out only affects this device', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ListView(children: [OperatorAccessCard(session: session)]),
        ),
      ),
    );

    await tester.tap(find.text('Cerrar sesión en este equipo'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Esta acción cerrará tu sesión solo en este dispositivo. '
        'No afectará tu sesión en otros dispositivos.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(AppAuthService().currentUser, isNotNull);

    await tester.tap(find.text('Cerrar sesión en este equipo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(AppAuthService().currentUser, isNull);
  });
}
