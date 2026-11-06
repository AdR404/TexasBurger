import 'package:texas_burger/widgets/cart_bottom_sheet.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/screens/home_screen.dart';
import 'package:texas_burger/screens/quick_sale_screen.dart';
import 'package:texas_burger/screens/daily_dashboard_screen.dart';
import 'package:texas_burger/screens/history_screen.dart';
import 'package:texas_burger/screens/caja_screen.dart';
import 'package:texas_burger/screens/settings_screen.dart';
import 'package:texas_burger/services/product_service.dart';
import 'package:texas_burger/services/sales_service.dart';
import 'package:texas_burger/services/caja_service.dart';
import 'package:texas_burger/services/user_role_service.dart';
import 'package:texas_burger/data/staff_catalog.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/models/sale_context.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/widgets/sale_history_list.dart';
import 'package:texas_burger/widgets/staff_context_selector.dart';
import 'package:texas_burger/widgets/ticket_dialog.dart';
import 'package:texas_burger/theme/app_theme.dart';

Venta ticket({
  SaleContext? selection,
  double discount = 42,
  DateTime? timestamp,
}) => Venta(
  id: 'ticket',
  ticketNumber: 1001,
  items: [
    VentaItem(
      product: Producto(
        id: 'burger',
        name: 'HAMBURGUESA CLÁSICA',
        description: '',
        price: 96,
        category: 'Hamburguesas',
      ),
      unitPrice: 96,
      quantity: 2,
    ),
  ],
  subtotal: 192,
  discount: discount,
  total: 192 - discount,
  paymentMethod: 'Efectivo',
  cashGiven: 200,
  changeReturned: 50,
  timestamp: timestamp ?? DateTime(2026, 10, 13, 14, 35, 27),
  saleContext: selection,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Carga la fuente Roboto del SDK de Flutter para las pruebas de interfaz
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((package) => package['name'] == 'flutter');
    final packageRoot = configFile.uri.resolve('${flutter['rootUri']}/');
    final font = File.fromUri(
      packageRoot.resolve(
        '../../bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ),
    );
    final loader = FontLoader(
      'Roboto',
    )..addFont(font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  });
  testWidgets(
    'staff must select branch and employee; no employee is silently chosen',
    (tester) async {
      SaleContext? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: StaffContextSelector(
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      expect(selected, isNull);
      await tester.tap(find.byKey(const ValueKey('staff-branch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Norte').last);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.byKey(const ValueKey('staff-employee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofía Reyes').last);
      await tester.pumpAndSettle();
      expect(selected!.branchId, 'norte');
      expect(selected!.employeeId, 'demo_sofia_reyes');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active shift disables branch but allows another attending employee',
    (tester) async {
      SaleContext? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StaffContextSelector(
              initialSelection: StaffCatalog.selection(
                'perimetral_sur',
                'demo_ana_torres',
              ),
              lockBranch: true,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      );
      final branch = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('staff-branch')),
      );
      expect(branch.onChanged, isNull);
      await tester.tap(find.byKey(const ValueKey('staff-employee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luis García').last);
      await tester.pumpAndSettle();
      expect(selected!.branchId, 'perimetral_sur');
      expect(selected!.employeeName, 'Luis García');
    },
  );

  testWidgets(
    'ticket shows and copies metadata along with original purchase details',
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
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: TicketDialog(
              venta: ticket(
                selection: StaffCatalog.selection(
                  'perimetral_sur',
                  'demo_ana_torres',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Texas Burger'), findsOneWidget);
      expect(find.text('Sucursal: Perimetral Sur'), findsOneWidget);
      expect(find.text('Atendido por: Ana Torres'), findsOneWidget);
      expect(find.text('Fecha: 13/10/2026'), findsOneWidget);
      expect(find.text('Hora: 14:35:27'), findsOneWidget);
      expect(find.text('Hamburguesa clásica'), findsOneWidget);
      await tester.ensureVisible(find.text('WhatsApp'));
      await tester.tap(find.text('WhatsApp'));
      await tester.pump();
      expect(clipboard, contains('Ticket #1001'));
      expect(clipboard, contains('Sucursal: Perimetral Sur'));
      expect(clipboard, contains('Atendido por: Ana Torres'));
      expect(clipboard, contains('Fecha: 13/10/2026'));
      expect(clipboard, contains('Hora: 14:35:27'));
      expect(clipboard, contains('2x Hamburguesa clásica'));
      expect(clipboard, contains('Descuento: -\$42.00'));
      expect(find.text('Subtotal:'), findsOneWidget);
      expect(clipboard, contains('Subtotal: \$192.00'));
      expect(clipboard, contains('Total: \$150.00'));
      expect(clipboard, contains('Método: Efectivo'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy ticket and narrow history show missing data without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: SaleHistoryList(sales: [ticket()])),
        ),
      );
      expect(find.text('Texas Burger • No registrado'), findsOneWidget);
      expect(find.text('Atendido por: No registrado'), findsOneWidget);
      expect(find.text('13/10/2026 14:35:27'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Atendido por: No registrado'));
      await tester.pumpAndSettle();
      expect(find.text('Sucursal: No registrado'), findsOneWidget);
      expect(find.text('Hora: 14:35:27'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('undiscounted ticket always shows and copies subtotal', (
    tester,
  ) async {
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
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: TicketDialog(venta: ticket(discount: 0))),
      ),
    );
    expect(find.text('Subtotal:'), findsOneWidget);
    expect(find.text('Total:'), findsOneWidget);
    expect(find.text('Descuento / Promo:'), findsNothing);
    await tester.ensureVisible(find.text('WhatsApp'));
    await tester.tap(find.text('WhatsApp'));
    await tester.pump();
    expect(clipboard, contains('Subtotal: \$192.00'));
    expect(clipboard, contains('Total: \$192.00'));
    expect(clipboard, isNot(contains('Descuento:')));
    expect(clipboard, contains('IVA: No registrado'));
    expect(clipboard, isNot(contains('IVA incluido')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('today history retains staff and opens the original ticket', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sale = ticket(
      timestamp: DateTime.now(),
      selection: StaffCatalog.selection('norte', 'demo_sofia_reyes'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SaleHistoryList(sales: [sale])),
      ),
    );
    expect(find.textContaining('Hoy,'), findsOneWidget);
    expect(find.textContaining('2x Hamburguesa clásica'), findsOneWidget);
    expect(find.textContaining('HAMBURGUESA CLÁSICA'), findsNothing);
    expect(find.text('Texas Burger • Norte'), findsOneWidget);
    await tester.tap(find.text('Atendido por: Sofía Reyes'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TicketDialog>(find.byType(TicketDialog)).venta,
      same(sale),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct internal screens enforce the current local role', (
    tester,
  ) async {
    final roles = UserRoleService()..switchToUser();
    addTearDown(roles.switchToUser);
    for (final screen in [const DailyDashboardScreen(), const CajaScreen()]) {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: screen),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Disponible solo en modo administrador.'),
        findsOneWidget,
      );
      expect(find.text('Abrir caja'), findsNothing);
      expect(find.byTooltip('Exportar ventas del periodo'), findsNothing);
      roles.loginAdmin('admin', 'admin');
      await tester.pumpAndSettle();
      expect(find.text('Disponible solo en modo administrador.'), findsNothing);
      roles.switchToUser();
      await tester.pumpAndSettle();
      expect(
        find.text('Disponible solo en modo administrador.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Añadir artículo / promo'), findsNothing);
    expect(find.byTooltip('Editar precio'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Opciones y datos (solo administrador)'), findsNothing);
  });

  testWidgets(
    'navigation, image fallback and existing catalog administration work by role',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final plain = Producto(
        id: 'plain',
        name: 'SIN IMAGEN',
        description: '',
        price: 30,
        category: 'Bebidas',
      );
      final missing = Producto(
        id: 'missing',
        name: 'Imagen ausente',
        description: '',
        price: 40,
        category: 'Bebidas',
        imagePath: 'assets/images/missing.png',
      );
      SharedPreferences.setMockInitialValues({
        'texas_products': jsonEncode([plain.toJson(), missing.toJson()]),
        'texas_sales': jsonEncode([ticket().toJson()]),
        'texas_last_ticket': 1001,
      });
      await tester.runAsync(() async {
        await ProductService().init();
        await SalesService().init();
        await CajaService().init();
      });
      final roles = UserRoleService()..switchToUser();
      addTearDown(roles.switchToUser);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuickSaleScreen), findsOneWidget);
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['Venta', 'Catálogo', 'Historial'],
      );
      expect(
        find.byType(DailyDashboardScreen, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(CajaScreen, skipOffstage: false), findsNothing);
      for (final name in ['Sin imagen', 'Imagen ausente']) {
        final card = find.ancestor(
          of: find.text(name),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: card, matching: find.byType(Icon)),
          findsWidgets,
        );
      }
      expect(tester.takeException(), isNull);
      // El usuario puede vender y cambiar cantidades en el carrito
      await tester.runAsync(
        () => CajaService().updateSaleContext(
          StaffCatalog.selection('norte', 'demo_sofia_reyes'),
        ),
      );
      final plainCard = find.ancestor(
        of: find.text('Sin imagen'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: plainCard, matching: find.byIcon(Icons.add)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: plainCard, matching: find.byIcon(Icons.add)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver Orden'));
      await tester.pumpAndSettle();
      final cart = tester.widget<CartBottomSheet>(find.byType(CartBottomSheet));
      expect(cart.cartItems.single.quantity, 2);
      expect(cart.cartItems.single.product.name, 'SIN IMAGEN');
      expect(cart.cartItems.single.subtotal, 60);
      expect(
        find.descendant(
          of: find.byType(CartBottomSheet),
          matching: find.text('Sin imagen'),
        ),
        findsOneWidget,
      );
      expect(find.text('SIN IMAGEN'), findsNothing);
      Navigator.of(tester.element(find.byType(CartBottomSheet))).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Promociones'));
      await tester.tap(find.text('Promociones'));
      await tester.pumpAndSettle();
      for (final path in [
        'assets/images/promo_martes.png',
        'assets/images/combo_pollo_especial.png',
      ]) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName == path,
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      final screens = [QuickSaleScreen, SettingsScreen, HistoryScreen];
      for (var index = 0; index < screens.length; index++) {
        await tester.tap(find.byType(NavigationDestination).at(index));
        await tester.pumpAndSettle();
        expect(find.byType(screens[index]), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Sin imagen'), findsOneWidget);
      expect(find.text('SIN IMAGEN'), findsNothing);
      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('Añadir artículo / promo'), findsNothing);
      expect(find.byTooltip('Editar precio'), findsNothing);
      expect(find.byType(Switch), findsNothing);

      // Prueba de inicio de sesión como administrador desde la interfaz
      await tester.tap(find.text('Usuario'));
      await tester.pumpAndSettle();
      final loginFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(loginFields.at(0), 'admin');
      await tester.enterText(loginFields.at(1), 'admin');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(roles.isAdmin, isTrue);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Menú'), findsOneWidget);
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['Venta', 'Dashboard', 'Historial', 'Caja', 'Menú'],
      );
      expect(find.text('Añadir artículo / promo'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Editar precio').first);
      await tester.tap(find.byTooltip('Editar precio').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '35.50',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(ProductService().products.first.price, 35.5);
      await tester.ensureVisible(find.byType(Switch).first);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(ProductService().products.first.isAvailable, isFalse);

      for (final promo in [false, true]) {
        await tester.ensureVisible(find.text('Añadir artículo / promo'));
        await tester.tap(find.text('Añadir artículo / promo'));
        await tester.pumpAndSettle();
        final fields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        final name = promo ? 'PROMOCIÓN NUEVA' : 'PRODUCTO NUEVO';
        await tester.enterText(fields.at(0), name);
        await tester.enterText(fields.at(1), '70');
        await tester.enterText(fields.at(2), 'Descripción nueva');
        if (promo) {
          await tester.ensureVisible(find.byType(SwitchListTile));
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        final created = ProductService().products.singleWhere(
          (p) => p.name == name,
        );
        expect(created.price, 70);
        expect(created.isPromo, promo);
      }
      // Si se cambia a modo usuario con un diálogo abierto, no permite guardar cambios
      await tester.ensureVisible(find.byTooltip('Editar precio').first);
      await tester.tap(find.byTooltip('Editar precio').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '999',
      );
      final save = tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Guardar'),
          )
          .onPressed!;
      final beforeRevocation = ProductService().products.first.toJson();
      roles.switchToUser();
      save();
      await tester.pumpAndSettle();
      expect(ProductService().products.first.toJson(), beforeRevocation);
      expect(find.text('Guardar'), findsNothing);
      expect(
        find.text('Disponible solo en modo administrador.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byTooltip('Editar precio'), findsNothing);
      expect(find.text('Añadir artículo / promo'), findsNothing);
      await tester.tap(find.byType(NavigationDestination).first);
      await tester.pumpAndSettle();
      expect(find.byType(QuickSaleScreen), findsOneWidget);
      // Conserva la categoría seleccionada al volver a la pantalla de venta
      expect(find.text('Producto nuevo'), findsNothing);
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      for (final name in ['Producto nuevo', 'Promoción nueva']) {
        await tester.ensureVisible(find.text(name));
        await tester.pumpAndSettle();
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('PRODUCTO NUEVO'), findsNothing);
      expect(find.text('PROMOCIÓN NUEVA'), findsNothing);
      for (final path in [
        'assets/images/promo_martes.png',
        'assets/images/combo_pollo_especial.png',
      ]) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName == path,
          ),
          findsOneWidget,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      final saved = (jsonDecode(prefs.getString('texas_products')!) as List)
          .cast<Map<String, dynamic>>();
      expect(saved.singleWhere((p) => p['id'] == 'plain')['price'], 35.5);
      expect(
        saved.singleWhere((p) => p['id'] == 'plain')['isAvailable'],
        isFalse,
      );
      expect(prefs.getString('texas_sales'), jsonEncode([ticket().toJson()]));
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      for (var index = 0; index < screens.length; index++) {
        await tester.tap(find.byType(NavigationDestination).at(index));
        await tester.pumpAndSettle();
        expect(find.byType(screens[index]), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      for (final restrictedIndex in [1, 3, 1, 3]) {
        roles.loginAdmin('admin', 'admin');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byType(NavigationDestination).at(restrictedIndex),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(restrictedIndex == 1 ? DailyDashboardScreen : CajaScreen),
          findsOneWidget,
        );
        roles.switchToUser();
        await tester.pumpAndSettle();
        expect(find.byType(QuickSaleScreen), findsOneWidget);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        expect(find.byType(NavigationDestination), findsNWidgets(3));
        expect(
          find.byType(DailyDashboardScreen, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(CajaScreen, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      }
      // Operaciones de apertura, movimientos y cierre de caja en modo administrador
      tester.view.physicalSize = const Size(400, 900);
      roles.loginAdmin('admin', 'admin');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir caja / iniciar turno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iniciar Turno'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'opening caja');
      expect(CajaService().isCajaOpen, isTrue);
      await tester.ensureVisible(find.text('Registrar gasto'));
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      final movementFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(movementFields.at(0), '20');
      await tester.enterText(movementFields.at(1), 'Hielo');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'caja movement');
      expect(CajaService().activeCorte!.cashOut, 20);
      await tester.ensureVisible(
        find.text('Hacer corte de caja (cerrar turno)'),
      );
      await tester.tap(find.text('Hacer corte de caja (cerrar turno)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar Turno'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'caja closing report');
      expect(CajaService().isCajaOpen, isFalse);
      expect(CajaService().cortesHistory.first.expectedCash, 480);
      expect(CajaService().cortesHistory.first.difference, 0);
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      roles.switchToUser();
      await tester.runAsync(
        () => CajaService().updateSaleContext(
          StaffCatalog.selection('norte', 'demo_sofia_reyes'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuickSaleScreen), findsOneWidget);
      await tester.tap(find.text('Ver Orden'));
      await tester.pumpAndSettle();
      final retainedCart = tester.widget<CartBottomSheet>(
        find.byType(CartBottomSheet),
      );
      expect(retainedCart.cartItems.single.quantity, 2);
      expect(retainedCart.cartItems.single.unitPrice, 30);
      expect(retainedCart.cartItems.single.product.id, 'plain');
      expect(retainedCart.cartItems.single.product.name, 'SIN IMAGEN');
      expect(tester.takeException(), isNull);
    },
  );
}
