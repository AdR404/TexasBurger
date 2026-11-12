import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/venta.dart';

/// One durable, explicit attempt, not an automatic synchronization queue.
class InventorySaleAttempt {
  InventorySaleAttempt({
    required this.project,
    required this.actor,
    required this.send,
  });
  final String project;
  final String actor;
  final Future<dynamic> Function(String id, Map<String, dynamic> request) send;
  String get key => 'texas_inventory_attempt_v1_$project';

  static String uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<Map<String, dynamic>?> pending() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (value['actor'] != actor) {
        throw StateError(
          'Existe un cobro pendiente de otro usuario. Inicia su sesión para recuperarlo.',
        );
      }
      return value;
    } on FormatException {
      throw StateError(
        'El intento pendiente no se puede leer. No se sobrescribirá.',
      );
    }
  }

  Future<void> _save(Map<String, dynamic> value) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(value),
    )) {
      throw StateError(
        'No se pudo conservar el intento. No se enviará otro cobro.',
      );
    }
  }

  Future<void> prepare(Venta sale, Map<String, dynamic> request) async {
    if (await pending() != null) {
      throw StateError(
        'Existe un cobro pendiente. Utiliza Recuperar cobro pendiente antes de cobrar otra venta.',
      );
    }
    final id = uuid();
    await _save({
      'actor': actor,
      'id': id,
      'request': request,
      'sale': {...sale.toJson(), 'id': id, 'operationId': id},
      'sent': false,
    });
  }

  Future<Venta> resume() async {
    final value = await pending();
    if (value == null) throw StateError('No hay un cobro pendiente.');
    if (value['result'] == null) {
      final previouslySent = value['sent'] == true;
      value['sent'] = true;
      await _save(value); // Durable before any network request.
      dynamic result;
      try {
        result = await send(
          value['id'] as String,
          Map<String, dynamic>.from(value['request'] as Map),
        ).timeout(const Duration(seconds: 30));
      } on PostgrestException catch (e) {
        // A rejection on a later retry does not prove the FIRST call failed.
        final definite =
            !previouslySent && const ['22023', '42501'].contains(e.code);
        if (definite) await acknowledge(value['id'] as String);
        throw StateError(
          definite
              ? 'Venta rechazada por el servidor: ${e.message}. No se registró este intento.'
              : 'No se pudo confirmar el cobro: ${e.message}. Conservamos el intento; recupera la misma operación, no vuelvas a cobrar.',
        );
      } catch (_) {
        throw StateError(
          'Resultado incierto por conexión. Conservamos el cobro pendiente. Usa Recuperar cobro pendiente; no vuelvas a cobrar.',
        );
      }
      if (result is! Map ||
          result['estado'] != 'complete' ||
          result['venta_id'] is! int ||
          (result['venta_id'] as int) <= 0 ||
          result['repetida'] is! bool ||
          !result.containsKey('caja_turno_id') ||
          (result['caja_turno_id'] != null &&
              (result['caja_turno_id'] is! int ||
                  (result['caja_turno_id'] as int) <= 0))) {
        throw StateError(
          'Respuesta no confirmada. Conservamos el intento para recuperar la misma operación.',
        );
      }
      value['result'] = Map<String, dynamic>.from(result);
      await _save(value);
    }
    final result = value['result'] as Map;
    return Venta.fromJson({
      ...Map<String, dynamic>.from(value['sale'] as Map),
      'remoteId': result['venta_id'],
      'cashTurnId': result['caja_turno_id'],
    });
  }

  Future<void> acknowledge(String id) async {
    final value = await pending();
    if (value == null || value['id'] != id) {
      throw StateError('El intento pendiente cambió.');
    }
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError(
        'Venta confirmada; falta cerrar el intento local. Recupera el cobro, no lo repitas.',
      );
    }
  }
}
