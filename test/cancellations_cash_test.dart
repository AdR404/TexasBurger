import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/services/app_auth_service.dart' as app;
import 'package:texas_burger/services/sale_actions.dart';
import 'package:texas_burger/services/sales_service.dart';
import 'package:texas_burger/services/dashboard_service.dart';
import 'package:texas_burger/services/export_service.dart';
import 'package:texas_burger/widgets/sale_actions_panel.dart';
import 'package:texas_burger/widgets/verified_cash_dialog.dart';
import 'package:texas_burger/widgets/ticket_dialog.dart';

const admin = app.AuthUser(
  id: 'admin',
  email: '',
  name: 'Admin',
  role: 'admin',
  businessId: 1,
  employeeId: 'employee',
  employeeName: 'Admin',
  branchId: 'norte',
);
const cashier = app.AuthUser(
  id: 'cashier',
  email: '',
  name: 'Cajero',
  role: 'cajero',
  businessId: 2,
  employeeId: 'cashier',
  employeeName: 'Cajero',
  branchId: 'norte',
);
Map<String, dynamic> sale({String state = 'activa'}) => {
  'id': 9,
  'sucursal_id': 'norte',
  'estado': state,
  'metodo_pago': 'Efectivo',
  'total': 100,
};
Map<String, dynamic> summary([String hash = 'first']) => {
  'turno_id': 3,
  'cerrado': false,
  'huella': hash,
  'total_bruto': 150,
  'total_cancelado': 50,
  'total_neto': 100,
  'ordenes_validas': 1,
  'ordenes_canceladas': 1,
  'fondo_inicial': 20,
  'entradas': 10,
  'salidas': 5,
  'efectivo_base_neta': 125,
  'efectivo_cancelado_sin_conciliar': 0,
  'por_metodo': {
    for (final m in ['Efectivo', 'Tarjeta', 'Transferencia'])
      m: {'neto': m == 'Efectivo' ? 100 : 0},
  },
};
Venta local({bool cancelled = false}) => Venta(
  id: 'local',
  remoteId: 9,
  ticketNumber: 1001,
  items: [],
  subtotal: 100,
  total: 100,
  paymentMethod: 'Efectivo',
  timestamp: DateTime.now(),
  status: cancelled ? 'cancelada' : 'activa',
  cancellationReason: cancelled ? 'Error de pedido' : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cancel form defaults to no reintegration and sends once while pending', (tester) async {
    final pending = Completer<dynamic>();
    var calls = 0;
    final api = SaleActions(cancelEnabled: true, user: () => admin, send: (_, p) {
      calls++;
      expect(p['p_reintegrar'], false);
      return pending.future;
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SaleActionsPanel(
      sale: sale(), actions: api, onChanged: () async {},
    ))));
    await tester.tap(find.text('Cancelar venta'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value, false);
    await tester.enterText(find.byType(TextField), 'Pedido incorrecto');
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.tap(find.text('Confirmar'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(calls, 1);
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar venta'));
    expect(button.onPressed, isNull);
    pending.complete({'venta_id': 9, 'estado': 'cancelada', 'repetida': false});
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('pending cash prevents verified confirmation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VerifiedCashDialog(
      load: () async => {...summary(), 'efectivo_cancelado_sin_conciliar': 50},
      close: (_, _, _) async => fail('Must not close pending cash'),
    ))));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar cierre')).onPressed, isNull);
  });

  test('new actions disabled by default, no RPC or fallback', () async {
    expect(SaleActions.cancellationsEnabled, isFalse);
    expect(SaleActions.verifiedCashEnabled, isFalse);
    var calls = 0;
    final api = SaleActions(
      user: () => admin,
      send: (_, _) async {
        calls++;
        return null;
      },
    );
    await expectLater(api.cancel(sale(), 'Error'), throwsStateError);
    await expectLater(api.summary(3), throwsStateError);
    await expectLater(api.close(3, 'h', 125, ''), throwsStateError);
    expect(calls, 0);
  });

  test(
    'cancel uses exact contract; reintegration defaults false and may be true',
    () async {
      final requests = <Map<String, dynamic>>[];
      final api = SaleActions(
        cancelEnabled: true,
        user: () => admin,
        send: (name, p) async {
          expect(name, 'cancelar_venta');
          requests.add(p);
          return {'venta_id': 9, 'estado': 'cancelada', 'repetida': false};
        },
      );
      await api.cancel(sale(), ' Error ');
      await api.cancel(sale(), 'Error', restore: true);
      expect(requests.first, {
        'p_venta_id': 9,
        'p_motivo': 'Error',
        'p_reintegrar': false,
      });
      expect(requests.last['p_reintegrar'], true);
      await expectLater(
        api.cancel(sale(state: 'cancelada'), 'Error'),
        throwsStateError,
      );
      expect(requests.length, 2);
    },
  );

  for (final error in [
    const PostgrestException(
      message: 'Falta permiso de sucursal',
      code: '42501',
    ),
    const PostgrestException(message: 'Turno cerrado', code: '22023'),
    const PostgrestException(message: 'Lote caducado', code: '22023'),
  ]) {
    test('preserves server rejection: ${error.message}', () async {
      var calls = 0;
      final api = SaleActions(
        cancelEnabled: true,
        user: () => admin,
        send: (_, _) async {
          calls++;
          throw error;
        },
      );
      await expectLater(
        api.cancel(sale(), 'Error'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', error.message),
        ),
      );
      expect(calls, 1);
    });
  }

  test(
    'network uncertainty does not retry and repeat result is explicit',
    () async {
      var calls = 0;
      final api = SaleActions(
        cancelEnabled: true,
        user: () => admin,
        send: (_, _) async {
          calls++;
          throw TimeoutException('offline');
        },
      );
      await expectLater(
        api.cancel(sale(), 'Error'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('sin confirmar'),
          ),
        ),
      );
      expect(calls, 1);
      final repeated = SaleActions(
        cancelEnabled: true,
        user: () => admin,
        send: (_, _) async => {
          'venta_id': 9,
          'estado': 'cancelada',
          'repetida': true,
        },
      );
      expect((await repeated.cancel(sale(), 'Error'))['repetida'], true);
    },
  );

  test(
    'cash reconciliation requires explicit attestation, no movement RPC',
    () async {
      final calls = <String>[];
      final api = SaleActions(
        cashEnabled: true,
        user: () => admin,
        send: (name, p) async {
          calls.add(name);
          expect(p['p_confirmo_sin_salida'], true);
          expect(p['p_nota'], 'Entregado');
          return {'venta_id': 9, 'estado': p['p_estado'], 'repetida': false};
        },
      );
      await expectLater(
        api.reconcile(sale(state: 'cancelada'), 'devuelto', 'Entregado', false),
        throwsStateError,
      );
      await api.reconcile(
        sale(state: 'cancelada'),
        'devuelto',
        'Entregado',
        true,
      );
      await api.reconcile(
        sale(state: 'cancelada'),
        'no_cobrado',
        'Entregado',
        true,
      );
      expect(calls, [
        'caja_conciliar_efectivo_cancelado',
        'caja_conciliar_efectivo_cancelado',
      ]);
    },
  );

  test(
    'summary and fingerprint close exact contracts, stale hash never falls back',
    () async {
      var stale = false;
      final calls = <String>[];
      final api = SaleActions(
        cashEnabled: true,
        user: () => admin,
        send: (name, p) async {
          calls.add(name);
          if (name == 'caja_resumen_turno') return summary();
          expect(p, {
            'p_turno_id': 3,
            'p_huella': 'first',
            'p_efectivo_contado': 125.0,
            'p_notas': 'Corte',
          });
          if (stale) {
            throw const PostgrestException(message: 'Cambió', code: '40001');
          }
          return 3;
        },
      );
      final s = await api.summary(3);
      expect(s['total_neto'], 100);
      expect(await api.close(3, s['huella'], 125, 'Corte'), 3);
      stale = true;
      await expectLater(
        api.close(3, 'first', 125, 'Corte'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('confirma nuevamente'),
          ),
        ),
      );
      expect(calls, [
        'caja_resumen_turno',
        'caja_cerrar_turno_verificado',
        'caja_cerrar_turno_verificado',
      ]);
    },
  );

  test(
    'cancelled totals excluded, original CSV amount retained and valid income zero',
    () {
      final rows = [local(), local(cancelled: true)];
      final metrics = DashboardService.computeMetrics(
        rows,
        DashboardPeriod.todo,
      );
      expect(metrics.totalVendido, 100);
      expect(metrics.totalTickets, 1);
      expect(metrics.totalEfectivo, 100);
      final csv = ExportService.generateSalesCsv(rows);
      expect(csv, contains('cancelada,0.00,"Error de pedido"'));
      expect(rows.last.total, 100);
      expect(
        ExportService.generateWhatsAppSalesReport(rows, 'Prueba'),
        contains('VENTA TOTAL:* \$100.00'),
      );
      expect(
        Venta.fromJson(local().toJson()..remove('status')).isCancelled,
        false,
      );
    },
  );

  test(
    'server state updates local record by ID without deleting or duplicating',
    () async {
      SharedPreferences.setMockInitialValues({
        'texas_sales': jsonEncode([local().toJson()]),
      });
      final service = SalesService.forTesting(remoteWriter: (_) async {});
      await service.applyRemoteStates([
        {...sale(state: 'cancelada'), 'cancelacion_motivo': 'Error'},
      ]);
      await service.applyRemoteStates([
        {...sale(state: 'cancelada'), 'cancelacion_motivo': 'Error'},
      ]);
      expect(service.sales.length, 1);
      expect(service.sales.single.isCancelled, true);
      expect(service.sales.single.total, 100);
    },
  );

  testWidgets('cancelled ticket keeps amount and reason', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TicketDialog(venta: local(cancelled: true))),
      ),
    );
    expect(find.text('Venta CANCELADA'), findsOneWidget);
    expect(find.textContaining('Error de pedido'), findsOneWidget);
    expect(find.text('\$100.00'), findsWidgets);
  });

  testWidgets('admin can initiate, cashier and other branch cannot', (
    tester,
  ) async {
    for (final user in [admin, cashier]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SaleActionsPanel(
              key: ValueKey(user.id),
              sale: sale(),
              onChanged: () async {},
              actions: SaleActions(cancelEnabled: true, user: () => user),
            ),
          ),
        ),
      );
      expect(
        find.text('Cancelar venta'),
        user.isAdmin ? findsOneWidget : findsNothing,
      );
    }
    expect(
      SaleActions(
        user: () => admin,
      ).canManage({...sale(), 'sucursal_id': 'sur'}),
      false,
    );
  });

  testWidgets(
    'stale close refreshes and requires another explicit confirmation',
    (tester) async {
      var reads = 0, closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VerifiedCashDialog(
              load: () async => summary(++reads == 1 ? 'first' : 'second'),
              close: (hash, cash, notes) async {
                closes++;
                expect(hash, 'first');
                throw StateError('Los importes cambiaron');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total neto: \$100.00'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '125');
      await tester.tap(find.text('Confirmar cierre'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(closes, 1);
      expect(find.textContaining('Los importes cambiaron'), findsOneWidget);
    },
  );
}
