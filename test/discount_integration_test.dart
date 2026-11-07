import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/data/staff_catalog.dart';
import 'package:texas_burger/models/discount_code.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/services/discount_code_service.dart';
import 'package:texas_burger/services/export_service.dart';
import 'package:texas_burger/services/pricing_service.dart';
import 'package:texas_burger/services/sales_service.dart';
import 'package:texas_burger/services/user_role_service.dart';

List<VentaItem> items(double price, {String id = 'test', int quantity = 1}) => [
  VentaItem(
    product: Producto(
      id: id,
      name: 'PRODUCTO ORIGINAL',
      description: '',
      price: price,
      category: 'Hamburguesas',
    ),
    quantity: quantity,
    unitPrice: price,
  ),
];

DiscountCode coupon({
  String code = 'DIEZ',
  double value = 10,
  DiscountKind kind = DiscountKind.percentage,
  bool active = true,
}) => DiscountCode(
  code: code,
  description: 'Prueba',
  kind: kind,
  value: value,
  isActive: active,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserRoleService().switchToUser();
  });
  tearDown(() => UserRoleService().switchToUser());

  test('included IVA preserves price and splits base and tax', () {
    final calc = PricingService.calculate(items: items(116));
    expect(
      [
        calc.subtotal,
        calc.discount,
        calc.taxableSubtotal,
        calc.iva,
        calc.total,
      ],
      [116, 0, 100, 16, 116],
    );
    final zero = PricingService.calculate(items: []);
    expect([zero.total, zero.iva, zero.taxableSubtotal], [0, 0, 0]);
    for (final price in [0.01, 10.01, 35.5, 96.0, 150.0]) {
      final result = PricingService.calculate(items: items(price));
      expect(result.total, price);
      expect(result.taxableSubtotal + result.iva, closeTo(price, 0.000001));
    }
    expect(
      () => PricingService.calculate(items: items(116), ivaRate: double.nan),
      throwsArgumentError,
    );
  });

  test(
    'percentage and fixed coupons reduce gross amount before IVA breakdown',
    () {
      final percent = PricingService.calculate(
        items: items(116),
        coupon: coupon(),
      );
      expect(percent.discount, closeTo(11.6, 0.000001));
      expect(percent.total, closeTo(104.4, 0.000001));
      expect([percent.taxableSubtotal, percent.iva], [90, 14.4]);
      final fixed = PricingService.calculate(
        items: items(116),
        coupon: coupon(value: 16, kind: DiscountKind.fixedAmount),
      );
      expect(
        [fixed.discount, fixed.total, fixed.taxableSubtotal, fixed.iva],
        [16, 100, 86.21, 13.79],
      );
      final capped = PricingService.calculate(
        items: items(116),
        coupon: coupon(value: 999, kind: DiscountKind.fixedAmount),
      );
      expect([capped.discount, capped.total, capped.iva], [116, 0, 0]);
    },
  );

  test('Tuesday promotion is retained and coupon applies to remainder', () {
    final original = PricingService.calculate(
      items: items(96, id: 'hamb_texana_clasica', quantity: 2),
      forceMartesPromo: true,
    );
    expect(
      [original.subtotal, original.discount, original.total],
      [192, 42, 150],
    );
    expect([original.taxableSubtotal, original.iva], [129.31, 20.69]);
    final combined = PricingService.calculate(
      items: items(96, id: 'hamb_texana_clasica', quantity: 2),
      forceMartesPromo: true,
      coupon: coupon(),
    );
    expect([combined.discount, combined.total], [57, 135]);
    expect(combined.taxableSubtotal + combined.iva, closeTo(135, 0.000001));
  });

  test('inactive and malformed coupons never alter charges', () {
    for (final invalid in [
      coupon(active: false),
      coupon(value: double.nan),
      coupon(value: double.infinity),
      coupon(value: -1),
      coupon(value: 101),
      coupon(code: ' '),
    ]) {
      final result = PricingService.calculate(
        items: items(116),
        coupon: invalid,
      );
      expect(result.total, 116);
      expect(result.discountCode, isNull);
    }
  });

  test(
    'coupon persistence, updates and concurrent operations preserve unrelated data',
    () async {
      SharedPreferences.setMockInitialValues({
        'texas_sales': '[{"original":true}]',
        'texas_staff_context': 'original',
        'texas_products': 'original',
      });
      final service = DiscountCodeService.forTesting();
      await service.init();
      UserRoleService().loginAdmin('admin', 'admin');
      await Future.wait([
        service.save(coupon(code: ' diez ')),
        service.save(coupon(code: 'DOS', value: 2)),
      ]);
      expect(service.codes.length, 2);
      expect(service.findActive('DiEz')!.code, 'DIEZ');
      await service.save(coupon(code: 'diez', value: 15));
      expect(service.codes.length, 2);
      await service.setActive(' diez ', false);
      expect(service.findActive('DIEZ'), isNull);
      final restarted = DiscountCodeService.forTesting();
      await restarted.init();
      expect(restarted.codes.singleWhere((c) => c.code == 'DIEZ').value, 15);
      expect(
        restarted.codes.singleWhere((c) => c.code == 'DIEZ').isActive,
        isFalse,
      );
      await restarted.setActive('DIEZ', true);
      await restarted.remove(' dos ');
      expect(restarted.codes.single.code, 'DIEZ');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('texas_sales'), '[{"original":true}]');
      expect(prefs.getString('texas_staff_context'), 'original');
      expect(prefs.getString('texas_products'), 'original');
      final before = prefs.getString('texas_discount_codes');
      UserRoleService().switchToUser();
      await expectLater(restarted.save(coupon()), throwsStateError);
      await expectLater(restarted.setActive('DIEZ', false), throwsStateError);
      await expectLater(restarted.remove('DIEZ'), throwsStateError);
      expect(prefs.getString('texas_discount_codes'), before);
    },
  );

  test(
    'corrupt coupon storage does not block startup or overwrite data',
    () async {
      SharedPreferences.setMockInitialValues({
        'texas_discount_codes': '{invalid',
      });
      final service = DiscountCodeService.forTesting();
      await service.init();
      expect(service.loadFailed, isTrue);
      UserRoleService().loginAdmin('admin', 'admin');
      await expectLater(service.save(coupon()), throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'texas_discount_codes',
        ),
        '{invalid',
      );
    },
  );

  test(
    'new fiscal fields persist and remote writer still receives original staff and totals',
    () async {
      final legacy = Venta(
        id: 'legacy',
        ticketNumber: 8,
        items: items(116),
        subtotal: 116,
        total: 116,
        paymentMethod: 'Efectivo',
        timestamp: DateTime(2026, 10, 1),
      ).toJson();
      SharedPreferences.setMockInitialValues({
        'texas_sales': jsonEncode([legacy]),
        'texas_last_ticket': 8,
      });
      final sent = <Venta>[];
      final sales = SalesService.forTesting(
        remoteWriter: (sale) async {
          sent.add(sale);
        },
      );
      await sales.init();
      final calc = PricingService.calculate(
        items: items(116),
        coupon: coupon(code: 'A,"B'),
      );
      final sale = await sales.registerSale(
        saleContext: StaffCatalog.selection('norte', 'demo_sofia_reyes'),
        items: items(116),
        subtotal: calc.subtotal,
        discount: calc.discount,
        total: calc.total,
        iva: calc.iva,
        ivaRate: calc.ivaRate,
        ivaIncluded: true,
        discountCode: calc.discountCode,
        paymentMethod: 'Efectivo',
        cashGiven: 116,
        changeReturned: calc.discount,
      );
      expect(sent.single, same(sale));
      expect(sent.single.saleContext!.branchId, 'norte');
      expect(sent.single.items.single.product.name, 'PRODUCTO ORIGINAL');
      final restarted = SalesService.forTesting(remoteWriter: (_) async {});
      await restarted.init();
      final restored = restarted.sales.singleWhere((s) => s.id == sale.id);
      expect(restored.toJson(), sale.toJson());
      expect(restored.ivaIncluded, isTrue);
      expect(restored.ivaRate, 0.16);
      expect(restored.taxableSubtotal, 90);
      final old = restarted.sales.singleWhere((s) => s.id == 'legacy');
      expect(old.toJson(), legacy);
      expect(old.iva, isNull);
      expect(old.ivaRate, isNull);
      expect(old.ivaIncluded, isNull);
      final csv = ExportService.generateSalesCsv([sale, old]);
      expect(
        csv,
        contains(
          'Empleado_ID,Atendido_Por,Codigo_Descuento,IVA,Tasa_IVA,IVA_Incluido,Base_Sin_IVA',
        ),
      );
      expect(csv, contains('"A,""B",14.40,16.00,Si,90.00'));
      expect(csv.split('\n')[2], endsWith(',"",,,,'));
    },
  );

  test('startup, remote binding and Android startup fix remain configured', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('await DbService.init();'));
    expect(main, contains('await DiscountCodeService().init();'));
    final sales = File('lib/services/sales_service.dart').readAsStringSync();
    expect(sales, contains('_remoteWriter = DbService.guardarVenta'));
    expect(sales, contains('_remoteWriter(newSale);'));
    final lock = File('pubspec.lock')
        .readAsStringSync()
        .split('  shared_preferences_android:')[1]
        .split('  shared_preferences_foundation:')[0];
    expect(lock, contains('version: "2.5.3"'));
  });
}
