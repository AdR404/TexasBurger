import 'dart:io' show HttpDate;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/corte_caja.dart';
import '../models/sale_context.dart';
import 'db_service.dart';
import 'sale_actions.dart';
import 'user_role_service.dart';
import 'app_auth_service.dart';
import 'caja_service.dart';

class CajaSnapshot {
  const CajaSnapshot(this.active, this.history, [this.summary]);
  final Map<String, dynamic>? summary;
  final CorteCaja? active;
  final List<CorteCaja> history;
}

class CajaRepository {
  CajaRepository({
    SupabaseClient? client,
    String? Function()? actor,
    DateTime Function(DateTime)? salesClock,
    Future<DateTime> Function()? checkedNow,
  }) : _client = client,
       _actor = actor ?? (() => DbService.session?.validOperatorId),
       _salesClock = salesClock ?? monterreyWallClock,
       _checkedNow = checkedNow ?? checkDeviceClock;
  final SupabaseClient? _client;
  SupabaseClient get db => _client ?? Supabase.instance.client;
  final String? Function() _actor;
  // Confirmed business convention for current shifts, not inferred for old sales.
  final DateTime Function(DateTime) _salesClock;
  final Future<DateTime> Function() _checkedNow;

  static void debugFailure(String operation, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    final code =
        error is PostgrestException &&
            RegExp(r'^[A-Z0-9]{5,12}$').hasMatch(error.code ?? '')
        ? error.code
        : null;
    debugPrint(
      '[Caja] $operation: ${error.runtimeType}${code == null ? '' : ' code=$code'}',
    );
    final locations = RegExp(
      r'(?:caja_repository|caja_service|sale_actions)\.dart:\d+:\d+',
    ).allMatches(stack.toString()).map((m) => m.group(0)).toSet().take(4);
    for (final location in locations) {
      debugPrint('[Caja] $location');
    }
  }

  static DateTime monterreyWallClock(DateTime instant) {
    if (instant.toUtc().year < 2023) {
      throw StateError(
        'No se puede interpretar automáticamente un turno histórico con esta regla horaria.',
      );
    }
    return instant.toUtc().subtract(const Duration(hours: 6));
  }

  static Future<DateTime> checkDeviceClock({
    http.Client? client,
    Uri? endpoint,
    DateTime Function()? now,
  }) async {
    final clock = now ?? DateTime.now;
    if (clock().timeZoneOffset != const Duration(hours: -6)) {
      throw StateError(
        'Configura el dispositivo con la zona America/Monterrey (UTC−6) y fecha/hora automáticas antes de operar Caja.',
      );
    }
    final transport = client ?? http.Client();
    try {
      final started = clock().toUtc();
      final response = await transport
          .head(
            endpoint ??
                Uri.parse('${DbService.environment!.url}/auth/v1/health'),
          )
          .timeout(const Duration(seconds: 8));
      final header = response.headers['date'];
      if (header == null || response.statusCode >= 500) {
        throw StateError(
          'No se pudo verificar el reloj con Supabase: falta la cabecera Date accesible o el servidor no está disponible. En Chrome revisa CORS y Access-Control-Expose-Headers. No se realizará la operación.',
        );
      }
      final server = HttpDate.parse(header).toUtc();
      final current = clock().toUtc();
      if (current.difference(started).inSeconds > 10 ||
          current.difference(server).abs() > const Duration(seconds: 30)) {
        throw StateError(
          'El reloj del dispositivo difiere de Supabase o la conexión es demasiado lenta. Activa fecha/hora automáticas y actualiza Caja.',
        );
      }
      // Conservative cutoff: HTTP Date has second precision. Never extend it
      // into the future; the subsecond/concurrent-close gap remains a limitation.
      return server;
    } finally {
      if (client == null) transport.close();
    }
  }

  Future<String> authorize() async {
    UserRoleService().requireAdmin();
    final actor = _actor();
    if (actor == null) {
      throw StateError(
        'Inicia sesión remota con una cuenta autorizada para Caja.',
      );
    }
    final rows = await db
        .from('inventario_admins')
        .select('user_id')
        .eq('user_id', actor)
        .eq('activo', true)
        .retry(enabled: false)
        .timeout(const Duration(seconds: 15));
    if (rows.length != 1 || _actor() != actor) {
      throw StateError(
        'La cuenta no está autorizada para Caja o cambió la sesión.',
      );
    }
    return actor;
  }

