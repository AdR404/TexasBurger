import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'operator_auth_service.dart';

enum OperatorState { local, authenticated, checking, offline, expired, error }

/// Supabase identity only. Business permissions for online sales are not enabled.
class OperatorSession extends ChangeNotifier {
  OperatorSession(this.auth, this.prefs, {required this.projectId});
  final OperatorAuthGateway auth;
  final SharedPreferences prefs;
  final String projectId;
  StreamSubscription<void>? _subscription;
  String? _verifiedId;
  bool _selected = false;
  String? _selectedId;
  bool _disposed = false;
  int _revision = 0;
  bool busy = false;
  OperatorState state = OperatorState.local;
  String? message;
  String get _modeKey => 'texas_remote_mode_$projectId';
  String get _operatorKey => 'texas_remote_operator_$projectId';
  String? get email => _selected ? auth.email : null;
  String? get sessionOperatorId => _selected ? auth.currentOperatorId : null;
  bool get authenticated =>
      _selected &&
      state == OperatorState.authenticated &&
      _selectedId != null &&
      _verifiedId == _selectedId &&
      auth.validOperatorId == _selectedId;
  String? get validOperatorId => authenticated ? auth.validOperatorId : null;

  Future<void> initialize() async {
    _selected = prefs.getBool(_modeKey) ?? false;
    _selectedId = prefs.getString(_operatorKey);
    _subscription = auth.changes.listen(
      (_) {
        if (!busy) unawaited(refresh());
      },
      onError: (Object error) {
        // A token refresh/network error must not crash the startup/UI.
        if (!busy) unawaited(refresh());
      },
    );
    await refresh();
  }

  Future<void> signIn(String email, String password) async {
    if (busy) return;
    busy = true;
    _revision++;
    _selected = false;
    _selectedId = null;
    _verifiedId = null;
    state = OperatorState.local;
    message = null;
    _notify();
    try {
      if (!await prefs.setBool(_modeKey, false)) throw StateError('storage');
      await auth.signIn(email, password).timeout(const Duration(seconds: 15));
      final id = auth.validOperatorId;
      if (id == null || !await prefs.setString(_operatorKey, id)) {
        throw StateError('identity');
      }
      if (!await prefs.setBool(_modeKey, true)) throw StateError('storage');
      _selectedId = id;
      _selected = true;
      await refresh();
    } on AuthRetryableFetchException {
      state = OperatorState.error;
      message =
          'No se pudo contactar al servidor de acceso. Puedes continuar en modo local.';
    } on AuthException {
      state = OperatorState.error;
      message =
          'No se pudo iniciar sesión. Comprueba las credenciales y el estado de la cuenta.';
    } on SocketException {
      state = OperatorState.error;
      message = 'Sin conexión. Puedes continuar en modo local.';
    } on TimeoutException {
      state = OperatorState.error;
      message =
          'El acceso tardó demasiado. Continúa localmente o vuelve a intentar.';
    } catch (_) {
      state = OperatorState.error;
      message =
          'No se pudo completar el acceso remoto. Las ventas locales se conservan.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    final revision = ++_revision;
    _verifiedId = null;
    final id = _selected ? auth.currentOperatorId : null;
    if (id == null) {
      state = OperatorState.local;
      _notify();
      return;
    }
    if (id != _selectedId) {
      state = OperatorState.error;
      message =
          'La sesión cambió de operador. Cierra sesión e inicia el acceso de nuevo.';
      _notify();
      return;
    }
    if (auth.validOperatorId == null) {
      state = OperatorState.expired;
      message = 'Sesión expirada. Renueva el acceso con conexión a internet.';
      _notify();
      return;
    }
    state = OperatorState.checking;
    message = null;
    _notify();
    try {
      await auth.verifySession().timeout(const Duration(seconds: 8));
      if (_disposed || revision != _revision || auth.validOperatorId != id) {
        return;
      }
      _verifiedId = id;
      state = OperatorState.authenticated;
      message =
          'Identidad comprobada. La autorización y el guardado de ventas online están pendientes de implementar.';
    } catch (error) {
      if (_disposed || revision != _revision || auth.currentOperatorId != id) {
        return;
      }
      if (error is SocketException ||
          error is TimeoutException ||
          error is AuthRetryableFetchException) {
        state = auth.validOperatorId == null
            ? OperatorState.expired
            : OperatorState.offline;
        message =
            'Sin conexión verificable. No se puede confirmar una venta remota.';
      } else {
        state = OperatorState.error;
        message =
            'No se pudo verificar la sesión. Cierra sesión y vuelve a iniciar el acceso.';
      }
    }
    _notify();
  }

  Future<void> signOut() async {
    if (busy) return;
    busy = true;
    _revision++;
    _selected = false;
    _selectedId = null;
    _verifiedId = null;
    state = OperatorState.local;
    message = null;
    _notify();
    try {
      final saved = await prefs.setBool(_modeKey, false);
      await auth.signOut().timeout(const Duration(seconds: 8));
      if (!saved) throw StateError('storage');
    } catch (_) {
      message =
          'Modo local activado. No se pudo confirmar el cierre remoto; vuelve a intentarlo con conexión.';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
