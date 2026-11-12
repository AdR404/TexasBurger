import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'app_auth_service.dart';

/// No retries: a transport failure can occur after a committed operation.
class SaleActions {
  static const cancellationsEnabled = bool.fromEnvironment(
    'TEXAS_ENABLE_SALE_CANCELLATIONS',
  );
  static const verifiedCashEnabled = bool.fromEnvironment(
    'TEXAS_ENABLE_VERIFIED_CASH_CLOSE',
  );
  SaleActions({
    Future<dynamic> Function(String, Map<String, dynamic>)? send,
    AuthUser? Function()? user,
    this.cancelEnabled = cancellationsEnabled,
    this.cashEnabled = verifiedCashEnabled,
  }) : _send =
           send ??
           ((name, params) async => Supabase.instance.client
               .rpc(name, params: params)
               .retry(enabled: false)
               .timeout(const Duration(seconds: 20))),
       _user = user ?? (() => AppAuthService().currentUser);
  final Future<dynamic> Function(String, Map<String, dynamic>) _send;
  final AuthUser? Function() _user;
  final bool cancelEnabled, cashEnabled;

  bool canManage(Map<String, dynamic> sale) {
    final u = _user();
    return u != null &&
        u.isAdmin &&
        sale['id'] is int &&
        sale['sucursal_id'] is String &&
        (u.branchId == null || u.branchId == sale['sucursal_id']);
  }

  Future<dynamic> _call(String name, Map<String, dynamic> params) async {
    final actor = _user();
    if (actor == null || !actor.isAdmin) {
      throw StateError('Administrador autorizado requerido.');
    }
    try {
      final result = await _send(name, params);
      if (_user()?.id != actor.id) {
        throw StateError(
          'Cambió la sesión. Consulta el estado antes de repetir.',
        );
      }
      return result;
    } on PostgrestException catch (e) {
      if (e.code == '40001') {
        throw StateError(
          'Los importes cambiaron. Actualiza el resumen y confirma nuevamente.',
        );
      }
      if (['42501', '22023', '23505'].contains(e.code)) {
        throw StateError(e.message);
      }
      throw StateError(
        'Operación sin confirmar. Consulta el estado antes de repetir; revisa conexión y disponibilidad de la RPC.',
      );
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'Conexión interrumpida: operación sin confirmar. Actualiza antes de repetir; no se reintentó automáticamente.',
      );
    }
  }

  Future<Map<String, dynamic>> cancel(
    Map<String, dynamic> sale,
    String reason, {
    bool restore = false,
  }) async {
    if (!cancelEnabled || !canManage(sale)) {
      throw StateError(
        'Cancelación no habilitada para este administrador y sucursal.',
      );
    }
    if (sale['estado'] == 'cancelada') {
      throw StateError('La venta ya fue cancelada.');
    }
    if (reason.trim().isEmpty) throw StateError('El motivo es obligatorio.');
    final r = await _call('cancelar_venta', {
      'p_venta_id': sale['id'],
      'p_motivo': reason.trim(),
      'p_reintegrar': restore,
    });
    if (r is! Map ||
        r['estado'] != 'cancelada' ||
        r['venta_id'] != sale['id'] ||
        r['repetida'] is! bool) {
      throw StateError(
        'Respuesta sin confirmar. Consulta el historial antes de repetir.',
      );
    }
    return Map<String, dynamic>.from(r);
  }

  Future<Map<String, dynamic>> reconcile(
    Map<String, dynamic> sale,
    String state,
    String note,
    bool noCashOut,
  ) async {
    if (!cashEnabled || !canManage(sale)) {
      throw StateError('Conciliación no habilitada.');
    }
    if (sale['estado'] != 'cancelada' ||
        sale['metodo_pago'] != 'Efectivo' ||
        !['no_cobrado', 'devuelto'].contains(state) ||
        note.trim().isEmpty ||
        !noCashOut) {
      throw StateError(
        'Confirma estado, nota y que no hay otra salida por esta devolución.',
      );
    }
    final r = await _call('caja_conciliar_efectivo_cancelado', {
      'p_venta_id': sale['id'],
      'p_estado': state,
      'p_nota': note.trim(),
      'p_confirmo_sin_salida': noCashOut,
    });
    if (r is! Map ||
        r['venta_id'] != sale['id'] ||
        r['estado'] != state ||
        r['repetida'] is! bool) {
      throw StateError(
        'Conciliación sin confirmar. Consulta antes de repetir.',
      );
    }
    return Map<String, dynamic>.from(r);
  }

  Future<Map<String, dynamic>> summary(int turn) async {
    if (!cashEnabled) throw StateError('Cierre verificado desactivado.');
    final r = await _call('caja_resumen_turno', {'p_turno_id': turn});
    if (r is! Map ||
        r['turno_id'] != turn ||
        r['huella'] is! String ||
        (r['huella'] as String).isEmpty ||
        r['por_metodo'] is! Map ||
        r['cerrado'] is! bool ||
        ![
          'total_bruto',
          'total_cancelado',
          'total_neto',
          'ordenes_validas',
          'ordenes_canceladas',
          'fondo_inicial',
          'entradas',
          'salidas',
          'efectivo_base_neta',
          'efectivo_cancelado_sin_conciliar',
        ].every((k) => r[k] is num && (r[k] as num).isFinite)) {
      throw StateError('Resumen incompleto; no se puede cerrar Caja.');
    }
    final methods = r['por_metodo'] as Map;
    if (!['Efectivo', 'Tarjeta', 'Transferencia'].every((m) =>
        methods[m] is Map && methods[m]['neto'] is num && (methods[m]['neto'] as num).isFinite)) {
      throw StateError('Desglose incompleto; no se puede cerrar Caja.');
    }
    return Map<String, dynamic>.from(r);
  }

  Future<int> close(
    int turn,
    String fingerprint,
    double counted,
    String notes,
  ) async {
    if (!cashEnabled ||
        fingerprint.isEmpty ||
        !counted.isFinite ||
        counted < 0 ||
        (counted * 100 - (counted * 100).round()).abs() > .00001) {
      throw StateError('Datos de cierre inválidos.');
    }
    final r = await _call('caja_cerrar_turno_verificado', {
      'p_turno_id': turn,
      'p_huella': fingerprint,
      'p_efectivo_contado': counted,
      'p_notas': notes,
    });
    if (r is! int || r != turn) {
      throw StateError('Cierre sin confirmar. Consulta Caja antes de repetir.');
    }
    return r;
  }
}