  void _sameActor(String actor) {
    if (_actor() != actor) {
      throw StateError('Cambió la sesión remota. Vuelve a consultar Caja.');
    }
  }

  Future<List<Map<String, dynamic>>> _all(
    PostgrestFilterBuilder<List<Map<String, dynamic>>> Function() query,
  ) async {
    final rows = <Map<String, dynamic>>[];
    final ids = <Object?>{};
    while (true) {
      final page = await query()
          .order('id')
          .range(rows.length, rows.length + 499)
          .retry(enabled: false)
          .timeout(const Duration(seconds: 20));
      if (page.isEmpty) return rows;
      for (final row in page) {
        if (row['id'] == null || !ids.add(row['id'])) {
          throw StateError(
            'La consulta cambió durante la lectura. Actualiza Caja antes de cerrar.',
          );
        }
      }
      rows.addAll(page);
    }
  }

  Future<Map<String, dynamic>?> _open(String branch) async {
    final rows = await db
        .from('caja_turnos')
        .select()
        .eq('empresa_id', 'texas_burger')
        .eq('sucursal_id', branch)
        .isFilter('fecha_cierre', null)
        .limit(2)
        .retry(enabled: false)
        .timeout(const Duration(seconds: 15));
    if (rows.length > 1) {
      throw StateError('Hay varios turnos abiertos. Revisa Caja en BD.');
    }
    return rows.isEmpty ? null : rows.single;
  }

  Future<CajaSnapshot> load(String branch) async {
    var stage = 'autorizacion';
    try {
      final actor = await authorize();
      stage = 'turnos.abierto.select';
      final activeRow = await _open(branch);
      stage = 'turnos.cerrados.select';
      final closed = await db
          .from('caja_turnos')
          .select()
          .eq('empresa_id', 'texas_burger')
          .eq('sucursal_id', branch)
          .not('fecha_cierre', 'is', null)
          .order('fecha_apertura', ascending: false)
          .order('id', ascending: false)
          .limit(50)
          .retry(enabled: false)
          .timeout(const Duration(seconds: 15));
      stage = 'turnos.cerrados.decode';
      final history = closed.map((r) => _map(r, const [])).toList();
      CorteCaja? active;
      Map<String, dynamic>? summary;
      if (activeRow != null) {
        stage = 'movimientos.select_decode';
        final moves = await _movements(activeRow['id'] as int);
        final Map<String, int> sales;
        if (SaleActions.verifiedCashEnabled) {
          stage = 'caja_resumen_turno';
          summary = await SaleActions().summary(activeRow['id'] as int);
          if (summary['cerrado'] != false) {
            throw StateError('El turno cambió; actualiza Caja.');
          }
          stage = 'resumen.decode';
          final methods = summary['por_metodo'] as Map;
          sales = {
            for (final m in ['Efectivo', 'Tarjeta', 'Transferencia'])
              m: cents((methods[m] as Map)['neto'] as num),
            'orders': summary['ordenes_validas'] as int,
          };
        } else {
          stage = 'ventas_legacy.reloj_select_decode';
          sales = await _sales(activeRow, await _checkedNow());
        }
        stage = 'turno.activo.decode';
        active = _map(
          {
            ...activeRow,
            if (summary != null) ...{
              'fondo_inicial': summary['fondo_inicial'],
              'entradas_total': summary['entradas'],
              'salidas_total': summary['salidas'],
            },
          },
          moves,
          sales: sales,
        );
      }
      _sameActor(actor);
      return CajaSnapshot(active, history, summary);
    } catch (error, stack) {
      debugFailure('load.$stage', error, stack);
      rethrow;
    }
  }

  Future<List<CajaMovimiento>> _movements(int id) async =>
      (await _all(
            () => db.from('caja_movimientos').select().eq('turno_id', id),
          ))
          .map(
            (r) => CajaMovimiento(
              id: '${r['id']}',
              type: r['tipo'] as String,
              amount: (r['importe'] as num).toDouble(),
              concept: r['concepto'] as String,
              timestamp: DateTime.parse(r['fecha_hora'] as String).toLocal(),
            ),
          )
          .toList();

