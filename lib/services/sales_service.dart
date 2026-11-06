import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import '../models/sale_context.dart';
import 'db_service.dart';
import 'user_role_service.dart';

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
  // Avoid overlapping writes to the existing SharedPreferences history.
  Future<void> _writes = Future<void>.value();
  Future<T> _serialize<T>(Future<T> Function() action) {
    final task = _writes.then((_) => action());
    _writes = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  List<Venta> get sales => List.unmodifiable(_sales);

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _lastTicketNumber = prefs.getInt('texas_last_ticket') ?? 1000;

    final jsonString = prefs.getString('texas_sales');
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(jsonString);
        _sales = list
            .map((item) => Venta.fromJson(item as Map<String, dynamic>))
            .toList();
        _sales.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } catch (e) {
        throw StateError(
          'No se pudo leer el historial local; no se sobrescribirá.',
        );
      }
    }
    for (final sale in _sales) {
      if (sale.ticketNumber > _lastTicketNumber) {
        _lastTicketNumber = sale.ticketNumber;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setInt('texas_last_ticket', _lastTicketNumber)) {
      throw StateError('No se pudo guardar la numeración');
    }
    final jsonString = jsonEncode(_sales.map((s) => s.toJson()).toList());
    if (!await prefs.setString('texas_sales', jsonString)) {
      throw StateError('No se pudo guardar el historial');
    }
  }

  int getNextTicketNumber() {
    return _lastTicketNumber + 1;
  }

  Future<Venta> registerSale({
    required SaleContext saleContext,
    required List<VentaItem> items,
    required double subtotal,
    required double discount,
    double? iva,
    double? ivaRate,
    bool? ivaIncluded,
    String? discountCode,
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
  }) => _serialize(() async {
    final newSale = Venta(
      id: 'txs_${DateTime.now().microsecondsSinceEpoch}_${_lastTicketNumber + 1}',
      ticketNumber: _lastTicketNumber + 1,
      items: items
          .map(
            (item) => VentaItem(
              product: item.product,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              selectedExtras: List.from(item.selectedExtras),
              removedIngredients: List.from(item.removedIngredients),
              notes: item.notes,
            ),
          )
          .toList(),
      subtotal: subtotal,
      discount: discount,
      iva: iva,
      ivaRate: ivaRate,
      ivaIncluded: ivaIncluded,
      discountCode: discountCode,
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

    await _remoteWriter(newSale);
    _lastTicketNumber = newSale.ticketNumber;
    _sales.insert(0, newSale);
    try {
      await _save();
    } catch (_) {
      if (DbService.onlineSalesEnabled && DbService.isSyncEnabled) {
        notifyListeners();
        throw StateError('Venta registrada en Supabase, pero falló el historial local. No repitas el cobro.');
      }
      _sales.removeWhere((sale) => sale.id == newSale.id);
      rethrow;
    }
    notifyListeners();
    return newSale;
  });

  Future<void> cancelSale(String id) async {
    UserRoleService().requireAdmin();
    _sales.removeWhere((s) => s.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> clearAllSales() async {
    UserRoleService().requireAdmin();
    _sales.clear();
    _lastTicketNumber = 1000;
    await _save();
    notifyListeners();
  }

}
