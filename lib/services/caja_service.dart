import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/corte_caja.dart';
import '../models/venta.dart';
import '../models/sale_context.dart';
import 'user_role_service.dart';

class CajaService extends ChangeNotifier {
  static final CajaService _instance = CajaService._internal();
  factory CajaService() => _instance;
  CajaService._internal();

  @visibleForTesting
  CajaService.forTesting();

  CorteCaja? _activeCorte;
  List<CorteCaja> _cortesHistory = [];
  bool _initialized = false;
  SaleContext? _saleContext;

  SaleContext? get saleContext => _saleContext;
  bool get isBranchLocked => isCajaOpen && _saleContext != null;

  bool get isCajaOpen => _activeCorte != null && !_activeCorte!.isClosed;
  CorteCaja? get activeCorte => _activeCorte;
  List<CorteCaja> get cortesHistory => List.unmodifiable(_cortesHistory);

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    final contextString = prefs.getString('texas_staff_context');
    if (contextString != null) {
      try {
        _saleContext = SaleContext.fromJson(jsonDecode(contextString) as Map<String, dynamic>);
      } catch (_) {
        _saleContext = null;
      }
    }

    final activeString = prefs.getString('texas_active_corte');
    if (activeString != null && activeString.isNotEmpty) {
      try {
        _activeCorte = CorteCaja.fromJson(jsonDecode(activeString) as Map<String, dynamic>);
      } catch (e) {
        _activeCorte = null;
      }
    }