  Future<CorteCaja> closed(int id, String branch) async {
    final actor = await authorize();
    final row = await db
        .from('caja_turnos')
        .select()
        .eq('id', id)
        .eq('empresa_id', 'texas_burger')
        .eq('sucursal_id', branch)
        .not('fecha_cierre', 'is', null)
        .single()
        .retry(enabled: false)
        .timeout(const Duration(seconds: 15));
    final moves = await _movements(id);
    _sameActor(actor);
    return _map(row, moves);
  }

  static int cents(num value) {
    final amount = value.toDouble();
    if (!amount.isFinite ||
        amount < 0 ||
        amount >= 1e10 ||
        (amount * 100 - (amount * 100).round()).abs() > 0.00001) {
      throw StateError(
        'El importe debe ser positivo o cero y tener como máximo dos decimales.',
      );
    }
    return (amount * 100).round();
  }

  Future<Map<String, int>> _sales(
    Map<String, dynamic> turn,
    DateTime end,
  ) async {
    final opening = DateTime.parse(turn['fecha_apertura'] as String).toUtc();
    if (end.isBefore(opening) &&
        opening.difference(end) < const Duration(seconds: 1)) {
      end =
          opening; // A newly opened shift may be within the rounded HTTP second.
    }
    if (end.isBefore(opening)) {
      throw StateError(
        'La hora del dispositivo es anterior a la apertura. No se puede cerrar Caja.',
      );
    }
    String wall(DateTime instant) =>
        _salesClock(instant).toIso8601String().replaceFirst(RegExp(r'Z$'), '');
    final rows = await _all(
      () => db
          .from('ventas')
          .select('id,total,metodo_pago,estado')
          .eq('empresa_id', 'texas_burger')
          .eq('sucursal_id', turn['sucursal_id'])
          .gte('fecha_hora', wall(opening))
          .lt('fecha_hora', wall(end)),
    );
    final totals = <String, int>{
      'Efectivo': 0,
      'Tarjeta': 0,
      'Transferencia': 0,
      'orders': rows.length,
    };
    for (final row in rows) {
      if (row['estado'] == 'cancelada') {
        throw StateError(
          'Este turno contiene cancelaciones. Se requiere instalar y habilitar el cierre verificado; no se usarán totales del procedimiento anterior.',
        );
      }
      final method = row['metodo_pago'];
      if (!['Efectivo', 'Tarjeta', 'Transferencia'].contains(method) ||
          row['total'] is! num) {
        throw StateError(
          'Hay ventas sin importe o con un método de pago desconocido. No se puede cerrar Caja.',
        );
      }
      totals[method as String] = totals[method]! + cents(row['total'] as num);
    }
    return totals;
  }

  Future<int> _rpc(
    String name,
    Map<String, dynamic> params,
    String actor,
  ) async {
    _sameActor(actor);
    try {
      final result = await db
          .rpc(name, params: params)
          .retry(enabled: false)
          .timeout(const Duration(seconds: 20));
      if (result is! int || result <= 0) {
        throw StateError('Respuesta inesperada');
      }
      return result;
    } on PostgrestException catch (e, stack) {
      debugFailure('rpc.$name', e, stack);
      if (['42501', '22023', '23505'].contains(e.code)) {
        throw StateError(e.message);
      }
      throw StateError(
        'Operación sin confirmar. Consulta Caja antes de repetirla; no hay reintentos automáticos.',
      );
    } catch (e, stack) {
      debugFailure('rpc.$name', e, stack);
      throw StateError(
        'Operación sin confirmar. Consulta Caja antes de repetirla; no hay reintentos automáticos.',
      );
    }
  }

  Future<int> open(SaleContext context, double cash) async {
    var stage = 'autorizacion';
    try {
      cents(cash);
      final actor = await authorize();
      final profile = AppAuthService().currentUser;
      if (profile == null ||
          profile.id != actor ||
          context.employeeId != profile.employeeId ||
          context.employeeName != profile.employeeName ||
          AppAuthService().branches[context.branchId] != context.branchName ||
          CajaService().saleContext?.branchId != context.branchId) {
        throw StateError(
          'La apertura requiere el empleado autenticado y la sucursal operativa actual.',
        );
      }
      stage = 'turnos.abierto.select';
      final existing = await _open(context.branchId);
      if (existing != null) return existing['id'] as int;
      stage = 'reloj';
      await _checkedNow();
      if (AppAuthService().currentUser?.id != actor ||
          CajaService().saleContext?.branchId != context.branchId) {
        throw StateError('Cambió la sesión o sucursal antes de abrir Caja.');
      }
      stage = 'caja_abrir_turno';
      return await _rpc('caja_abrir_turno', {
        'p_sucursal_id': context.branchId,
        'p_empleado_pos_id': profile.employeeId,
        'p_empleado_nombre': profile.employeeName,
        'p_fondo_inicial': cash,
      }, actor);
    } catch (error, stack) {
      debugFailure('open.$stage', error, stack);
      rethrow;
    }
  }

