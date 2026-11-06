import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sale_context.dart';
import 'caja_service.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.businessId,
    required this.employeeId,
    required this.employeeName,
    this.branchId,
    this.branchName,
  });
  final String id, email, name, role, employeeId, employeeName;
  final int businessId;
  final String? branchId, branchName;
  bool get isAdmin => role == 'admin';
  bool get isCajero => role == 'cajero';

  factory AuthUser.fromProfile(
    String uid,
    String email,
    Map<String, dynamic> p,
  ) {
    final role = p['rol'];
    if (p['usuario_id'] is! int ||
        p['activo'] != true ||
        p['empleado_activo'] != true ||
        p['empleado_es_demo'] != false ||
        p['empleado_pos_id'] is! String ||
        (p['empleado_pos_id'] as String).trim().isEmpty ||
        p['empleado_nombre'] is! String ||
        (p['empleado_nombre'] as String).trim().isEmpty ||
        !['admin', 'cajero'].contains(role) ||
        (role == 'admin' && p['administrador_efectivo'] != true) ||
        (role == 'cajero' && p['sucursal_id'] == null) ||
        (p['sucursal_id'] != null &&
            (p['sucursal_activa'] != true ||
                p['sucursal_nombre'] is! String))) {
      throw StateError(
        'La cuenta no tiene un perfil operativo habilitado. Solicita al administrador revisar usuario, empleado y sucursal.',
      );
    }
    return AuthUser(
      id: uid,
      email: email,
      name: p['nombre'] as String? ?? '',
      role: role as String,
      businessId: p['usuario_id'] as int,
      employeeId: p['empleado_pos_id'] as String,
      employeeName: p['empleado_nombre'] as String,
      branchId: p['sucursal_id'] as String?,
      branchName: p['sucursal_nombre'] as String?,
    );
  }
}

class AuthResult {
  const AuthResult({required this.success, this.message, this.user});
  final bool success;
  final String? message;
  final AuthUser? user;
  factory AuthResult.ok(AuthUser user, [String? message]) =>
      AuthResult(success: true, user: user, message: message);
  factory AuthResult.fail(String message) =>
      AuthResult(success: false, message: message);
}

/// The SDK owns token persistence. Profiles are always read from the authenticated RPC.
class AppAuthService extends ChangeNotifier {
  static final AppAuthService _instance = AppAuthService._internal();
  factory AppAuthService() => _instance;
  AppAuthService._internal();
  SupabaseClient? _client;
  SharedPreferences? _prefs;
  StreamSubscription<AuthState>? _subscription;
  Timer? _expiry;
  AuthUser? _user;
  bool _loading = false;
  bool _signingIn = false;
  bool _recovering = false;
  bool _registering = false;
  bool get isRecoveringPassword => _recovering;
  bool get isRegistering => _registering;
  String get authRedirect => kIsWeb
      ? Uri.base.replace(query: '', fragment: '').toString()
      : 'texasburger://auth/callback';
  int _revision = 0;
  String? message;
  Map<String, String> _branches = {};
  Map<String, String> get branches => Map.unmodifiable(_branches);
  AuthUser? get currentUser => isAuthenticated ? _user : null;
  bool get isAuthenticated =>
      !_recovering &&
      !_loading &&
      _user != null &&
      _client?.auth.currentSession?.isExpired == false &&
      _client?.auth.currentUser?.id == _user!.id;
  bool get isLoading => _loading;
  bool get isAdmin => currentUser?.isAdmin ?? false;
  String? get currentUserName => currentUser?.name;
  String? get currentUserEmail => currentUser?.email;
  String get currentUserRole => currentUser?.role ?? 'cajero';

