import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/data/staff_catalog.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/services/bootstrap_service.dart';
import 'package:texas_burger/services/caja_service.dart';
import 'package:texas_burger/services/pricing_service.dart';
import 'package:texas_burger/services/product_service.dart';
import 'package:texas_burger/services/sales_service.dart';
import 'package:texas_burger/services/user_role_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final roles = UserRoleService();
  final staff = StaffCatalog.selection('norte', 'demo_sofia_reyes');

  setUp(() {
    roles.switchToUser();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(roles.switchToUser);

  test('all product names render in sentence case without changing JSON', () {
    for (final entry in {
      'HAMBURGUESA CLÁSICA': 'Hamburguesa clásica',
      'Hamburguesa Doble Carne': 'Hamburguesa doble carne',
      'COMBO POLLO ESPECIAL': 'Combo pollo especial',
      'PAPAS A LA FRANCESA': 'Papas a la francesa',
      'PROMOCIÓN DEL MARTES': 'Promoción del martes',
      '  ÁRBOL ESPECIAL  ': 'Árbol especial',
      '': '',
    }.entries) {
      final product = BootstrapService.getDefaultProducts().first.copyWith(
        name: entry.key,
      );
      final json = product.toJson();
      final restored = Producto.fromJson(jsonDecode(jsonEncode(json)));
      expect(restored.displayName, entry.value);
      expect(restored.toJson(), json);
      expect(restored.name, entry.key);
    }
  });

  test(
    'old stored names and new products preserve identity, prices and promo calculations',
    () async {
      final original = BootstrapService.getDefaultProducts()
          .singleWhere((p) => p.id == 'hamb_texana_clasica')
          .copyWith(name: 'HAMBURGUESA TEXANA CLÁSICA', price: 96);
      SharedPreferences.setMockInitialValues({
        'texas_products': jsonEncode([original.toJson()]),
        'unrelated': 'conservar',
      });
      final products = ProductService.forTesting();
      await products.init();
      expect(
        products.products.singleWhere((p) => p.id == original.id).toJson(),
        original.toJson(),
      );
      roles.loginAdmin('admin', 'admin');
      final newProduct = original.copyWith(id: 'new', name: 'PRODUCTO NUEVO');
      await products.addProduct(newProduct);
      roles.switchToUser();
      final restarted = ProductService.forTesting();
      await restarted.init();
      expect(
        restarted.products.singleWhere((p) => p.id == 'new').displayName,
        'Producto nuevo',
      );
      expect(
        restarted.products.singleWhere((p) => p.id == 'new').toJson(),
        newProduct.toJson(),
      );
      final items = [VentaItem(product: original, quantity: 2, unitPrice: 96)];
      final calc = PricingService.calculate(
        items: items,
        forceMartesPromo: true,
      );
      expect([calc.subtotal, calc.discount, calc.total], [192, 42, 150]);
      var remoteCalls = 0;
      final sales = SalesService.forTesting(
        remoteWriter: (sale) async {
          remoteCalls++;
          expect(sale.items.single.product.name, original.name);
        },
      );
      await sales.init();
      final sale = await sales.registerSale(
        saleContext: staff,
        items: items,
        subtotal: calc.subtotal,
        discount: calc.discount,
        total: calc.total,
        paymentMethod: 'Efectivo',
        cashGiven: 200,
        changeReturned: 50,
      );
      expect(roles.isUser, isTrue);
      expect(sale.items.single.product.toJson(), original.toJson());
      expect(sale.employeeName, staff.employeeName);
      expect([sale.subtotal, sale.discount, sale.total], [192, 42, 150]);
      expect(remoteCalls, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('unrelated'), 'conservar');
    },
  );

  test('user cannot mutate products, sales or caja through services', () async {
    final products = ProductService.forTesting();
    final sales = SalesService.forTesting(remoteWriter: (_) async {});
    final caja = CajaService.forTesting();
    await products.init();
    await sales.init();
    await caja.init();
    final product = products.products.first;
    roles.loginAdmin('admin', 'admin');
    await caja.abrirCaja(500, saleContext: staff);
    final sale = await sales.registerSale(
      saleContext: staff,
      items: [
        VentaItem(product: product, quantity: 1, unitPrice: product.price),
      ],
      subtotal: product.price,
      discount: 0,
      total: product.price,
      paymentMethod: 'Efectivo',
      cashGiven: product.price,
      changeReturned: 0,
    );
    roles.switchToUser();
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    for (final operation in <Future<dynamic> Function()>[
      () => products.updatePrice(product.id, 1),
      () => products.toggleAvailability(product.id),
      () => products.addProduct(product.copyWith(id: 'unauthorized')),
      products.resetToDefaults,
      () => sales.cancelSale(sale.id),
      sales.clearAllSales,
      () => sales.loadSampleSales(products.products),
      () => caja.abrirCaja(100, saleContext: staff),
      () => caja.registrarMovimiento(
        type: 'salida',
        amount: 10,
        concept: 'No permitido',
      ),
      () => caja.cerrarCaja(
        actualCashCounted: 500,
        notes: '',
        allSales: sales.sales,
      ),
    ]) {
      await expectLater(operation(), throwsStateError);
    }
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    expect(products.products.first.toJson(), product.toJson());
    expect(sales.sales.single.id, sale.id);
    expect(caja.isCajaOpen, isTrue);
    expect(caja.activeCorte!.movimientos, isEmpty);
  });
}
