import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/services/bootstrap_service.dart';
import 'package:texas_burger/services/product_service.dart';

// Synthetic identity fixtures only; these are not real products or recipes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final product = BootstrapService.getDefaultProducts().first;
  const key = 'texas_product_remote_ids_v1_main';
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cleared local storage requires a new exact match, not an old ID',
    () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({product.id: 10}),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await expectLater(
        ProductService.forTesting().resolveRemoteId(
          product: product,
          projectId: 'main',
          lookup: (id, name) async {
            expect(id, isNull);
            return [
              {'id': 10, 'nombre': 'Renamed on another device', 'activo': true},
            ];
          },
        ),
        throwsStateError,
      );
      expect(prefs.getString(key), isNull);
    },
  );

  test(
    'remote edits retain identity and do not overwrite local price or promo',
    () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({product.id: 10}),
      });
      final before = product.toJson();
      expect(
        await ProductService.forTesting().resolveRemoteId(
          product: product,
          projectId: 'main',
          lookup: (id, name) async {
            expect(id, 10);
            return [
              {
                'id': 10,
                'nombre': 'Renamed remotely',
                'activo': true,
                'precio': 9999,
              },
            ];
          },
        ),
        10,
      );
      expect(product.toJson(), before);
    },
  );

  test('concurrent local aliases cannot claim the same remote ID', () async {
    final service = ProductService.forTesting();
    final first = service.resolveRemoteId(
      product: product,
      projectId: 'main',
      lookup: (_, name) async => [
        {'id': 10, 'nombre': name, 'activo': true},
      ],
    );
    final second = service.resolveRemoteId(
      product: product.copyWith(id: 'another_local_identity'),
      projectId: 'main',
      lookup: (_, name) async => [
        {'id': 10, 'nombre': name, 'activo': true},
      ],
    );
    await expectLater(second, throwsStateError);
    expect(await first, 10);
    expect(
      jsonDecode((await SharedPreferences.getInstance()).getString(key)!),
      {product.id: 10},
    );
  });
}