  Future<void> init({SupabaseClient? client}) async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    // Remove only legacy mock identity/credentials; preserve sales and settings.
    for (final key in [
      'texas_auth_current_user_v1',
      'texas_auth_registered_users_v1',
      'texas_staff_context',
    ]) {
      if (!await prefs.remove(key)) {
        throw StateError(
          'No se pudieron limpiar los datos de la sesión anterior.',
        );
      }
    }
    await _subscription?.cancel();
    try {
      _client = client ?? Supabase.instance.client;
    } catch (_) {
      _client = null;
    }
    _recovering =
        _client?.auth.currentUser != null &&
        prefs.getString('texas_password_recovery_uid') ==
            _client!.auth.currentUser!.id;
    _subscription = _client?.auth.onAuthStateChange.listen(
      (event) {
        if (event.event == AuthChangeEvent.passwordRecovery &&
            event.session != null) {
          _clear();
          _recovering = true;
          unawaited(_rememberRecovery(event.session!.user.id));
          notifyListeners();
          return;
        }
        if (_signingIn) return;
        if (event.event == AuthChangeEvent.signedOut || event.session == null) {
          _clear();
        } else if (event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.tokenRefreshed ||
            event.event == AuthChangeEvent.userUpdated) {
          if (!_loading && !_recovering) unawaited(refresh());
        }
      },
      onError: (Object _) {
        _clear();
        message =
            'El enlace o la sesión no son válidos. Solicita otro enlace o inicia sesión con conexión.';
        notifyListeners();
      },
    );
    // A replayed recovery event must win over profile restoration.
    await Future<void>.delayed(Duration.zero);
    if (!_recovering) await refresh();
  }

  Future<void> _rememberRecovery(String uid) async {
    try {
      if (await _prefs?.setString('texas_password_recovery_uid', uid) != true) {
        throw StateError('No se pudo conservar el estado de recuperación.');
      }
    } catch (_) {
      await signOut();
      message = 'No se pudo preparar la recuperación. Solicita otro enlace.';
      notifyListeners();
    }
  }

  void _clear() {
    _revision++;
    _recovering = false;
    _expiry?.cancel();
    _user = null;
    _branches = {};
    _loading = false;
    CajaService().clearOperatorContext();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_recovering) return;
    final revision = ++_revision;
    _loading = true;
    notifyListeners();
    try {
      final client = _client;
      final session = client?.auth.currentSession;
      if (client == null || session == null) {
        _clear();
        return;
      }
      if (session.isExpired) {
        await client.auth.refreshSession().timeout(const Duration(seconds: 15));
      }
      final identity = await client.auth.getUser().timeout(
        const Duration(seconds: 15),
      );
      final rows = await client
          .rpc('login_mi_perfil')
          .retry(enabled: false)
          .timeout(const Duration(seconds: 15));
      if (revision != _revision) return;
      if (rows is! List ||
          rows.length != 1 ||
          identity.user?.id != client.auth.currentUser?.id) {
        throw StateError(
          'La cuenta no está habilitada para utilizar la aplicación. Solicita la vinculación de su perfil.',
        );
      }
      final user = AuthUser.fromProfile(
        identity.user!.id,
        identity.user!.email ?? '',
        Map<String, dynamic>.from(rows.single as Map),
      );
      final branches = await client
          .from('sucursales')
          .select('id,nombre')
          .eq('empresa_id', SaleContext.texasBurgerId)
          .eq('activo', true)
          .retry(enabled: false)
          .timeout(const Duration(seconds: 15));
      if (revision != _revision) return;
      final available = {
        for (final b in branches) b['id'] as String: b['nombre'] as String,
      };
      if (available.isEmpty ||
          (user.branchId != null && !available.containsKey(user.branchId))) {
        throw StateError(
          'No hay una sucursal activa disponible para esta cuenta.',
        );
      }
      final previousBranch = _user?.id == user.id
          ? CajaService().saleContext?.branchId
          : null;
      CajaService().clearOperatorContext();
      _user = user;
      _branches = user.branchId == null
          ? available
          : {user.branchId!: available[user.branchId]!};
      final localShiftBranch =
          !CajaService().remoteMode && CajaService().isCajaOpen
          ? CajaService().activeCorte?.openingContext?.branchId
          : null;
      final selected =
          user.branchId ??
          (available.containsKey(localShiftBranch) ? localShiftBranch : null) ??
          (available.containsKey(previousBranch) ? previousBranch : null);
      if (selected != null) {
        CajaService().setOperatorContext(
          SaleContext(
            branchId: selected,
            branchName: available[selected]!,
            employeeId: user.employeeId,
            employeeName: user.employeeName,
          ),
        );
      }
      _loading = false;
      message = null;
      _expiry?.cancel();
      final expires = client.auth.currentSession?.expiresAt;
      if (expires != null) {
        _expiry = Timer(
          Duration(
            seconds: (expires - DateTime.now().millisecondsSinceEpoch ~/ 1000)
                .clamp(0, 86400),
          ),
          () => unawaited(refresh()),
        );
      }
      notifyListeners();
    } catch (error) {
      if (revision != _revision) return;
      _clear();
      message = error is StateError
          ? error.message.toString()
          : 'No se pudo validar el acceso. Comprueba tu conexión e inicia sesión nuevamente.';
      try {
        await _client?.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    if (_signingIn) {
      return AuthResult.fail('Espera a que termine el inicio de sesión.');
    }
    _signingIn = true;
    _clear();
    _loading = true;
    notifyListeners();
    try {
      await _prefs?.remove('texas_password_recovery_uid');
      final client = _client;
      if (client == null) {
        return AuthResult.fail(
          'Supabase no está disponible. Reinicia con conexión.',
        );
      }
      await client.auth
          .signInWithPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 20));
      await refresh();
      return isAuthenticated
          ? AuthResult.ok(_user!)
          : AuthResult.fail(message ?? 'Cuenta no habilitada.');
    } catch (_) {
      _clear();
      try {
        await _client?.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      return AuthResult.fail(
        'No se pudo iniciar sesión. Revisa correo, contraseña y conexión.',
      );
    } finally {
      _signingIn = false;
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _clear();
    try {
      await _client?.auth.signOut(scope: SignOutScope.local);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('texas_staff_context');
      await prefs.remove('texas_password_recovery_uid');
    } catch (_) {
      message =
          'Acceso bloqueado. No se pudo confirmar el cierre de sesión; vuelve a intentarlo con conexión.';
    }
    notifyListeners();
  }

  Future<List<AuthUser>> getRegisteredUsers() async => const [];

  Future<AuthResult> registerUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
    String? branchName,
  }) async {
    if (!isAdmin || _registering) {
      return AuthResult.fail('Se requiere una sesión administrativa válida.');
    }
    if (name.trim().isEmpty ||
        !email.contains('@') ||
        password.length < 8 ||
        !['admin', 'cajero'].contains(role) ||
        (role == 'cajero' && branchId == null) ||
        (branchId != null && !branches.containsKey(branchId))) {
      return AuthResult.fail(
        'Revisa nombre, correo, contraseña (8 caracteres), rol y sucursal.',
      );
    }
    final actor = currentUser!.id;
    _registering = true;
    notifyListeners();
    try {
      final response = await _client!.functions
          .invoke(
            'admin-register-user',
            body: {
              'name': name.trim(),
              'email': email.trim().toLowerCase(),
              'password': password,
              'role': role,
              'branch_id': branchId,
            },
          )
          .timeout(const Duration(seconds: 30));
      if (currentUser?.id != actor) {
        return AuthResult.fail(
          'La sesión cambió durante el registro. Consulta al administrador antes de repetirlo.',
        );
      }
      final data = response.data;
      if (response.status == 200 &&
          data is Map &&
          data['state'] == 'pending_confirmation') {
        // Deployed versions also use this state with success=false.
        return const AuthResult(
          success: true,
          message:
              'Usuario registrado correctamente. Se solicitó el envío del correo de confirmación. El empleado deberá confirmar su correo antes de iniciar sesión.',
        );
      }
      if (response.status != 200 || data is! Map || data['success'] != true) {
        return AuthResult.fail(
          'No se confirmó el alta. Revisa el estado con el administrador antes de repetirla.',
        );
      }
      return AuthResult(
        success: true,
        message:
            data['message'] as String? ??
            'Cuenta y empleado creados. Falta confirmar el correo.',
      );
    } on FunctionException catch (error) {
      final data = error.details;
      return AuthResult.fail(
        data is Map && data['message'] is String
            ? data['message'] as String
            : 'No se pudo registrar. Comprueba el despliegue y los permisos.',
      );
    } catch (_) {
      return AuthResult.fail(
        'No se recibió confirmación. El alta podría haberse completado; verifica su estado antes de repetirla.',
      );
    } finally {
      _registering = false;
      notifyListeners();
    }
  }

  Future<AuthResult> updateRecoveredPassword(String password) async {
    if (!_recovering || _client?.auth.currentSession == null) {
      return AuthResult.fail('Solicita un enlace de recuperación nuevo.');
    }
    if (password.length < 8) {
      return AuthResult.fail('Utiliza al menos 8 caracteres.');
    }
    try {
      await _client!.auth.updateUser(UserAttributes(password: password));
      // Keep recovery isolated from operational navigation until logout finishes.
      await signOut();
      message =
          'Contraseña actualizada. Inicia sesión con tu nueva contraseña.';
      notifyListeners();
      return const AuthResult(success: true);
    } on AuthException catch (error) {
      return AuthResult.fail(error.message);
    } catch (_) {
      return AuthResult.fail(
        'No se confirmó el cambio de contraseña. Comprueba tu conexión.',
      );
    }
  }

  Future<AuthResult> sendPasswordResetEmail({required String email}) async {
    try {
      if (_client == null) throw StateError('Sin conexión');
      await _client!.auth
          .resetPasswordForEmail(email.trim(), redirectTo: authRedirect)
          .timeout(const Duration(seconds: 15));
      return const AuthResult(
        success: true,
        message:
            'Si el correo corresponde a una cuenta, recibirás un enlace para cambiar tu contraseña.',
      );
    } catch (_) {
      return AuthResult.fail(
        'No se pudo solicitar la recuperación. Revisa la conexión e intenta nuevamente.',
      );
    }
  }
}
