import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/data/staff_catalog.dart';
import 'package:texas_burger/models/discount_code.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/screens/quick_sale_screen.dart';
import 'package:texas_burger/screens/settings_screen.dart';
import 'package:texas_burger/services/caja_service.dart';
import 'package:texas_burger/services/discount_code_service.dart';
import 'package:texas_burger/services/product_service.dart';
import 'package:texas_burger/services/sales_service.dart';
import 'package:texas_burger/services/user_role_service.dart';
import 'package:texas_burger/theme/app_theme.dart';
import 'package:texas_burger/widgets/cart_bottom_sheet.dart';
import 'package:texas_burger/widgets/discount_codes_dialog.dart';
import 'package:texas_burger/widgets/ticket_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final product = Producto(
    id: 'test_116',
    name: 'PRODUCTO PRUEBA',
    description: '',
    price: 116,
    category: 'Bebidas',
  );
  final roles = UserRoleService();
  final discounts = DiscountCodeService();
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  setUpAll(() async {
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((p) => p['name'] == 'flutter');
    final root = configFile.uri.resolve('${flutter['rootUri']}/');
    final font = File.fromUri(
      root.resolve(
        '../../bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ),
    );
    await (FontLoader(
      'Roboto',
    )..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)))).load();
    SharedPreferences.setMockInitialValues({
      'texas_products': jsonEncode([product.toJson()]),
    });
    await discounts.init();
    await ProductService().init();
    await SalesService().init();
    await CajaService().init();
    await CajaService().updateSaleContext(
      StaffCatalog.selection('norte', 'demo_sofia_reyes'),
    );
  });
  setUp(roles.switchToUser);
  tearDown(roles.switchToUser);

  testWidgets(
    'coupon administration is protected, scrolls and revokes stale actions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: DiscountCodesDialog()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Guardar código'), findsNothing);
      expect(
        find.text('Disponible solo en modo administrador.'),
        findsOneWidget,
      );
      roles.loginAdmin('admin', 'admin');
      await tester.pumpAndSettle();
      await tester.enterText(field('Código'), ' diez_ui ');
      await tester.enterText(
        field('Nombre de la promoción'),
        'Descuento del equipo',
      );
      await tester.enterText(field('Porcentaje'), '10');
      await tester.ensureVisible(find.text('Guardar código'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Guardar código'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(discounts.findActive('DIEZ_UI')!.value, 10);
      await tester.ensureVisible(find.byType(Switch).first);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch).first);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(discounts.findActive('DIEZ_UI'), isNull);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch).first);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(discounts.findActive('DIEZ_UI'), isNotNull);
      final staleDelete = tester
          .widget<IconButton>(
            find
                .byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Eliminar código',
                )
                .first,
          )
          .onPressed!;
      roles.switchToUser();
      staleDelete();
      await tester.pumpAndSettle();
      expect(discounts.findActive('DIEZ_UI'), isNotNull);
      expect(find.text('Guardar código'), findsNothing);
      roles.loginAdmin('admin', 'admin');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Eliminar código').first);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Eliminar código').first);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(discounts.findActive('DIEZ_UI'), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings exposes coupon administration only to admin', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Códigos de descuento'), findsNothing);
    roles.loginAdmin('admin', 'admin');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Administrar'));
    await tester.tap(find.text('Administrar'));
    await tester.pumpAndSettle();
    expect(find.byType(DiscountCodesDialog), findsOneWidget);
    roles.switchToUser();
    await tester.pumpAndSettle();
    expect(find.text('Guardar código'), findsNothing);
    expect(find.text('Disponible solo en modo administrador.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'user applies coupon, retains it after quantity change and cannot charge a revoked coupon',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      roles.loginAdmin('admin', 'admin');
      await tester.runAsync(
        () => discounts.save(
          const DiscountCode(
            code: 'VENTA10',
            description: 'Diez por ciento',
            kind: DiscountKind.percentage,
            value: 10,
          ),
        ),
      );
      roles.switchToUser();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const QuickSaleScreen()),
      );
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: find.text('Producto prueba'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.add)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver Orden'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Código de descuento'));
      await tester.enterText(field('Código de descuento'), 'noexiste');
      await tester.ensureVisible(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Cobrar \$116.00'), findsOneWidget);
      await tester.enterText(field('Código de descuento'), 'venta10');
      await tester.ensureVisible(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Cobrar \$104.40'), findsOneWidget);
      expect(find.text('IVA incluido (16%):'), findsOneWidget);
      await tester.ensureVisible(find.byIcon(Icons.add_circle_outline));
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Código de descuento')).controller!.text,
        'VENTA10',
      );
      expect(find.text('Cobrar \$208.80'), findsOneWidget);
      expect(
        tester
            .widget<CartBottomSheet>(find.byType(CartBottomSheet))
            .cartItems
            .single
            .quantity,
        2,
      );
      final staleCharge = tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Cobrar \$208.80'),
          )
          .onPressed!;
      roles.loginAdmin('admin', 'admin');
      await tester.runAsync(() => discounts.setActive('VENTA10', false));
      roles.switchToUser();
      staleCharge();
      await tester.pumpAndSettle();
      expect(SalesService().sales, isEmpty);
      expect(find.text('Cobrar \$232.00'), findsOneWidget);
      expect(
        find.text('El código ya no está disponible. Revisa el total.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Quitar código'));
      await tester.tap(find.text('Quitar código'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Código de descuento')).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fiscal ticket shows and copies included IVA without changing total or staff',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sale = Venta(
        id: 'new',
        ticketNumber: 9,
        items: [VentaItem(product: product, quantity: 1, unitPrice: 116)],
        subtotal: 116,
        discount: 11.6,
        iva: 14.4,
        ivaRate: 0.16,
        ivaIncluded: true,
        discountCode: 'VENTA10',
        total: 104.4,
        paymentMethod: 'Tarjeta',
        timestamp: DateTime(2026, 10, 26, 12),
        saleContext: StaffCatalog.selection('norte', 'demo_sofia_reyes'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: TicketDialog(venta: sale)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subtotal:'), findsOneWidget);
      expect(find.text('IVA incluido (16%):'), findsOneWidget);
      expect(find.text('\$14.40'), findsOneWidget);
      expect(find.text('\$104.40'), findsOneWidget);
      await tester.ensureVisible(find.text('WhatsApp'));
      await tester.tap(find.text('WhatsApp'));
      await tester.pump();
      expect(clipboard, contains('Base sin IVA: \$90.00'));
      expect(clipboard, contains('IVA incluido (16%): \$14.40'));
      expect(clipboard, contains('Total: \$104.40'));
      expect(clipboard, contains('Código: VENTA10'));
      expect(clipboard, contains('Atendido por: Sofía Reyes'));
      expect(tester.takeException(), isNull);
    },
  );
}
