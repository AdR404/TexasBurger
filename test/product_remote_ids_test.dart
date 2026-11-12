import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/services/bootstrap_service.dart';
import 'package:texas_burger/services/product_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = BootstrapService.getDefaultProducts().first;
  const key = 'texas_product_remote_ids_v1_main';
  Map<String, dynamic> row(int id, String name, {bool active = true}) => {
    'id': id,
    'nombre': name,
    'activo': active,
  };

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legacy catalog is untouched and binding survives restart and rename',
    () async {
      final catalog = jsonEncode([original.toJson()]);
      SharedPreferences.setMockInitialValues({
        'texas_products': catalog,
        'texas_sales': 'historical data',
      });
      final service = ProductService.forTesting();
      expect(
        await service.resolveRemoteId(
          product: original,
          projectId: 'main',
          lookup: (id, name) async {
            expect(id, isNull);
            expect(name, original.name);
            return [row(123, name)];
          },
        ),
        123,
      );
      final restarted = ProductService.forTesting();
      expect(
        await restarted.resolveRemoteId(
          product: original.copyWith(name: 'Nuevo nombre local'),
          projectId: 'main',
          lookup: (id, name) async {
            expect(id, 123);
            return [row(123, 'Nuevo nombre remoto')];
          },
        ),
        123,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(key)!), {original.id: 123});
      expect(prefs.getString('texas_products'), catalog);
      expect(prefs.getString('texas_sales'), 'historical data');
      expect(Producto.fromJson(original.toJson()).id, original.id);
    },
  );

  for (final scenario in [
    'missing',
    'ambiguous',
    'similar',
    'inactive',
    'invalid id',
  ]) {
    test('rejects $scenario without persisting a guessed ID', () async {
      final rows = switch (scenario) {
        'missing' => <Map<String, dynamic>>[],
        'ambiguous' => [row(1, original.name), row(2, original.name)],
        'similar' => [row(1, '${original.name} ')],
        'inactive' => [row(1, original.name, active: false)],
        _ => [row(0, original.name)],
      };
      await expectLater(
        ProductService.forTesting().resolveRemoteId(
          product: original,
          projectId: 'main',
          lookup: (_, _) async => rows,
        ),
        throwsStateError,
      );
      expect((await SharedPreferences.getInstance()).getString(key), isNull);
    });
  }

  test(
    'missing or inactive linked ID never falls back to a new name match',
    () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({original.id: 123}),
      });
      for (final rows in [
        <Map<String, dynamic>>[],
        [row(123, original.name, active: false)],
        [row(456, original.name)],
      ]) {
        var calls = 0;
        await expectLater(
          ProductService.forTesting().resolveRemoteId(
            product: original,
            projectId: 'main',
            lookup: (id, _) async {
              calls++;
              expect(id, 123);
              return rows;
            },
          ),
          throwsStateError,
        );
        expect(calls, 1);
        expect(
          jsonDecode((await SharedPreferences.getInstance()).getString(key)!),
          {original.id: 123},
        );
      }
    },
  );

  test('projects have independent IDs', () async {
    final service = ProductService.forTesting();
    for (final project in ['main', 'test']) {
      expect(
        await service.resolveRemoteId(
          product: original,
          projectId: project,
          lookup: (id, name) async {
            expect(id, isNull);
            return [row(project == 'main' ? 1 : 2, name)];
          },
        ),
        project == 'main' ? 1 : 2,
      );
    }
  });

  test('concurrent bindings preserve both products', () async {
    final service = ProductService.forTesting();
    final other = BootstrapService.getDefaultProducts()[1];
    await Future.wait([
      service.resolveRemoteId(
        product: original,
        projectId: 'main',
        lookup: (_, name) async => [row(1, name)],
      ),
      service.resolveRemoteId(
        product: other,
        projectId: 'main',
        lookup: (_, name) async => [row(2, name)],
      ),
    ]);
    expect(
      jsonDecode((await SharedPreferences.getInstance()).getString(key)!),
      {original.id: 1, other.id: 2},
    );
  });

  test('two local products cannot silently share a remote identity', () async {
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({'another_local_id': 123}),
    });
    await expectLater(
      ProductService.forTesting().resolveRemoteId(
        product: original,
        projectId: 'main',
        lookup: (_, name) async => [row(123, name)],
      ),
      throwsStateError,
    );
  });

  test('corrupt mapping is retained and no lookup is attempted', () async {
    SharedPreferences.setMockInitialValues({key: '{"broken": -1}'});
    await expectLater(
      ProductService.forTesting().resolveRemoteId(
        product: original,
        projectId: 'main',
        lookup: (_, _) async => fail('Must not guess a new binding'),
      ),
      throwsStateError,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(key),
      '{"broken": -1}',
    );
  });
}
