import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import '../models/producto.dart';
import '../models/sale_context.dart';
import 'db_service.dart';

class SalesService extends ChangeNotifier {
  static final SalesService _instance = SalesService._internal();
  factory SalesService() => _instance;
  SalesService._internal() : _remoteWriter = DbService.guardarVenta;

  @visibleForTesting
  SalesService.forTesting({required Future<void> Function(Venta) remoteWriter})
      : _remoteWriter = remoteWriter;

  final Future<void> Function(Venta) _remoteWriter;

  List<Venta> _sales = [];
  int _lastTicketNumber = 1000;
  bool _initialized = false;

  List<Venta> get sales => List.unmodifiable(_sales);

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _lastTicketNumber = prefs.getInt('texas_last_ticket') ?? 1000;
    
    final jsonString = prefs.getString('texas_sales');
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(jsonString);
        _sales = list.map((item) => Venta.fromJson(item as Map<String, dynamic>)).toList();
        _sales.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } catch (e) {
        _sales = [];
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('texas_last_ticket', _lastTicketNumber);
    final jsonString = jsonEncode(_sales.map((s) => s.toJson()).toList());
    await prefs.setString('texas_sales', jsonString);
  }

  int getNextTicketNumber() {
    return _lastTicketNumber + 1;
  }

  Future<Venta> registerSale({
    required SaleContext saleContext,
    required List<VentaItem> items,
    required double subtotal,
    required double discount,
    required double total,
    required String paymentMethod,
    double cashGiven = 0.0,
    double changeReturned = 0.0,
    String notes = '',
    String orderType = 'Comer aquí',
    String? tableNumber,
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
  }) async {
    _lastTicketNumber++;
    final newSale = Venta(
      id: 'txs_${DateTime.now().millisecondsSinceEpoch}',
      ticketNumber: _lastTicketNumber,
      items: items.map((item) => VentaItem(
        product: item.product,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        selectedExtras: List.from(item.selectedExtras),
        removedIngredients: List.from(item.removedIngredients),
        notes: item.notes,
      )).toList(),
      subtotal: subtotal,
      discount: discount,
      total: total,
      paymentMethod: paymentMethod,
      cashGiven: cashGiven,
      changeReturned: changeReturned,
      timestamp: DateTime.now(),
      saleContext: saleContext,
      notes: notes,
      orderType: orderType,
      tableNumber: tableNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: deliveryAddress,
    );

    _sales.insert(0, newSale);
    await _save();
    notifyListeners();
    _remoteWriter(newSale);
    return newSale;
  }

  Future<void> cancelSale(String id) async {
    _sales.removeWhere((s) => s.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> clearAllSales() async {
    _sales.clear();
    _lastTicketNumber = 1000;
    await _save();
    notifyListeners();
  }

  Future<void> loadSampleSales(List<Producto> catalog) async {
    if (catalog.isEmpty) return;
    final now = DateTime.now();
    final pClassic = catalog.firstWhere((p) => p.id == 'hamb_texana_clasica', orElse: () => catalog[0]);
    final pSuper = catalog.firstWhere((p) => p.id == 'hamb_super_texana', orElse: () => catalog[1]);
    final pCombo = catalog.firstWhere((p) => p.id == 'combo_pollo_especial', orElse: () => catalog[0]);
    final pWalter = catalog.firstWhere((p) => p.id == 'hamb_walter_especial', orElse: () => catalog[0]);

    final samples = [
      Venta(
        id: 'sample_1',
        ticketNumber: 1001,
        items: [
          VentaItem(product: pClassic, quantity: 2, unitPrice: pClassic.price),
          VentaItem(product: pCombo, quantity: 1, unitPrice: pCombo.price),
        ],
        subtotal: (pClassic.price * 2) + pCombo.price,
        discount: 0,
        total: (pClassic.price * 2) + pCombo.price,
        paymentMethod: 'Efectivo',
        cashGiven: 400.0,
        changeReturned: 400.0 - ((pClassic.price * 2) + pCombo.price),
        timestamp: DateTime(now.year, now.month, now.day, 13, 15),
      ),
      Venta(
        id: 'sample_2',
        ticketNumber: 1002,
        items: [
          VentaItem(product: pSuper, quantity: 2, unitPrice: pSuper.price),
        ],
        subtotal: pSuper.price * 2,
        discount: 0,
        total: pSuper.price * 2,
        paymentMethod: 'Tarjeta',
        timestamp: DateTime(now.year, now.month, now.day, 14, 30),
      ),
      Venta(
        id: 'sample_3',
        ticketNumber: 1003,
        items: [
          VentaItem(product: pWalter, quantity: 1, unitPrice: pWalter.price),
          VentaItem(product: pClassic, quantity: 1, unitPrice: pClassic.price),
        ],
        subtotal: pWalter.price + pClassic.price,
        discount: 0,
        total: pWalter.price + pClassic.price,
        paymentMethod: 'Transferencia',
        timestamp: DateTime(now.year, now.month, now.day, 16, 45),
      ),
    ];

    _sales.addAll(samples);
    _sales.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _lastTicketNumber = 1003;
    await _save();
    notifyListeners();
  }
}
