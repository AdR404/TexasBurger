import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import '../models/venta.dart';
import 'operator_auth_service.dart';
import 'supabase_environment.dart';
import 'operator_session.dart';
import 'app_auth_service.dart';

const supabaseUrl = 'https://zlljyvowdripxdgvhilz.supabase.co';
const supabaseKey = 'sb_publishable_QagT6TuxktFz4DgItZ6aEQ_jRv0DbUO';

class DbService {
  static const String _syncPrefKey = 'texas_db_sync_enabled';

  static bool _initializedSupabase = false;
  static SupabaseClient get _db => Supabase.instance.client;

  // Build flag plus the saved preference enable the simple online writer.
  static const bool onlineSalesEnabled = bool.fromEnvironment(
    'TEXAS_ENABLE_SIMPLE_SALES',
  );
  static SupabaseEnvironment? environment;
  static OperatorSession? session;
  static OperatorAuthService get operatorAuth => OperatorAuthService(_db);

  static final ValueNotifier<bool> syncEnabledNotifier = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<String> lastSyncStatusNotifier =
      ValueNotifier<String>('Conexión pendiente de comprobar');

  static bool get isSyncEnabled => syncEnabledNotifier.value;

  // Read-only history. Keep nullable snapshots separate from local Venta defaults.
  static Future<List<Map<String, dynamic>>> consultarHistorial({
    int page = 0,
    String? branchId,
    DateTime? date,
  }) async {
    if (page < 0) throw ArgumentError.value(page, 'page');
    final user = AppAuthService().currentUser;
    if (user == null) {
      throw StateError('Inicia sesion para consultar el historial.');
    }
    if (!user.isAdmin) branchId = user.branchId;
    var query = _db
        .from('ventas')
        .select(
          'id,fecha_hora,total,metodo_pago,empresa_id,empresa_nombre,'
          'sucursal_id,sucursal_nombre,empleado_pos_id,empleado_nombre,'
          'subtotal,descuento,codigo_descuento,iva,tasa_iva,iva_incluido,'
          'detalle_venta(id,producto_id,cantidad,precio_unitario,productos(nombre))',
        )
        .eq('empresa_id', 'texas_burger');
    if (branchId != null) query = query.eq('sucursal_id', branchId);
    if (date != null) {
      final start = DateTime(date.year, date.month, date.day);
      final end = DateTime(date.year, date.month, date.day + 1);
      query = query
          .gte('fecha_hora', start.toUtc().toIso8601String())
          .lt('fecha_hora', end.toUtc().toIso8601String());
    }
    return await query
        .order('fecha_hora', ascending: false, nullsFirst: false)
        .order('id', ascending: false)
        .order('id', referencedTable: 'detalle_venta')
        .limit(201, referencedTable: 'detalle_venta')
        .range(page * 50, page * 50 + 50)
        .retry(enabled: false)
        .timeout(const Duration(seconds: 20));
  }

  static String get salesModeMessage => !isSyncEnabled
      ? 'Ventas solo en el dispositivo. No se enviarán automáticamente después. El inventario remoto requiere su propia sesión y permisos.'
      : onlineSalesEnabled
      ? 'Ventas online habilitadas. Cada venta requiere confirmar cabecera y detalles en Supabase. La conexión aún debe comprobarse.'
      : 'Esta compilación guarda ventas solo en el dispositivo; no incluye la opción de ventas online.';

