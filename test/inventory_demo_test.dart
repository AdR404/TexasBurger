import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/data/inventory_demo_data.dart';
import 'package:texas_burger/screens/inventory_screen.dart';
import 'package:texas_burger/theme/app_theme.dart';
import 'package:texas_burger/widgets/inventory_lot_detail_sheet.dart';
import 'support/auth_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    authenticateAsTestUser();
  });
  tearDown(clearTestSession);

  testWidgets(
    'demo inventory enables local actions and labels simulated data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: InventoryScreen(onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mostrar datos simulados'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Agregar lote'));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Agregar lote'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Movimientos de inventario'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('demo lot detail identifies simulated stock', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: InventoryLotDetailSheet(
            ingredientName: 'Carne de res',
            lots: InventoryDemoData.create(),
            isDemo: true,
          ),
        ),
      ),
    );

    expect(
      find.text('MODO DEMOSTRACIÓN: existencias simuladas.'),
      findsOneWidget,
    );
  });
}
