import 'package:texas_burger/services/user_role_service.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/services/bootstrap_service.dart';
import 'package:texas_burger/services/product_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy products gain images without losing edits or other local data',
    () async {
      final defaults = BootstrapService.getDefaultProducts();
      final edited =
          defaults.first
              .copyWith(
                name: 'Mi promoción',
                price: 175,
                description: 'Descripción editada',
                isAvailable: false,
                promoNote: 'Nota guardada',
              )
              .toJson()
            ..remove('imagePath');
      final customImage = defaults[1].copyWith(
        imagePath: 'assets/images/logo.png',
      );
      final custom = Producto(
        id: 'custom',
        name: 'Creación local',
        description: '',
        price: 44,
        category: 'Bebidas',
      );
      final untouched = {
        'texas_sales': '["historial conservado"]',
        'texas_active_corte': '{"turno":"conservado"}',
        'texas_cortes_history': '["corte conservado"]',
        'texas_config': '{"negocio":"conservado"}',
        'texas_staff_context': '{"empleado":"conservado"}',
      };
      SharedPreferences.setMockInitialValues({
        ...untouched,
        'texas_products': jsonEncode([
          edited,
          customImage.toJson(),
          custom.toJson(),
        ]),
      });
      final service = ProductService.forTesting();
      await service.init();
      final migrated = service.products.singleWhere(
        (p) => p.id == edited['id'],
      );
      expect(migrated.imagePath, 'assets/images/promo_martes.png');
      expect(migrated.toJson()..remove('imagePath'), edited);
      expect(
        service.products.singleWhere((p) => p.id == customImage.id).toJson(),
        customImage.toJson(),
      );
      expect(
        service.products.singleWhere((p) => p.id == custom.id).toJson(),
        custom.toJson(),
      );
      expect(service.products.length, defaults.length + 1);
      expect(
        service.products.map((p) => p.id).toSet().length,
        service.products.length,
      );
      final prefs = await SharedPreferences.getInstance();
      for (final entry in untouched.entries) {
        expect(prefs.getString(entry.key), entry.value);
      }
      final saved = prefs.getString('texas_products');
      final restarted = ProductService.forTesting();
      await restarted.init();
      expect(prefs.getString('texas_products'), saved);
      expect(
        restarted.products.map((p) => p.toJson()).toList(),
        service.products.map((p) => p.toJson()).toList(),
      );
    },
  );

  test(
    'image metadata survives price and availability edits and old JSON loads',
    () async {
      final product = BootstrapService.getDefaultProducts()[1];
      SharedPreferences.setMockInitialValues({
        'texas_products': jsonEncode([product.toJson()]),
      });
      final service = ProductService.forTesting();
      await service.init();
      UserRoleService().loginAdmin('admin', 'admin');
      addTearDown(() => UserRoleService().switchToUser());
      await service.updatePrice(product.id, 160);
      await service.toggleAvailability(product.id);
      final restarted = ProductService.forTesting();
      await restarted.init();
      final saved = restarted.products.singleWhere((p) => p.id == product.id);
      expect(saved.imagePath, 'assets/images/combo_pollo_especial.png');
      expect(saved.price, 160);
      expect(saved.isAvailable, isFalse);
      final legacy = product.toJson()..remove('imagePath');
      expect(Producto.fromJson(legacy).imagePath, isNull);
      expect(Producto.fromJson(legacy).toJson(), legacy);
    },
  );
}
