import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/producto.dart';
import 'bootstrap_service.dart';
import 'user_role_service.dart';

class ProductService extends ChangeNotifier {
  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  @visibleForTesting
  ProductService.forTesting();

  List<Producto> _products = [];
  bool _initialized = false;

  // Separate from catalog snapshots: existing carts/history retain their local ID.
  // A remote numeric ID is meaningful only inside its Supabase project.
  static Future<void> _linkWrites = Future<void>.value();

  Future<int> resolveRemoteId({
    required Producto product,
    required String projectId,
    required Future<List<Map<String, dynamic>>> Function(int? id, String name)
    lookup,
  }) {
    final task = _linkWrites.then((_) async {
      if (projectId.isEmpty || product.id.isEmpty) {
        throw StateError(
          'Falta el proyecto o la identidad local del producto.',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      final key = 'texas_product_remote_ids_v1_$projectId';
      final raw = prefs.getString(key);
      final links = <String, int>{};
      if (raw != null) {
        final dynamic decoded;
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          throw StateError(
            'Correspondencias locales dañadas; requiere revisión.',
          );
        }
        if (decoded is! Map ||
            decoded.entries.any(
              (e) =>
                  e.key is! String || e.value is! int || (e.value as int) <= 0,
            )) {
          throw StateError(
            'Correspondencias locales dañadas; requiere revisión.',
          );
        }
        links.addAll(Map<String, int>.from(decoded));
      }
      final existing = links[product.id];
      final rows = await lookup(existing, product.name);
      if (rows.length != 1 ||
          rows.single['id'] is! int ||
          (rows.single['id'] as int) <= 0 ||
          rows.single['activo'] != true ||
          (existing != null && rows.single['id'] != existing) ||
          (existing == null && rows.single['nombre'] != product.name)) {
        throw StateError(
          existing == null
              ? 'Producto sin correspondencia exacta y única: ${product.name}. Requiere vinculación.'
              : 'El vínculo remoto de ${product.name} no está disponible o activo. Requiere revisión; no se reasignó.',
        );
      }
      final remoteId = rows.single['id'] as int;
      if (links.entries.any(
        (e) => e.key != product.id && e.value == remoteId,
      )) {
        throw StateError(
          'El producto remoto ya está vinculado a otro producto local. Requiere revisión.',
        );
      }
      if (existing == null) {
        links[product.id] = remoteId;
        if (!await prefs.setString(key, jsonEncode(links))) {
          throw StateError(
            'No se pudo conservar la correspondencia del producto. No se envió la venta.',
          );
        }
      }
      return remoteId;
    });
    _linkWrites = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return task;
  }

  List<Producto> get products => List.unmodifiable(_products);
  List<Producto> get availableProducts =>
      _products.where((p) => p.isAvailable).toList();
  List<Producto> get promotions =>
      _products.where((p) => p.isPromo && p.isAvailable).toList();
  List<Producto> get burgers => _products
      .where((p) => p.category == 'Hamburguesas' && p.isAvailable)
      .toList();
  List<Producto> get complements => _products
      .where((p) => p.category == 'Complementos' && p.isAvailable)
      .toList();
  List<Producto> get drinks =>
      _products.where((p) => p.category == 'Bebidas' && p.isAvailable).toList();

  List<String> get categories => const [
    'Todas',
    'Hamburguesas',
    'Complementos',
    'Bebidas',
    'Promociones',
  ];

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('texas_products');

    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(jsonString);
        _products = list
            .map((item) => Producto.fromJson(item as Map<String, dynamic>))
            .toList();

        // Merge any new default items (like complementos or bebidas) if not present yet
        final defaults = BootstrapService.getDefaultProducts();
        bool addedNew = false;
        for (final def in defaults) {
          final index = _products.indexWhere((p) => p.id == def.id);
          if (index == -1) {
            _products.add(def);
            addedNew = true;
          } else {
            final currentProduct = _products[index];
            var updatedProduct = currentProduct;
            // Enrich existing products without replacing their saved fields.
            if (updatedProduct.imagePath == null && def.imagePath != null) {
              updatedProduct = updatedProduct.copyWith(
                imagePath: def.imagePath,
              );
            }
            if (updatedProduct.availableExtras.isEmpty &&
                def.availableExtras.isNotEmpty) {
              updatedProduct = updatedProduct.copyWith(
                availableExtras: def.availableExtras,
              );
            }
            if (!identical(updatedProduct, currentProduct)) {
              _products[index] = updatedProduct;
              addedNew = true;
            }
          }
        }
        if (addedNew) {
          await _save();
        }
      } catch (e) {
        _products = BootstrapService.getDefaultProducts();
        await _save();
      }
    } else {
      _products = BootstrapService.getDefaultProducts();
      await _save();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_products.map((p) => p.toJson()).toList());
    await prefs.setString('texas_products', jsonString);
  }

  Future<void> updatePrice(String id, double newPrice) async {
    UserRoleService().requireAdmin();
    final index = _products.indexWhere((p) => p.id == id);
    if (index != -1) {
      _products[index] = _products[index].copyWith(price: newPrice);
      await _save();
      notifyListeners();
    }
  }

  Future<void> toggleAvailability(String id) async {
    UserRoleService().requireAdmin();
    final index = _products.indexWhere((p) => p.id == id);
    if (index != -1) {
      _products[index] = _products[index].copyWith(
        isAvailable: !_products[index].isAvailable,
      );
      await _save();
      notifyListeners();
    }
  }

  Future<void> addProduct(Producto product) async {
    UserRoleService().requireAdmin();
    _products.add(product);
    await _save();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    UserRoleService().requireAdmin();
    _products = BootstrapService.getDefaultProducts();
    await _save();
    notifyListeners();
  }
}
