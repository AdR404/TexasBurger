import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_lot.dart';
import 'db_service.dart';

class InventoryIngredient {
  const InventoryIngredient(this.id, this.name, this.unit);
  final int id;
  final String name;
  final String unit;
}

class InventoryData {
  const InventoryData(this.ingredients, this.lots, this.movements);
  final List<InventoryIngredient> ingredients;
  final List<InventoryLot> lots;
  final List<Map<String, dynamic>> movements;
}

class InventoryException implements Exception {
  const InventoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Uses the existing Supabase client and session. No direct stock writes.
class InventoryRepository {
  InventoryRepository({
    SupabaseClient Function()? client,
    String? Function()? operatorId,
  }) : _client = client ?? (() => Supabase.instance.client),
       _operatorId = operatorId ?? (() => DbService.session?.validOperatorId);
  final SupabaseClient Function() _client;
  final String? Function() _operatorId;
  String? get operatorId => _operatorId();

  Future<String> _authorize() async {
    final actor = operatorId;
    if (actor == null) {
      throw const InventoryException(
        'Inicia sesión remota para consultar o modificar inventario.',
      );
    }
    final rows = await _client()
        .from('inventario_admins')
        .select('user_id')
        .eq('user_id', actor)
        .eq('activo', true)
        .retry(enabled: false)
        .timeout(const Duration(seconds: 15));
    if (rows.length != 1 || operatorId != actor) {
      throw const InventoryException(
        'La cuenta no está autorizada para inventario o cambió la sesión.',
      );
    }
    return actor;
  }

  Future<List<Map<String, dynamic>>> _pages(
    PostgrestFilterBuilder<List<Map<String, dynamic>>> Function() query,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var start = 0; ; start += 500) {
      final page = await query()
          .order('id')
          .range(start, start + 499)
          .retry(enabled: false)
          .timeout(const Duration(seconds: 15));
      result.addAll(page);
      if (page.length < 500) return result;
    }
  }

  Future<InventoryData> load(String branch) async {
    try {
      final actor = await _authorize();
      final ingredients =
          (await _pages(
                () => _client()
                    .from('ingredientes')
                    .select('id,nombre,unidad_medida'),
              ))
              .map(
                (r) => InventoryIngredient(
                  r['id'] as int,
                  r['nombre'] as String,
                  r['unidad_medida'] as String,
                ),
              )
              .toList();
      final names = {for (final i in ingredients) i.id: i.name};
      final rows = await _pages(
        () => _client()
            .from('inventario_lotes')
            .select()
            .eq('sucursal_id', branch),
      );
      final lots = rows
          .map(
            (r) => InventoryLot(
              id: r['id'] as int,
              ingredientId: r['ingrediente_id'] as int,
              ingredientName:
                  names[r['ingrediente_id']] ??
                  (throw const InventoryException(
                    'Ingrediente del lote no disponible.',
                  )),
              location: r['ubicacion'] as String,
              unit: r['unidad_medida'] as String,
              initialQuantity: (r['cantidad_inicial'] as num).toDouble(),
              availableQuantity: (r['cantidad_disponible'] as num).toDouble(),
              unitCost: (r['costo_unitario'] as num).toDouble(),
              entryDate: DateTime.parse(r['fecha_entrada'] as String),
              expirationDate: DateTime.parse(r['fecha_caducidad'] as String),
              estimatedExpiration: r['caducidad_estimada'] as bool,
            ),
          )
          .toList();
      final movements = await _pages(
        () => _client()
            .from('inventario_movimientos')
            .select(
              'id,lote_id,tipo,cantidad,cantidad_antes,cantidad_despues,motivo,fecha_hora,inventario_lotes!inner(sucursal_id)',
            )
            .eq('inventario_lotes.sucursal_id', branch),
      );
      if (operatorId != actor) {
        throw const InventoryException(
          'Cambió la sesión. Actualiza el inventario.',
        );
      }
      movements.sort(
        (a, b) =>
            (b['fecha_hora'] as String).compareTo(a['fecha_hora'] as String),
      );
      return InventoryData(ingredients, lots, movements);
    } catch (e) {
      throw _error(e, writing: false);
    }
  }

  Future<int> registerLot({
    required InventoryIngredient ingredient,
    required String branch,
    required String location,
    required double quantity,
    required double cost,
    required DateTime entry,
    required DateTime expiration,
    required bool estimated,
  }) async {
    if (ingredient.id <= 0 ||
        !['kg', 'pzas', 'L'].contains(ingredient.unit) ||
        branch.isEmpty ||
        !validInventoryDecimal(quantity, 3) ||
        quantity <= 0 ||
        quantity >= 1000000000 ||
        !validInventoryDecimal(cost, 4) ||
        cost < 0 ||
        cost >= 100000000 ||
        expiration.isBefore(entry)) {
      throw const InventoryException(
        'Revisa ingrediente real, unidad, fechas, cantidad (3 decimales) y costo (4 decimales).',
      );
    }
    return _write('inventario_registrar_lote', {
      'p_ingrediente_id': ingredient.id,
      'p_sucursal_id': branch,
      'p_ubicacion': location,
      'p_unidad': ingredient.unit,
      'p_cantidad': quantity,
      'p_costo_unitario': cost,
      'p_fecha_entrada': _date(entry),
      'p_fecha_caducidad': _date(expiration),
      'p_caducidad_estimada': estimated,
    });
  }

  Future<int> registerDecrease({
    required int lotId,
    required String type,
    required double quantity,
    required String reason,
  }) {
    if (lotId <= 0 ||
        !['salida', 'descarte'].contains(type) ||
        !validInventoryDecimal(quantity, 3) ||
        quantity <= 0 ||
        reason.trim().isEmpty) {
      throw const InventoryException(
        'Movimiento inválido. Revisa lote, tipo, cantidad y motivo.',
      );
    }
    return _write('inventario_registrar_baja', {
      'p_lote_id': lotId,
      'p_tipo': type,
      'p_cantidad': quantity,
      'p_motivo': reason.trim(),
    });
  }

  Future<int> _write(String name, Map<String, dynamic> params) async {
    var sent = false;
    try {
      final actor = await _authorize();
      if (operatorId != actor) {
        throw const InventoryException(
          'Cambió la sesión; no se envió la operación.',
        );
      }
      sent = true;
      final result = await _client()
          .rpc(name, params: params)
          .retry(enabled: false)
          .timeout(const Duration(seconds: 20));
      if (result is! int || result <= 0) {
        throw const FormatException('Invalid acknowledgement');
      }
      return result;
    } catch (e) {
      throw _error(e, writing: sent);
    }
  }

  static InventoryException _error(Object e, {required bool writing}) {
    if (e is InventoryException) return e;
    if (e is PostgrestException && e.code == '42501') {
      return const InventoryException(
        'La cuenta no tiene permiso para esta operación de inventario.',
      );
    }
    if (e is PostgrestException && e.code == '22023') {
      return InventoryException(e.message);
    }
    return InventoryException(
      writing
          ? 'No se pudo confirmar la operación. Consulta lotes e historial antes de repetirla; podría haberse registrado.'
          : 'No se pudo consultar inventario. Comprueba conexión, sesión y permisos y vuelve a actualizar.',
    );
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

bool validInventoryDecimal(double value, int places) {
  if (!value.isFinite) return false;
  final factor = places == 3 ? 1000 : 10000;
  return (value * factor - (value * factor).round()).abs() < 0.000001;
}
