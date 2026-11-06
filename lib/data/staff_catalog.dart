import 'package:supabase_flutter/supabase_flutter.dart';

class StaffEmployee {
  const StaffEmployee({required this.id, required this.name});

  final String id;
  final String name;
}

// Catálogo local de sucursales y personal de caja
class StaffCatalog {
  static const branches = {
    'perimetral_sur': 'Perimetral Sur',
    'norte': 'Norte',
  };

  static Future<List<StaffEmployee>> loadEmployees({
    SupabaseClient? client,
  }) async {
    final db = client ?? Supabase.instance.client;
    final rows = await db
        .from('empleados_pos')
        .select('id,nombre')
        .eq('activo', true)
        .eq('es_demo', false)
        .order('nombre')
        .retry(enabled: false);
    return rows
        .map(
          (row) => StaffEmployee(
            id: row['id'] as String,
            name: row['nombre'] as String,
          ),
        )
        .toList();
  }
}
