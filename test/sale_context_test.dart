import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/data/staff_catalog.dart';
import 'package:texas_burger/models/corte_caja.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/models/sale_context.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/services/caja_service.dart';
import 'package:texas_burger/services/export_service.dart';
import 'package:texas_burger/services/sales_service.dart';

final ana = StaffCatalog.selection('perimetral_sur', 'demo_ana_torres');
final luis = StaffCatalog.selection('perimetral_sur', 'demo_luis_garcia');
final norte = StaffCatalog.selection('norte', 'demo_sofia_reyes');

Venta exampleSale({SaleContext? context}) => Venta(
  id: 'existing_sale',
  ticketNumber: 1075,
  items: [
    VentaItem(
      product: Producto(
        id: 'burger',
        name: 'Hamburguesa',
        description: 'Original',
        price: 96,
        category: 'Hamburguesas',
      ),
      quantity: 2,
      unitPrice: 96,
      removedIngredients: ['Sin cebolla'],
      notes: 'Bien cocida',
    ),
  ],
  subtotal: 192,
  discount: 42,
  total: 150,
  paymentMethod: 'Efectivo',
  cashGiven: 200,
  changeReturned: 50,
  timestamp: DateTime(2026, 10, 13, 14, 35, 27),
  notes: 'Pedido original',
  orderType: 'A domicilio',
  customerName: 'Cliente',
  customerPhone: '5551234567',
  deliveryAddress: 'Calle 10',
  saleContext: context,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'catalog IDs are stable and demo staff have no numeric user mapping',
    () {
      expect(StaffCatalog.branches.keys, ['perimetral_sur', 'norte']);
      expect(StaffCatalog.employees.length, 3);
      expect(
        StaffCatalog.employees.keys.every((id) => id.startsWith('demo_')),
        isTrue,
      );
      expect(
        () => StaffCatalog.selection('unknown', 'demo_ana_torres'),
        throwsArgumentError,
      );
    },
  );

  test(
    'legacy JSON keeps all old fields and does not invent branch or employee',
    () {
      final legacy = exampleSale().toJson()..remove('saleContext');
      final sale = Venta.fromJson(
        jsonDecode(jsonEncode(legacy)) as Map<String, dynamic>,
      );
      expect(sale.saleContext, isNull);
      expect(sale.companyName, 'Texas Burger');
      expect(sale.branchName, 'No registrado');
      expect(sale.employeeName, 'No registrado');
      expect(sale.toJson()..remove('saleContext'), legacy);
    },
  );

  test(
    'new JSON retains IDs and name snapshots independently of the catalog',
    () {
      const snapshot = SaleContext(
        branchId: 'norte',
        branchName: 'Nombre histórico',
        employeeId: 'demo_ana_torres',
        employeeName: 'Nombre al cobrar',
      );
      final original = exampleSale(context: snapshot);
      final restored = Venta.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
      expect(restored.employeeName, 'Nombre al cobrar');
      expect(restored.branchName, 'Nombre histórico');
    },
  );

  test(
    'registration preserves old history, persists each employee and timestamps completion',
    () async {
      final legacy = exampleSale().toJson()..remove('saleContext');
      SharedPreferences.setMockInitialValues({
        'texas_sales': jsonEncode([legacy]),
        'texas_last_ticket': 1075,
      });
      final remoteCalls = <Venta>[];
      final sales = SalesService.forTesting(
        remoteWriter: (sale) async {
          remoteCalls.add(sale);
        },
      );
      await sales.init();
      final before = DateTime.now();
      final first = await sales.registerSale(
        saleContext: ana,
        items: exampleSale().items,
        subtotal: 192,
        discount: 42,
        total: 150,
        paymentMethod: 'Efectivo',
        cashGiven: 200,
        changeReturned: 50,
      );
      final second = await sales.registerSale(
        saleContext: luis,
        items: exampleSale().items,
        subtotal: 192,
        discount: 42,
        total: 150,
        paymentMethod: 'Tarjeta',
      );
      final after = DateTime.now();
      expect(first.timestamp.isBefore(before), isFalse);
      expect(second.timestamp.isAfter(after), isFalse);
      expect(first.employeeName, 'Ana Torres');
      expect(second.employeeName, 'Luis García');
      expect(first.total, 150);
      expect(first.discount, 42);
      expect(first.cashGiven, 200);
      expect(first.changeReturned, 50);
      expect(first.ticketNumber, 1076);
      expect(second.ticketNumber, 1077);
      expect(remoteCalls, [first, second]);
      final restarted = SalesService.forTesting(remoteWriter: (_) async {});
      await restarted.init();
      expect(restarted.sales.length, 3);
      expect(
        restarted.sales
            .singleWhere((s) => s.ticketNumber == 1076)
            .saleContext!
            .toJson(),
        ana.toJson(),
      );
      expect(
        restarted.sales
            .singleWhere((s) => s.ticketNumber == 1077)
            .saleContext!
            .toJson(),
        luis.toJson(),
      );
      expect(
        restarted.sales.singleWhere((s) => s.ticketNumber == 1075).toJson()
          ..remove('saleContext'),
        legacy,
      );
    },
  );

  test(
    'shift locks branch, changes employee, survives restart and preserves opener',
    () async {
      final caja = CajaService.forTesting();
      await caja.init();
      await caja.abrirCaja(500, saleContext: ana);
      await caja.updateSaleContext(luis);
      await expectLater(caja.updateSaleContext(norte), throwsStateError);
      await caja.registrarMovimiento(
        type: 'salida',
        amount: 20,
        concept: 'Hielo',
      );
      final restarted = CajaService.forTesting();
      await restarted.init();
      expect(restarted.isBranchLocked, isTrue);
      expect(restarted.saleContext!.toJson(), luis.toJson());
      expect(restarted.activeCorte!.openingContext!.toJson(), ana.toJson());
      expect(
        restarted.computeLiveShift([]).openingContext!.employeeName,
        'Ana Torres',
      );
      final closed = await restarted.cerrarCaja(
        actualCashCounted: 480,
        notes: '',
        allSales: [],
      );
      expect(closed.expectedCash, 480);
      expect(closed.difference, 0);
      expect(closed.openingContext!.employeeName, 'Ana Torres');
      expect(restarted.saleContext, isNull);
      expect(restarted.isBranchLocked, isFalse);
      await restarted.abrirCaja(300, saleContext: norte);
      expect(restarted.saleContext!.branchName, 'Norte');
      expect(
        restarted.cortesHistory.single.openingContext!.branchName,
        'Perimetral Sur',
      );
    },
  );

  test(
    'legacy open shift and cuts survive selection without inventing opener',
    () async {
      final old = CorteCaja(
        id: 'old',
        openedAt: DateTime(2026, 1, 1),
        initialCash: 500,
        expectedCash: 500,
      ).toJson()..remove('openingContext');
      SharedPreferences.setMockInitialValues({
        'texas_active_corte': jsonEncode(old),
      });
      final caja = CajaService.forTesting();
      await caja.init();
      expect(caja.isCajaOpen, isTrue);
      expect(caja.saleContext, isNull);
      await caja.updateSaleContext(ana);
      expect(caja.isBranchLocked, isTrue);
      expect(caja.activeCorte!.openingContext, isNull);
      expect(caja.activeCorte!.toJson()..remove('openingContext'), old);
    },
  );

  test(
    'staff selection without open box persists and can change branch',
    () async {
      final caja = CajaService.forTesting();
      await caja.init();
      await caja.updateSaleContext(ana);
      expect(caja.isCajaOpen, isFalse);
      await caja.updateSaleContext(norte);
      final restarted = CajaService.forTesting();
      await restarted.init();
      expect(restarted.saleContext!.toJson(), norte.toJson());
      expect(restarted.isBranchLocked, isFalse);
    },
  );

  test('CSV keeps original columns and amounts and appends staff snapshots', () {
    final csv = ExportService.generateSalesCsv([
      exampleSale(context: ana),
      exampleSale(),
    ]);
    expect(csv, startsWith('\uFEFFTicket,Fecha,Hora,Modalidad'));
    expect(
      csv,
      contains(
        'Notas,Empresa_ID,Empresa,Sucursal_ID,Sucursal,Empleado_ID,Atendido_Por',
      ),
    );
    expect(csv, contains('"2026-10-13","14:35:27"'));
    expect(csv, contains('192.00,42.00,150.00,"Pedido original"'));
    expect(
      csv,
      contains(
        '"texas_burger","Texas Burger","perimetral_sur","Perimetral Sur","demo_ana_torres","Ana Torres"',
      ),
    );
    expect(
      csv,
      contains(
        '"texas_burger","Texas Burger","","No registrado","","No registrado"',
      ),
    );
  });

  test('CSV escapes commas and quotes in stored names', () {
    const custom = SaleContext(
      branchId: 'norte',
      branchName: 'Norte, local "A"',
      employeeId: 'demo_ana_torres',
      employeeName: 'Ana "A"',
    );
    final csv = ExportService.generateSalesCsv([exampleSale(context: custom)]);
    expect(csv, contains('"Norte, local ""A"""'));
    expect(csv, contains('"Ana ""A"""'));
  });

  test(
    'sales report uses each sale and cut report identifies only the opener',
    () {
      final report = ExportService.generateWhatsAppSalesReport([
        exampleSale(context: ana),
        exampleSale(context: luis),
        exampleSale(),
      ], 'Todo');
      expect(report, contains('VENTA TOTAL:* \$450.00'));
      expect(report, contains('Atendido por: Ana Torres'));
      expect(report, contains('Atendido por: Luis García'));
      expect(report, contains('Atendido por: No registrado'));
      expect(report, contains('Fecha: 13/10/2026 | Hora: 14:35:27'));
      final corte = CorteCaja(
        id: 'test',
        openedAt: DateTime(2026, 10, 13, 12),
        initialCash: 500,
        expectedCash: 500,
        openingContext: ana,
      );
      final cutReport = ExportService.generateWhatsAppCorteReport(corte);
      expect(cutReport, contains('Sucursal: Perimetral Sur'));
      expect(cutReport, contains('Abrió caja: Ana Torres'));
      expect(cutReport, isNot(contains('Atendido por:')));
      final oldCut = CorteCaja.fromJson(
        corte.toJson()..remove('openingContext'),
      );
      expect(
        ExportService.generateWhatsAppCorteReport(oldCut),
        contains('Abrió caja: No registrado'),
      );
    },
  );
}