    final historyString = prefs.getString('texas_cortes_history');
    if (historyString != null && historyString.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(historyString);
        _cortesHistory = list.map((item) => CorteCaja.fromJson(item as Map<String, dynamic>)).toList();
        _cortesHistory.sort((a, b) => b.openedAt.compareTo(a.openedAt));
      } catch (e) {
        _cortesHistory = [];
      }
    }

    _initialized = true;
    // Recover the opening selection if the separate active selection is absent.
    // The opening employee is not used to rewrite any historical sale.
    if (isCajaOpen) {
      final opening = _activeCorte!.openingContext;
      if (_saleContext == null || (opening != null && _saleContext!.branchId != opening.branchId)) {
        _saleContext = opening;
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_saleContext != null) {
      await prefs.setString('texas_staff_context', jsonEncode(_saleContext!.toJson()));
    } else {
      await prefs.remove('texas_staff_context');
    }
    if (_activeCorte != null) {
      await prefs.setString('texas_active_corte', jsonEncode(_activeCorte!.toJson()));
    } else {
      await prefs.remove('texas_active_corte');
    }

    final historyJson = jsonEncode(_cortesHistory.map((c) => c.toJson()).toList());
    await prefs.setString('texas_cortes_history', historyJson);
  }

  Future<void> updateSaleContext(SaleContext selection) async {
    if (isBranchLocked && selection.branchId != _saleContext!.branchId) {
      throw StateError('La sucursal se conserva hasta cerrar el turno.');
    }
    _saleContext = selection;
    await _save();
    notifyListeners();
  }

  Future<void> abrirCaja(double initialCash, {required SaleContext saleContext}) async {
    UserRoleService().requireAdmin();
    if (isCajaOpen) throw StateError('Ya hay un turno abierto.');
    _saleContext = saleContext;
    _activeCorte = CorteCaja(
      id: 'corte_${DateTime.now().millisecondsSinceEpoch}',
      openingContext: saleContext,
      openedAt: DateTime.now(),
      initialCash: initialCash,
      expectedCash: initialCash,
      movimientos: [],
      isClosed: false,
    );
    await _save();
    notifyListeners();
  }

  Future<void> registrarMovimiento({
    required String type, // 'entrada' or 'salida'
    required double amount,
    required String concept,
  }) async {
    UserRoleService().requireAdmin();
    if (_activeCorte == null) return;

    final newMov = CajaMovimiento(
      id: 'mov_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      amount: amount,
      concept: concept,
      timestamp: DateTime.now(),
    );

    final updatedMovs = List<CajaMovimiento>.from(_activeCorte!.movimientos)..add(newMov);
    double newCashIn = _activeCorte!.cashIn;
    double newCashOut = _activeCorte!.cashOut;

    if (type == 'entrada') {
      newCashIn += amount;
    } else {
      newCashOut += amount;
    }

    _activeCorte = CorteCaja(
      id: _activeCorte!.id,
      openingContext: _activeCorte!.openingContext,
      openedAt: _activeCorte!.openedAt,
      initialCash: _activeCorte!.initialCash,
      cashIn: newCashIn,
      cashOut: newCashOut,
      cashSales: _activeCorte!.cashSales,
      cardSales: _activeCorte!.cardSales,
      transferSales: _activeCorte!.transferSales,
      totalSales: _activeCorte!.totalSales,
      ordersCount: _activeCorte!.ordersCount,
      expectedCash: _activeCorte!.initialCash + newCashIn - newCashOut + _activeCorte!.cashSales,
      movimientos: updatedMovs,
      notes: _activeCorte!.notes,
      isClosed: false,
    );

    await _save();
    notifyListeners();
  }

  CorteCaja computeLiveShift(List<Venta> allSales) {
    if (_activeCorte == null) {
      return CorteCaja(
        id: 'none',
        openedAt: DateTime.now(),
        initialCash: 0,
        expectedCash: 0,
      );
    }

    // Filter sales since caja was opened
    final shiftSales = allSales.where((s) => s.timestamp.isAfter(_activeCorte!.openedAt)).toList();

    double cashSales = 0.0;
    double cardSales = 0.0;
    double transferSales = 0.0;

    for (final s in shiftSales) {
      if (s.paymentMethod == 'Efectivo') {
        cashSales += s.total;
      } else if (s.paymentMethod == 'Tarjeta') {
        cardSales += s.total;
      } else if (s.paymentMethod == 'Transferencia') {
        transferSales += s.total;
      }
    }

    final totalSales = cashSales + cardSales + transferSales;
    final expectedCash = _activeCorte!.initialCash + _activeCorte!.cashIn - _activeCorte!.cashOut + cashSales;

    return CorteCaja(
      id: _activeCorte!.id,
      openingContext: _activeCorte!.openingContext,
      openedAt: _activeCorte!.openedAt,
      closedAt: _activeCorte!.closedAt,
      initialCash: _activeCorte!.initialCash,
      cashIn: _activeCorte!.cashIn,
      cashOut: _activeCorte!.cashOut,
      cashSales: cashSales,
      cardSales: cardSales,
      transferSales: transferSales,
      totalSales: totalSales,
      ordersCount: shiftSales.length,
      expectedCash: expectedCash,
      notes: _activeCorte!.notes,
      isClosed: _activeCorte!.isClosed,
      movimientos: _activeCorte!.movimientos,
    );
  }

  Future<CorteCaja> cerrarCaja({
    required double actualCashCounted,
    required String notes,
    required List<Venta> allSales,
  }) async {
    UserRoleService().requireAdmin();
    final live = computeLiveShift(allSales);
    final diff = actualCashCounted - live.expectedCash;

    final closedCorte = CorteCaja(
      id: live.id,
      openingContext: live.openingContext,
      openedAt: live.openedAt,
      closedAt: DateTime.now(),
      initialCash: live.initialCash,
      cashIn: live.cashIn,
      cashOut: live.cashOut,
      cashSales: live.cashSales,
      cardSales: live.cardSales,
      transferSales: live.transferSales,
      totalSales: live.totalSales,
      ordersCount: live.ordersCount,
      expectedCash: live.expectedCash,
      actualCashCounted: actualCashCounted,
      difference: diff,
      notes: notes,
      isClosed: true,
      movimientos: live.movimientos,
    );

    _cortesHistory.insert(0, closedCorte);
    _activeCorte = null;
    _saleContext = null;
    await _save();
    notifyListeners();
    return closedCorte;
  }
}
