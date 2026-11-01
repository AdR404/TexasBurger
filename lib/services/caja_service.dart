import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/corte_caja.dart';
import '../models/venta.dart';
import '../models/sale_context.dart';
import 'user_role_service.dart';
import 'db_service.dart';
import 'caja_repository.dart';

class CajaService extends ChangeNotifier {
  static final CajaService _instance = CajaService._internal();
  factory CajaService() => _instance;
  CajaService._internal() : _testLocal = false;

  @visibleForTesting
  CajaService.forTesting() : _testLocal = true;
  final bool _testLocal;

  CorteCaja? _activeCorte;
  List<CorteCaja> _cortesHistory = [];
  bool _initialized = false;
  SaleContext? _saleContext;

  final CajaRepository _remote = CajaRepository();
  CajaSnapshot? _snapshot;
  String? _snapshotActor;
  String? remoteError;
  bool remoteBusy = false;
  int _remoteRevision = 0;
  bool get remoteMode => !_testLocal && DbService.onlineSalesEnabled && DbService.isSyncEnabled;
  bool get remoteReady => _validSnapshot;
  bool get _validSnapshot => _snapshot != null &&
      _snapshotActor == DbService.session?.validOperatorId && _snapshotActor != null;

  void invalidateRemote() {
    _remoteRevision++;
    _snapshot = null;
    _snapshotActor = null;
    remoteError = null;
    if (!remoteMode && _activeCorte != null && !_activeCorte!.isClosed &&
        _activeCorte!.openingContext != null &&
        _saleContext?.branchId != _activeCorte!.openingContext!.branchId) {
      _saleContext = _activeCorte!.openingContext;
    }
    notifyListeners();
  }

  Future<void> refreshRemote() async {
    if (!remoteMode || remoteBusy) return;
    final revision = ++_remoteRevision;
    remoteBusy = true;
    _snapshot = null;
    remoteError = null;
    notifyListeners();
    try {
      final actor = DbService.session?.validOperatorId;
      final branch = _saleContext?.branchId;
      if (branch == null) throw StateError('Selecciona sucursal y empleado para consultar Caja.');
      final snapshot = await _remote.load(branch);
      if (revision != _remoteRevision || !remoteMode || branch != _saleContext?.branchId || actor != DbService.session?.validOperatorId) return;
      _snapshot = snapshot;
      _snapshotActor = actor;
    } catch (e) {
      if (revision == _remoteRevision) remoteError = _remoteMessage(e);
    } finally {
      remoteBusy = false;
      notifyListeners();
    }
  }

  String _remoteMessage(Object error) => error is StateError
      ? error.message.toString()
      : 'No se pudo consultar u operar Caja remota. Revisa conexión, sesión y permisos. No se utilizaron importes locales.';

  Future<T> _remoteOperation<T>(Future<T> Function() operation) async {
    if (remoteBusy) throw StateError('Espera a que termine la operación de Caja.');
    remoteBusy = true;
    remoteError = null;
    notifyListeners();
    try {
      return await operation();
    } catch (e) {
      _snapshot = null;
      remoteError = _remoteMessage(e);
      throw StateError(remoteError!);
    } finally {
      remoteBusy = false;
      notifyListeners();
    }
  }

  Future<void> _reloadConfirmed(String branch) async {
    try {
      final actor = DbService.session?.validOperatorId;
      final snapshot = await _remote.load(branch);
      if (!remoteMode || branch != _saleContext?.branchId || actor != DbService.session?.validOperatorId) throw StateError('Cambió la sesión o sucursal');
      _snapshot = snapshot;
      _snapshotActor = actor;
    } catch (_) {
      throw StateError('La operación fue confirmada por Supabase, pero no se pudo actualizar Caja. No repitas la operación; pulsa Actualizar.');
    }
  }

  Future<CorteCaja> remoteClosedDetails(CorteCaja turn) => _remote.closed(int.parse(turn.id), turn.openingContext!.branchId);

  SaleContext? get saleContext => _saleContext;
  bool get isBranchLocked => isCajaOpen && _saleContext != null;

  bool get isCajaOpen => activeCorte != null && !activeCorte!.isClosed;
  CorteCaja? get activeCorte => remoteMode ? (_validSnapshot ? _snapshot!.active : null) : _activeCorte;
  List<CorteCaja> get cortesHistory => remoteMode
      ? (_validSnapshot ? List.unmodifiable(_snapshot!.history) : const [])
      : List.unmodifiable(_cortesHistory);

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
    // Si hay un turno abierto sin selección activa en memoria, recupera la del inicio del turno
    if (!remoteMode && _activeCorte != null && !_activeCorte!.isClosed) {
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
    if (remoteMode) invalidateRemote();
    await _save();
    if (remoteMode) await refreshRemote();
    notifyListeners();
  }

  Future<void> abrirCaja(double initialCash, {required SaleContext saleContext}) async {
    UserRoleService().requireAdmin();
    if (remoteMode) {
      await _remoteOperation(() async {
        final prefs = await SharedPreferences.getInstance();
        // Persist only the selection, never remote shifts as local shifts.
        if (!await prefs.setString('texas_staff_context', jsonEncode(saleContext.toJson()))) throw StateError('No se pudo conservar la selección de sucursal.');
        _saleContext = saleContext;
        await _remote.open(saleContext, initialCash);
        await _reloadConfirmed(saleContext.branchId);
      });
      return;
    }
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
    if (remoteMode) {
      final turn = activeCorte;
      if (turn == null || remoteError != null) throw StateError('Actualiza Caja antes de registrar un movimiento.');
      await _remoteOperation(() async {
        await _remote.movement(turn, type, amount, concept);
        await _reloadConfirmed(turn.openingContext!.branchId);
      });
      return;
    }
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
    if (remoteMode) {
      return activeCorte ?? CorteCaja(id: 'none', openedAt: DateTime.now(), initialCash: 0, expectedCash: 0);
    }
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
    if (remoteMode) {
      final turn = activeCorte;
      if (turn == null || remoteError != null) throw StateError('Actualiza Caja antes de cerrar el turno.');
      return _remoteOperation(() async {
        final id = await _remote.close(turn, actualCashCounted, notes);
        CorteCaja closed;
        try {
          closed = await _remote.closed(id, turn.openingContext!.branchId);
        } catch (_) {
          throw StateError('Cierre confirmado, pero no se pudo recuperar el corte. No repitas el cierre; actualiza Caja.');
        }
        await _reloadConfirmed(turn.openingContext!.branchId);
        return closed;
      });
    }
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