  Future<void> movement(
    CorteCaja turn,
    String type,
    double amount,
    String concept,
  ) async {
    if (turn.isClosed ||
        !['entrada', 'salida'].contains(type) ||
        cents(amount) <= 0 ||
        concept.trim().isEmpty) {
      throw StateError('Movimiento inválido o turno cerrado.');
    }
    final actor = await authorize();
    await _checkedNow();
    await _rpc('caja_registrar_movimiento', {
      'p_turno_id': int.parse(turn.id),
      'p_tipo': type,
      'p_importe': amount,
      'p_concepto': concept.trim(),
    }, actor);
  }

  Future<int> close(
    CorteCaja turn,
    double counted,
    String notes, {
    String? fingerprint,
  }) async {
    cents(counted);
    final actor = await authorize();
    final current = await _open(turn.openingContext!.branchId);
    if (current == null || '${current['id']}' != turn.id) {
      throw StateError('El turno ya está cerrado o cambió. Actualiza Caja.');
    }
    if (SaleActions.verifiedCashEnabled) {
      if (fingerprint == null) {
        throw StateError(
          'Consulta y confirma el resumen del servidor antes de cerrar.',
        );
      }
      return SaleActions().close(
        int.parse(turn.id),
        fingerprint,
        counted,
        notes,
      );
    }
    final totals = await _sales(current, await _checkedNow());
    return _rpc('caja_cerrar_turno', {
      'p_turno_id': int.parse(turn.id),
      'p_ventas_efectivo': totals['Efectivo']! / 100,
      'p_ventas_tarjeta': totals['Tarjeta']! / 100,
      'p_ventas_transferencia': totals['Transferencia']! / 100,
      'p_numero_ordenes': totals['orders'],
      'p_efectivo_contado': counted,
      'p_notas': notes,
    }, actor);
  }

  CorteCaja _map(
    Map<String, dynamic> r,
    List<CajaMovimiento> moves, {
    Map<String, int>? sales,
  }) {
    double number(String key) => (r[key] as num).toDouble();
    final cash = sales == null
        ? number('ventas_efectivo')
        : sales['Efectivo']! / 100;
    final card = sales == null
        ? number('ventas_tarjeta')
        : sales['Tarjeta']! / 100;
    final transfer = sales == null
        ? number('ventas_transferencia')
        : sales['Transferencia']! / 100;
    return CorteCaja(
      id: '${r['id']}',
      openingContext: SaleContext(
        companyId: r['empresa_id'] as String,
        branchId: r['sucursal_id'] as String,
        branchName: r['sucursal_nombre'] as String,
        employeeId: r['empleado_pos_id'] as String? ?? '',
        employeeName: r['empleado_nombre'] as String,
      ),
      openedAt: DateTime.parse(r['fecha_apertura'] as String).toLocal(),
      closedAt: r['fecha_cierre'] == null
          ? null
          : DateTime.parse(r['fecha_cierre'] as String).toLocal(),
      initialCash: number('fondo_inicial'),
      cashIn: number('entradas_total'),
      cashOut: number('salidas_total'),
      cashSales: cash,
      cardSales: card,
      transferSales: transfer,
      totalSales: sales == null
          ? number('total_ventas')
          : (sales['Efectivo']! + sales['Tarjeta']! + sales['Transferencia']!) /
                100,
      ordersCount: sales?['orders'] ?? r['numero_ordenes'] as int,
      expectedCash: sales == null
          ? number('efectivo_esperado')
          : (cents(number('fondo_inicial')) +
                    cents(number('entradas_total')) -
                    cents(number('salidas_total')) +
                    sales['Efectivo']!) /
                100,
      actualCashCounted: (r['efectivo_contado'] as num?)?.toDouble(),
      difference: (r['diferencia'] as num?)?.toDouble(),
      notes: r['notas'] as String,
      isClosed: r['fecha_cierre'] != null,
      movimientos: moves,
    );
  }
}
