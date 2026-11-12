import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/models/sale_context.dart';
import 'package:texas_burger/services/bootstrap_service.dart';
import 'package:texas_burger/services/db_service.dart';
import 'package:texas_burger/services/inventory_sale_attempt.dart';
import 'package:texas_burger/services/pricing_service.dart';
import 'package:texas_burger/services/sales_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const context = SaleContext(
    branchId: 'norte',
    branchName: 'Norte',
    employeeId: 'real',
    employeeName: 'Empleado',
  );
  final product = BootstrapService.getDefaultProducts().first;
  Venta sale({String notes = ''}) {
    final items = [
      VentaItem(product: product, quantity: 2, unitPrice: 100, notes: notes),
    ];
    final pricing = PricingService.calculate(items: items);
    return Venta(
      id: 'local',
      ticketNumber: 1001,
      items: items,
      subtotal: pricing.subtotal,
      discount: pricing.discount,
      total: pricing.total,
      iva: pricing.iva,
      ivaRate: .16,
      ivaIncluded: true,
      paymentMethod: 'Efectivo',
      timestamp: DateTime(2026),
      saleContext: context,
    );
  }

  Future<Map<String, dynamic>> request(Venta s) =>
      DbService.inventoryRequest(s, resolve: (_) async => 91);
  Map<String, dynamic> result({bool repeated = false}) => {
    'estado': 'complete',
    'venta_id': 9,
    'repetida': repeated,
    'caja_turno_id': null,
  };
  InventorySaleAttempt attempt(
    Future<dynamic> Function(String, Map<String, dynamic>) send,
  ) => InventorySaleAttempt(project: 'test', actor: 'actor', send: send);
  Future<Venta> register(SalesService service) {
    final s = sale();
    return service.registerSale(
      saleContext: context,
      items: s.items,
      subtotal: s.subtotal,
      discount: s.discount,
      total: s.total,
      iva: s.iva,
      ivaRate: .16,
      ivaIncluded: true,
      paymentMethod: s.paymentMethod,
    );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('contract uses remote ids and unchanged pricing', () async {
    final s = sale();
    final r = await request(s);
    expect(r.keys.toSet(), {
      'sucursal_id',
      'items',
      'subtotal',
      'descuento',
      'total',
      'iva',
      'metodo_pago',
    });
    expect(r['items'], [
      {
        'producto_id': 91,
        'cantidad': 2,
        'precio_unitario': 100.0,
        'extras': [],
        'exclusiones': [],
        'notas': '',
      },
    ]);
    expect(r['total'], s.total);
    expect(r['iva'], s.iva);
  });
  test('reject unknown remote id', () async {
    await expectLater(
      DbService.inventoryRequest(sale(), resolve: (_) async => 0),
      throwsStateError,
    );
  });
  test('personalization not silently removed', () async {
    await expectLater(request(sale(notes: 'Sin cebolla')), throwsStateError);
  });
  test('successful result preserved until history acknowledgment', () async {
    final a = attempt((id, r) async => result());
    await a.prepare(sale(), await request(sale()));
    final s = await a.resume();
    expect(s.remoteId, 9);
    expect(s.operationId, s.id);
    expect(await a.pending(), isNotNull);
    await a.acknowledge(s.id);
    expect(await a.pending(), isNull);
  });
  test(
    'uncertain response survives restart with exact uuid and json',
    () async {
      String? id;
      String? json;
      final a = attempt((i, r) async {
        id = i;
        json = jsonEncode(r);
        throw Exception('network');
      });
      await a.prepare(sale(), await request(sale()));
      await expectLater(a.resume(), throwsStateError);
      final b = attempt((i, r) async {
        expect(i, id);
        expect(jsonEncode(r), json);
        return result(repeated: true);
      });
      final s = await b.resume();
      expect(s.id, id);
      expect(s.remoteId, 9);
    },
  );
  for (final message in [
    'Ingredientes insuficientes: 1',
    'Producto 1 pendiente de configurar consumo',
    'Producto 1 sin receta',
  ]) {
    test('confirmed rejection: $message', () async {
      final a = attempt(
        (i, r) async =>
            throw PostgrestException(message: message, code: '22023'),
      );
      await a.prepare(sale(), await request(sale()));
      await expectLater(
        a.resume(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      expect(await a.pending(), isNull);
    });
  }
  test('rejection after uncertainty cannot discard original attempt', () async {
    final a = attempt((i, r) async => throw Exception());
    await a.prepare(sale(), await request(sale()));
    await expectLater(a.resume(), throwsStateError);
    final b = attempt(
      (i, r) async => throw const PostgrestException(
        message: 'No autorizado',
        code: '42501',
      ),
    );
    await expectLater(b.resume(), throwsStateError);
    expect(await b.pending(), isNotNull);
  });
  test('malformed success retains attempt', () async {
    final a = attempt((i, r) async => {'estado': 'complete'});
    await a.prepare(sale(), await request(sale()));
    await expectLater(a.resume(), throwsStateError);
    expect(await a.pending(), isNotNull);
  });
  test('cannot overwrite pending or recover another actor', () async {
    final a = attempt((i, r) async => result());
    await a.prepare(sale(), await request(sale()));
    await expectLater(
      a.prepare(sale(), await request(sale())),
      throwsStateError,
    );
    final b = InventorySaleAttempt(
      project: 'test',
      actor: 'other',
      send: (i, r) async => result(),
    );
    await expectLater(b.resume(), throwsStateError);
  });
  test('mode off retains old writer', () async {
    var calls = 0;
    final s = SalesService.forTesting(
      remoteWriter: (_) async {
        calls++;
      },
    );
    await register(s);
    expect(calls, 1);
    expect(s.sales.single.operationId, isNull);
  });
  test(
    'mode on has no fallback and recovery deduplicates local history',
    () async {
      var old = 0;
      var calls = 0;
      final a = attempt((i, r) async {
        calls++;
        if (calls == 1) throw Exception();
        return result(repeated: true);
      });
      final s =
          SalesService.forTesting(
              remoteWriter: (_) async {
                old++;
              },
            )
            ..inventoryAttemptForTesting = a
            ..inventoryRequestForTesting = request;
      await expectLater(register(s), throwsStateError);
      expect(s.sales, isEmpty);
      expect(old, 0);
      await expectLater(register(s), throwsStateError);
      expect(calls, 1);
      final restored =
          SalesService.forTesting(
              remoteWriter: (_) async {
                old++;
              },
            )
            ..inventoryAttemptForTesting = a
            ..inventoryRequestForTesting = request;
      final recovered = await restored.recoverInventorySale();
      expect(recovered.remoteId, 9);
      expect(restored.sales.length, 1);
      expect(old, 0);
      expect(await a.pending(), isNull);
      await expectLater(restored.recoverInventorySale(), throwsStateError);
      expect(restored.sales.length, 1);
    },
  );
  test(
    'confirmed pending plus existing durable history never duplicates ticket',
    () async {
      final a = attempt((i, r) async => result());
      await a.prepare(sale(), await request(sale()));
      final confirmed = await a.resume();
      await (await SharedPreferences.getInstance()).setString(
        'texas_sales',
        jsonEncode([confirmed.toJson()]),
      );
      final s = SalesService.forTesting(
        remoteWriter: (_) async => fail('fallback'),
      )..inventoryAttemptForTesting = a;
      await s.recoverInventorySale();
      expect(s.sales.length, 1);
    },
  );
}
