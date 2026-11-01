import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/venta.dart';
import 'operator_auth_service.dart';
import 'supabase_environment.dart';
import 'operator_session.dart';

const supabaseUrl = 'https://zlljyvowdripxdgvhilz.supabase.co';
const supabaseKey = 'sb_publishable_QagT6TuxktFz4DgItZ6aEQ_jRv0DbUO';

class DbService {
  static const String _syncPrefKey = 'texas_db_sync_enabled';

  static SupabaseClient get _db => Supabase.instance.client;

  // The new online writer is not implemented. No UI preference enables writes.
  static const bool onlineSalesEnabled = false;
  static SupabaseEnvironment? environment;
  static OperatorSession? session;
  static OperatorAuthService get operatorAuth => OperatorAuthService(_db);

  static final ValueNotifier<bool> syncEnabledNotifier = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<String> lastSyncStatusNotifier =
      ValueNotifier<String>(
        'Guardado online no disponible; registro solo local',
      );

  static bool get isSyncEnabled => syncEnabledNotifier.value;

  static Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_syncPrefKey, enabled)) {
      throw StateError('No se pudo guardar la preferencia de sincronización.');
    }
    syncEnabledNotifier.value = enabled;
    lastSyncStatusNotifier.value = enabled
        ? 'Preferencia guardada; el guardado online sigue sin implementar'
        : 'Base de datos frenada (modo solo local)';
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_syncPrefKey) ?? true;
      syncEnabledNotifier.value = enabled;
      lastSyncStatusNotifier.value = enabled
          ? 'Preferencia guardada; conexión pendiente de comprobar. Guardado online no disponible'
          : 'Base de datos frenada (modo solo local)';
    } catch (_) {
      // Never resume remote writes if the saved preference could not be read.
      syncEnabledNotifier.value = false;
      lastSyncStatusNotifier.value =
          'No se pudo leer la configuración de BD; envío remoto pausado';
    }

    try {
      environment = SupabaseEnvironment.resolve(mainPublicKey: supabaseKey);
      await Supabase.initialize(
        url: environment!.url,
        publishableKey: environment!.publicKey,
        authOptions: const FlutterAuthClientOptions(
          persistSession: true,
          detectSessionInUri: false,
        ),
      );
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

  // Compatibility notification for the local history. No network writes,
  // retries or server acknowledgement are performed here.
  static Future<void> guardarVenta(Venta venta) async {
    lastSyncStatusNotifier.value = !isSyncEnabled
        ? 'BD frenada: Ticket #${venta.ticketNumber} guardado solo en dispositivo; sin confirmación remota'
        : 'Ticket #${venta.ticketNumber} guardado solo en dispositivo. Guardado online no disponible; sin confirmación remota';
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
          ? 'Lectura OK ($estadoModo). Escritura no comprobada; guardado online no disponible'
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
