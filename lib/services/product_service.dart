import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/producto.dart';
import 'bootstrap_service.dart';

class ProductService extends ChangeNotifier {
  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  List<Producto> _products = [];
  bool _initialized = false;

  List<Producto> get products => List.unmodifiable(_products);
  List<Producto> get availableProducts => _products.where((p) => p.isAvailable).toList();
  List<Producto> get promotions => _products.where((p) => p.isPromo && p.isAvailable).toList();
  List<Producto> get burgers => _products.where((p) => p.category == 'Hamburguesas' && p.isAvailable).toList();
  List<Producto> get complements => _products.where((p) => p.category == 'Complementos' && p.isAvailable).toList();
  List<Producto> get drinks => _products.where((p) => p.category == 'Bebidas' && p.isAvailable).toList();

  List<String> get categories => const ['Todas', 'Hamburguesas', 'Complementos', 'Bebidas', 'Promociones'];

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('texas_products');
    
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(jsonString);
        _products = list.map((item) => Producto.fromJson(item as Map<String, dynamic>)).toList();
        
        // Merge any new default items (like complementos or bebidas) if not present yet
        final defaults = BootstrapService.getDefaultProducts();
        bool addedNew = false;
        for (final def in defaults) {
          final index = _products.indexWhere((p) => p.id == def.id);
          if (index == -1) {
            _products.add(def);
            addedNew = true;
          } else if (_products[index].availableExtras.isEmpty && def.availableExtras.isNotEmpty) {
            // Update available extras if previously empty
            _products[index] = _products[index].copyWith(availableExtras: def.availableExtras);
            addedNew = true;
          }
          // Agrega la ruta de imagen a productos ya guardados que aún no la tienen
          final idx = _products.indexWhere((p) => p.id == def.id);
          if (idx != -1 && _products[idx].imagePath == null && def.imagePath != null) {
            _products[idx] = _products[idx].copyWith(imagePath: def.imagePath);
            addedNew = true;
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
    final index = _products.indexWhere((p) => p.id == id);
    if (index != -1) {
      _products[index] = _products[index].copyWith(price: newPrice);
      await _save();
      notifyListeners();
    }
  }

  Future<void> toggleAvailability(String id) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index != -1) {
      _products[index] = _products[index].copyWith(isAvailable: !_products[index].isAvailable);
      await _save();
      notifyListeners();
    }
  }

  Future<void> addProduct(Producto product) async {
    _products.add(product);
    await _save();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _products = BootstrapService.getDefaultProducts();
    await _save();
    notifyListeners();
  }
}