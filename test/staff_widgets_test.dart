import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:texas_burger/data/staff_catalog.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/models/sale_context.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/widgets/sale_history_list.dart';
import 'package:texas_burger/widgets/staff_context_selector.dart';
import 'package:texas_burger/widgets/ticket_dialog.dart';
import 'package:texas_burger/theme/app_theme.dart';

Venta ticket({SaleContext? selection}) => Venta(
  id: 'ticket',
  ticketNumber: 1001,
  items: [
    VentaItem(
      product: Producto(
        id: 'burger',
        name: 'Hamburguesa',
        description: '',
        price: 96,
        category: 'Hamburguesas',
      ),
      unitPrice: 96,
      quantity: 2,
    ),
  ],
  subtotal: 192,
  discount: 42,
  total: 150,
  paymentMethod: 'Efectivo',
  cashGiven: 200,
  changeReturned: 50,
  timestamp: DateTime(2026, 10, 13, 14, 35, 27),
  saleContext: selection,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use the app's real font rather than Ahem's artificially wide test glyphs.
    // Resolve it from this Flutter SDK; no host-specific path or download.
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
      expect(find.text('Hamburguesa'), findsOneWidget);
      await tester.ensureVisible(find.text('WhatsApp'));
      await tester.tap(find.text('WhatsApp'));
      await tester.pump();
      expect(clipboard, contains('Ticket #1001'));
      expect(clipboard, contains('Sucursal: Perimetral Sur'));
      expect(clipboard, contains('Atendido por: Ana Torres'));
      expect(clipboard, contains('Fecha: 13/10/2026'));
      expect(clipboard, contains('Hora: 14:35:27'));
      expect(clipboard, contains('2x Hamburguesa'));
      expect(clipboard, contains('Descuento: -\$42.00'));
      expect(clipboard, contains('TOTAL: \$150.00'));
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
}
