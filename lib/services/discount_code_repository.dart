import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/discount_code.dart';

class DiscountCodeRepository {
  DiscountCodeRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _schema = 'cobrador';
  static const String _table = 'cupones';

  Future<List<DiscountCode>> fetchAll() async {
    final rows = await _client
        .schema(_schema)
        .from(_table)
        .select('codigo,descripcion,tipo,valor,activo')
        .order('codigo');

    return rows
        .map(
          (row) => DiscountCode.fromSupabase(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  Future<void> save(DiscountCode coupon) async {
    await _client
        .schema(_schema)
        .from(_table)
        .upsert(coupon.toSupabase(), onConflict: 'codigo');
  }

  Future<void> setActive(String code, bool isActive) async {
    await _client
        .schema(_schema)
        .from(_table)
        .update({'activo': isActive})
        .eq('codigo', code.trim().toUpperCase());
  }

  Future<void> remove(String code) async {
    await _client
        .schema(_schema)
        .from(_table)
        .delete()
        .eq('codigo', code.trim().toUpperCase());
  }
}