  static Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_syncPrefKey, enabled)) {
      throw StateError('No se pudo guardar la preferencia de sincronización.');
    }
    syncEnabledNotifier.value = enabled;
    lastSyncStatusNotifier.value = salesModeMessage;
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_syncPrefKey) ?? true;
      syncEnabledNotifier.value = enabled;
      lastSyncStatusNotifier.value =
          '$salesModeMessage Conexión pendiente de comprobar.';
    } catch (_) {
      // Never resume remote writes if the saved preference could not be read.
      syncEnabledNotifier.value = false;
      lastSyncStatusNotifier.value =
          'No se pudo leer la configuración de BD; envío remoto pausado';
    }

    try {
      environment = SupabaseEnvironment.resolve(mainPublicKey: supabaseKey);
      if (!_initializedSupabase) {
        await Supabase.initialize(
          url: environment!.url,
          publishableKey: environment!.publicKey,
          authOptions: const FlutterAuthClientOptions(
            persistSession: true,
            detectSessionInUri: true,
          ),
        );
        _initializedSupabase = true;
      }
      session?.dispose();
      session = OperatorSession(
        operatorAuth,
        await SharedPreferences.getInstance(),
        projectId: environment!.projectId,
      );
      await session!.initialize();
    } catch (_) {
      session?.dispose();
      session = null;
      lastSyncStatusNotifier.value =
          'Acceso remoto no disponible o configuración inválida; trabajo local y envío bloqueado';
    }
  }

  // Explicit opt-in for an authorized test build. No RPC or automatic retries.
  static Future<void> guardarVenta(
    Venta venta, {
    SupabaseClient? client,
    bool? enabled,
  }) async {
    if (!(enabled ?? onlineSalesEnabled) || !isSyncEnabled) {
      lastSyncStatusNotifier.value =
          'Ticket #${venta.ticketNumber} guardado solo en dispositivo; sin confirmación remota';
      return;
    }
    final db = client ?? _db;
    int? remoteId;
    bool headerSent = false;
    try {
      final context = venta.saleContext;
      if (context == null ||
          venta.items.isEmpty ||
          venta.iva == null ||
          venta.ivaRate != 0.16 ||
          venta.ivaIncluded != true) {
        throw StateError('Faltan contexto, productos o desglose fiscal.');
      }
      final actor = db.auth.currentUser?.id;
      if (actor == null) {
        throw StateError('Inicia sesión antes de registrar la venta.');
      }
      final rows = await db.rpc('login_mi_perfil').retry(enabled: false);
      if (rows is! List || rows.length != 1 || db.auth.currentUser?.id != actor) {
        throw StateError('Se requiere un perfil autenticado valido.');
      }
      final profile = AuthUser.fromProfile(
        db.auth.currentUser!.id,
        db.auth.currentUser!.email ?? '',
        Map<String, dynamic>.from(rows.single as Map),
      );
      if (profile.employeeId != context.employeeId ||
          profile.employeeName != context.employeeName ||
          (profile.branchId != null && profile.branchId != context.branchId)) {
        throw StateError('El empleado o sucursal no corresponde a la sesion.');
      }
      final userId = profile.businessId;
      final details = <Map<String, dynamic>>[];
      for (final item in venta.items) {
        final products = await db
            .from('productos')
            .select('id')
            .eq('nombre', item.product.name)
            .eq('activo', true)
            .retry(enabled: false);
        if (products.length != 1 ||
            products.single['id'] is! int ||
            item.quantity <= 0 ||
            !item.unitPrice.isFinite ||
            item.unitPrice < 0) {
          throw StateError(
            'Producto sin correspondencia única válida: ${item.product.name}',
          );
        }
        details.add({
          'producto_id': products.single['id'],
          'cantidad': item.quantity,
          'precio_unitario': item.unitPrice,
        });
      }
      if (db.auth.currentUser?.id != actor ||
          db.auth.currentSession?.isExpired != false) {
        throw StateError('La sesión cambió o caducó antes de enviar la venta.');
      }
      headerSent = true;
      final header = await db
          .from('ventas')
          .insert({
            'usuario_id': userId,
            'fecha_hora': venta.timestamp.toIso8601String(),
            'total': venta.total,
            'metodo_pago': venta.paymentMethod,
            'subtotal': venta.subtotal,
            'descuento': venta.discount,
            'codigo_descuento': venta.discountCode,
            'iva': venta.iva,
            'tasa_iva': venta.ivaRate,
            'iva_incluido': venta.ivaIncluded,
            'empresa_id': context.companyId,
            'empresa_nombre': context.companyName,
            'sucursal_id': context.branchId,
            'sucursal_nombre': context.branchName,
            'empleado_pos_id': context.employeeId,
            'empleado_nombre': context.employeeName,
          })
          .select('id')
          .single()
          .retry(enabled: false);
      remoteId = header['id'] as int;
      for (final detail in details) {
        detail['venta_id'] = remoteId;
      }
      await db.from('detalle_venta').insert(details).retry(enabled: false);
      final stored = await db
          .from('detalle_venta')
          .select('producto_id,cantidad,precio_unitario')
          .eq('venta_id', remoteId)
          .retry(enabled: false);
      final remaining = List<Map<String, dynamic>>.from(stored);
      for (final detail in details) {
        final index = remaining.indexWhere(
          (row) =>
              row['producto_id'] == detail['producto_id'] &&
              row['cantidad'] == detail['cantidad'] &&
              row['precio_unitario'] == detail['precio_unitario'],
        );
        if (index < 0) {
          throw StateError('No se verificaron todos los detalles.');
        }
        remaining.removeAt(index);
      }
      if (remaining.isNotEmpty) {
        throw StateError('Hay detalles adicionales inesperados.');
      }
      lastSyncStatusNotifier.value = 'Venta completa en Supabase: $remoteId';
    } catch (error) {
      final message = headerSent
          ? 'Venta no confirmada como completa (ID: ${remoteId ?? "desconocido"}). Puede existir una cabecera o un registro parcial. No repitas el cobro sin revisar BD.'
          : 'No se envió la venta. Revisa la correspondencia de productos, el usuario del empleado y los permisos. ${error is StateError ? error.message : "No se pudo consultar Supabase."}';
      lastSyncStatusNotifier.value = message;
      throw StateError(message);
    }
  }

  static Future<String> probarConexion() async {
    try {
      final ventas = await _db.from('ventas').select('id').limit(1);
      final detalles = await _db.from('detalle_venta').select('id').limit(1);
      final productos = await _db.from('productos').select('id').limit(1);

      String? errorStaff;
      try {
        await _db.from('sucursales').select('id').limit(1);
        await _db.from('empleados_pos').select('id').limit(1);
      } catch (e) {
        errorStaff = '$e';
      }

      final estadoModo = isSyncEnabled ? 'ACTIVA' : 'PAUSADA (Local)';
      final msg = errorStaff == null
          ? 'Lectura OK ($estadoModo). Escritura no comprobada por esta prueba.'
          : 'Lectura parcial ($estadoModo). Error en sucursales/empleados: $errorStaff';
      lastSyncStatusNotifier.value =
          '$msg (muestra máxima de 1 fila por tabla: ventas ${ventas.length}, '
          'productos ${productos.length}, detalles ${detalles.length})';
      return msg;
    } catch (e) {
      final err = 'Error de conexión con Supabase: $e';
      lastSyncStatusNotifier.value = err;
      return err;
    }
  }
}
