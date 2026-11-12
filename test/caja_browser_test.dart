import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:texas_burger/models/sale_context.dart';
import 'package:texas_burger/services/caja_repository.dart';
import 'package:texas_burger/services/caja_service.dart';
import 'support/auth_fixtures.dart';

// Only the two clock properties used by the guard; independent of host timezone.
class TestClock implements DateTime {
  TestClock(this.instant, [this.offset = const Duration(hours: -6)]);
  final DateTime instant;
  final Duration offset;
  @override
  Duration get timeZoneOffset => offset;
  @override
  DateTime toUtc() => instant.toUtc();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = Uri.parse('https://example.invalid/auth/v1/health');
  final clock = TestClock(DateTime.utc(2026, 11, 12, 18));
  final headers = {'date': 'Thu, 12 Nov 2026 18:00:00 GMT'};
  tearDown(clearTestSession);

  test('clock uses portable HEAD client without auth headers', () async {
    final client = MockClient((request) async {
      expect(request.method, 'HEAD');
      expect(request.url, endpoint);
      expect(request.headers.containsKey('authorization'), false);
      expect(request.headers.containsKey('apikey'), false);
      return http.Response('', 200, headers: headers);
    });
    addTearDown(client.close);
    expect(await CajaRepository.checkDeviceClock(client: client, endpoint: endpoint, now: () => clock), clock.toUtc());
  });

  test('missing or CORS-hidden Date blocks instead of trusting device clock', () async {
    final client = MockClient((_) async => http.Response('', 200));
    addTearDown(client.close);
    await expectLater(CajaRepository.checkDeviceClock(client: client, endpoint: endpoint, now: () => clock),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('cabecera Date'))));
  });

  test('timezone and inaccurate clock guards remain enforced', () async {
    var calls = 0;
    final client = MockClient((_) async { calls++; return http.Response('', 200, headers: headers); });
    addTearDown(client.close);
    await expectLater(CajaRepository.checkDeviceClock(client: client, endpoint: endpoint,
      now: () => TestClock(clock.instant, Duration.zero)), throwsStateError);
    expect(calls, 0);
    await expectLater(CajaRepository.checkDeviceClock(client: client, endpoint: endpoint,
      now: () => TestClock(clock.instant.add(const Duration(minutes: 2)))), throwsStateError);
  });

  for (final branch in ['norte', 'perimetral_sur']) {
    test('load empty Caja does not check clock or open a turn ($branch)', () async {
      authenticateAsTestUser(branchId: branch == 'norte' ? branch : null);
      final calls = <String>[];
      final transport = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(jsonEncode(request.url.path.endsWith('inventario_admins')
          ? [{'user_id': 'test-admin'}] : []), 200, request: request, headers: {'content-type':'application/json'});
      });
      final client = SupabaseClient('https://example.invalid', 'test', httpClient: transport);
      addTearDown(client.dispose);
      final repository = CajaRepository(client: client, actor: () => 'test-admin',
        checkedNow: () async => throw StateError('Clock must not run during empty load'));
      final snapshot = await repository.load(branch);
      expect(snapshot.active, isNull);
      expect(snapshot.history, isEmpty);
      expect(calls, ['GET /rest/v1/inventario_admins', 'GET /rest/v1/caja_turnos', 'GET /rest/v1/caja_turnos']);
    });
  }

  test('opening reaches RPC after clock guard; failed guard never sends RPC', () async {
    authenticateAsTestUser();
    const selection = SaleContext(branchId: 'norte', branchName: 'Norte',
      employeeId: 'demo_sofia_reyes', employeeName: 'Sofía Reyes');
    CajaService().setOperatorContext(selection);
    var rpcCalls = 0;
    final transport = MockClient((request) async {
      Object response = [];
      if (request.url.path.endsWith('inventario_admins')) response = [{'user_id':'test-admin'}];
      if (request.url.path.endsWith('rpc/caja_abrir_turno')) {
        rpcCalls++;
        expect(jsonDecode(request.body)['p_sucursal_id'], 'norte');
        response = 17;
      }
      return http.Response(jsonEncode(response), 200, request: request, headers: {'content-type':'application/json'});
    });
    final client = SupabaseClient('https://example.invalid', 'test', httpClient: transport);
    addTearDown(client.dispose);
    final clockClient = MockClient((_) async => http.Response('', 200, headers: headers));
    addTearDown(clockClient.close);
    final repository = CajaRepository(client: client, actor: () => 'test-admin', checkedNow: () =>
      CajaRepository.checkDeviceClock(client: clockClient, endpoint: endpoint, now: () => clock));
    expect(await repository.open(selection, 100), 17);
    final blocked = CajaRepository(client: client, actor: () => 'test-admin',
      checkedNow: () async => throw StateError('Unverified clock'));
    await expectLater(blocked.open(selection, 100), throwsStateError);
    expect(rpcCalls, 1);
  });

  test('diagnostics identify failed stage but never log response messages or details', () {
    final messages = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) { messages.add(message ?? ''); };
    try {
      CajaRepository.debugFailure('load.turnos.cerrados.select',
        const PostgrestException(code: '42501', message: 'secret', details: 'token', hint: 'private'),
        StackTrace.fromString('caja_repository.dart:180:9 secret-url'));
      expect(messages.join(), contains('load.turnos.cerrados.select'));
      expect(messages.join(), contains('42501'));
      expect(messages.join(), isNot(contains('secret')));
      expect(messages.join(), isNot(contains('token')));
      expect(messages.join(), isNot(contains('private')));
    } finally { debugPrint = original; }
  });
}
