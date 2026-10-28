import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/venta.dart';

const supabaseUrl = 'https://zlljyvowdripxdgvhilz.supabase.co';
const supabaseKey = 'sb_publishable_QagT6TuxktFz4DgItZ6aEQ_jRv0DbUO';

class DbService {
  static const String _syncPrefKey = 'texas_db_sync_enabled';

  static SupabaseClient get _db => Supabase.instance.client;

  static final Map<String, int> _productIds = {};
  static final Map<String, int> _categoryIds = {};

  static final ValueNotifier<bool> syncEnabledNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<String> lastSyncStatusNotifier = ValueNotifier<String>(
    'Sincronización activa',
  );

  static bool get isSyncEnabled => syncEnabledNotifier.value;

  static Future<void> setSyncEnabled(bool enabled) async {
    syncEnabledNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncPrefKey, enabled);
    lastSyncStatusNotifier.value = enabled
        ? 'Sincronización con Supabase reanudada'
        : 'Base de datos frenada (modo solo local)';
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_syncPrefKey) ?? true;
      syncEnabledNotifier.value = enabled;
      lastSyncStatusNotifier.value = enabled
          ? 'Conectado a Supabase'
          : 'Base de datos frenada (modo solo local)';
    } catch (_) {}

    try {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    } catch (e) {
      debugPrint('No se pudo conectar a la BD: $e');
      lastSyncStatusNotifier.value = 'Error al inicializar Supabase: $e';
    }
  }

  static Future<int> _categoryId(String nombre) async {
    if (_categoryIds.containsKey(nombre)) return _categoryIds[nombre]!;

    final existing = await _db
        .from('categorias')
        .select('id')
        .eq('nombre', nombre)
        .limit(1);
    if (existing.isNotEmpty) {
      _categoryIds[nombre] = existing.first['id'] as int;
      return _categoryIds[nombre]!;
    }

    final row = await _db
        .from('categorias')
        .insert({'nombre': nombre})
        .select('id')
        .single();
    _categoryIds[nombre] = row['id'] as int;
    return _categoryIds[nombre]!;
  }

  static Future<int> _productId(
    String nombre,
    String categoria,
    double precio,
    String descripcion,
  ) async {
    if (_productIds.containsKey(nombre)) return _productIds[nombre]!;

    final existing = await _db
        .from('productos')
        .select('id')
        .eq('nombre', nombre)
        .limit(1);
    if (existing.isNotEmpty) {
      _productIds[nombre] = existing.first['id'] as int;
      return _productIds[nombre]!;
    }

    final catId = await _categoryId(categoria);
    final row = await _db
        .from('productos')
        .insert({
          'nombre': nombre,
          'categoria_id': catId,
          'precio': precio,
          'descripcion': descripcion,
        })
        .select('id')
        .single();
    _productIds[nombre] = row['id'] as int;
    return _productIds[nombre]!;
  }

  static Future<Map<String, dynamic>> _insertVentaHeader(Venta venta) async {
    final basePayload = <String, dynamic>{
      'usuario_id': 2,
      'fecha_hora': venta.timestamp.toIso8601String(),
      'total': venta.total,
      'metodo_pago': venta.paymentMethod,
    };

    final extendedPayload = <String, dynamic>{
      ...basePayload,
      'subtotal': venta.subtotal,
      'descuento': venta.discount,
      if (venta.discountCode != null) 'codigo_descuento': venta.discountCode,
      if (venta.iva != null) 'iva': venta.iva,
      if (venta.ivaRate != null) 'tasa_iva': venta.ivaRate,
      if (venta.ivaIncluded != null) 'iva_incluido': venta.ivaIncluded,
      if (venta.saleContext != null) ...{
        'empresa_id': venta.saleContext!.companyId,
        'empresa_nombre': venta.saleContext!.companyName,
        'sucursal_id': venta.saleContext!.branchId,
        'sucursal_nombre': venta.saleContext!.branchName,
        'empleado_pos_id': venta.saleContext!.employeeId,
        'empleado_nombre': venta.saleContext!.employeeName,
      },
    };

    try {
      return await _db
          .from('ventas')
          .insert(extendedPayload)
          .select('id')
          .single();
    } on PostgrestException {
      return await _db.from('ventas').insert(basePayload).select('id').single();
    }
  }

  static Future<void> guardarVenta(Venta venta) async {
    if (!isSyncEnabled) {
      lastSyncStatusNotifier.value =
          'BD frenada: Ticket #${venta.ticketNumber} guardado solo en dispositivo';
      return;
    }

    try {
      final row = await _insertVentaHeader(venta);
      final ventaId = row['id'] as int;
      final detalle = <Map<String, dynamic>>[];

      for (final item in venta.items) {
        final p = item.product;
        final prodId = await _productId(
          p.name,
          p.category,
          p.price,
          p.description,
        );
        detalle.add({
          'venta_id': ventaId,
          'producto_id': prodId,
          'cantidad': item.quantity,
          'precio_unitario': item.unitPrice,
        });
      }

      if (detalle.isNotEmpty) {
        await _db.from('detalle_venta').insert(detalle);
      }
      lastSyncStatusNotifier.value =
          'Ticket #${venta.ticketNumber} guardado en Supabase (ID remoto: $ventaId)';
    } catch (e) {
      debugPrint('No se pudo guardar la venta en la BD: $e');
      lastSyncStatusNotifier.value =
          'Error al sincronizar Ticket #${venta.ticketNumber}: $e';
    }
  }

  static Future<String> probarConexion() async {
    try {
      final ventas = await _db.from('ventas').select('id').limit(1);
      final detalles = await _db.from('detalle_venta').select('id').limit(1);
      final productos = await _db.from('productos').select('id').limit(1);

      bool tieneContextoStaff = true;
      try {
        await _db.from('sucursales').select('id').limit(1);
        await _db.from('empleados_pos').select('id').limit(1);
      } catch (_) {
        tieneContextoStaff = false;
      }

      final estadoModo = isSyncEnabled ? 'ACTIVA' : 'PAUSADA (Local)';
      final msg = tieneContextoStaff
          ? 'Conexión OK ($estadoModo) - Tablas listas'
          : 'Conexión OK ($estadoModo) - Esquema base';
      lastSyncStatusNotifier.value =
          '$msg (ventas: ${ventas.length}, prod: ${productos.length}, det: ${detalles.length})';
      return msg;
    } catch (e) {
      final err = 'Error de conexión con Supabase: $e';
      lastSyncStatusNotifier.value = err;
      return err;
    }
  }
}
