import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/venta.dart';

const supabaseUrl = 'https://zlljyvowdripxdgvhilz.supabase.co';
const supabaseKey = 'sb_publishable_QagT6TuxktFz4DgItZ6aEQ_jRv0DbUO';

class DbService {
  static SupabaseClient get _db => Supabase.instance.client;

  static final Map<String, int> _productIds = {};
  static final Map<String, int> _categoryIds = {};

  static Future<void> init() async {
    try {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    } catch (e) {
      debugPrint('No se pudo conectar a la BD: $e');
    }
  }

  static Future<int> _categoryId(String nombre) async {
    if (_categoryIds.containsKey(nombre)) return _categoryIds[nombre]!;
    final row = await _db
        .from('categorias')
        .upsert({'nombre': nombre}, onConflict: 'nombre')
        .select('id')
        .single();
    _categoryIds[nombre] = row['id'] as int;
    return _categoryIds[nombre]!;
  }

  static Future<int> _productId(String nombre, String categoria, double precio, String descripcion) async {
    if (_productIds.containsKey(nombre)) return _productIds[nombre]!;
    final catId = await _categoryId(categoria);
    final row = await _db
        .from('productos')
        .upsert({
          'nombre': nombre,
          'categoria_id': catId,
          'precio': precio,
          'descripcion': descripcion,
        }, onConflict: 'nombre')
        .select('id')
        .single();
    _productIds[nombre] = row['id'] as int;
    return _productIds[nombre]!;
  }

  static Future<void> guardarVenta(Venta venta) async {
    try {
      final row = await _db
          .from('ventas')
          .insert({
            'usuario_id': 2,
            'fecha_hora': venta.timestamp.toIso8601String(),
            'total': venta.total,
            'metodo_pago': venta.paymentMethod,
          })
          .select('id')
          .single();

      final ventaId = row['id'] as int;
      final detalle = <Map<String, dynamic>>[];

      for (final item in venta.items) {
        final p = item.product;
        final prodId = await _productId(p.name, p.category, p.price, p.description);
        detalle.add({
          'venta_id': ventaId,
          'producto_id': prodId,
          'cantidad': item.quantity,
          'precio_unitario': item.unitPrice,
        });
      }

      await _db.from('detalle_venta').insert(detalle);
    } catch (e) {
      debugPrint('No se pudo guardar la venta en la BD: $e');
    }
  }
}
