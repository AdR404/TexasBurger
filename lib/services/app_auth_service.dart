import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_role_service.dart';

/// Modelo de usuario autenticado en Texas Burger.
class AuthUser {
  final String id;
  final String email;
  final String name;
  final String role; // 'cajero' | 'admin'
  final String? branchId;
  final String? branchName;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.branchId,
    this.branchName,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isCajero => role.toLowerCase() == 'cajero';

}

/// Resultado de operaciones de autenticación.
class AuthResult {
  final bool success;
  final String? message;
  final AuthUser? user;

  const AuthResult({required this.success, this.message, this.user});

  factory AuthResult.ok(AuthUser user, [String? message]) =>
      AuthResult(success: true, user: user, message: message);

  factory AuthResult.fail(String message) =>
      AuthResult(success: false, message: message);
}

/// Servicio central de autenticación de Texas Burger.
///
/// Encapsula la lógica de sesión, roles de usuario y las conexiones preparadas
/// para Supabase Auth.
class AppAuthService extends ChangeNotifier {
  static final AppAuthService _instance = AppAuthService._internal();
  factory AppAuthService() => _instance;
  AppAuthService._internal();

  static const String _legacyUserSessionPrefKey = 'texas_auth_current_user_v1';
  static const String _legacyCustomUsersPrefKey = 'texas_auth_registered_users_v1';
  static const String debugAdminEmail = 'admin.pruebas@texasburger.test';
  static const String debugAdminPassword = 'AdminDemo_2026!';
  static const String debugCashierEmail = 'cajera.pruebas@texasburger.test';
  static const String debugCashierPassword = 'CajeraDemo_2026!';

  final UserRoleService _roleService = UserRoleService();

  AuthUser? _currentUser;
  bool _initialized = false;
  bool _isLoading = false;
  bool _isLocalTestSession = false;

  AuthUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get currentUserName => _currentUser?.name;
  String? get currentUserEmail => _currentUser?.email;
  String get currentUserRole => _currentUser?.role ?? 'cajero';
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  /// Acceso seguro al cliente Supabase si ya fue inicializado.
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Inicializa la sesión guardada si existe.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyUserSessionPrefKey);
      await prefs.remove(_legacyCustomUsersPrefKey);
      final user = _supabase?.auth.currentUser;
      if (user != null) {
        _currentUser = _authUserFromSupabase(user);
        _applyRole(_currentUser!.role);
      }
    } catch (e) {
      debugPrint('Error al restaurar sesión previa: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Inicia sesión con correo y contraseña.
  ///
  /// La autenticación requiere una cuenta real de Supabase Auth.
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();
    try {
      if (kDebugMode && cleanEmail.endsWith('@texasburger.test')) {
        final testUser = _debugTestUser(cleanEmail, cleanPassword);
        if (testUser == null) {
          return AuthResult.fail('Credenciales de prueba incorrectas.');
        }
        _currentUser = testUser;
        _isLocalTestSession = true;
        _applyRole(testUser.role);
        return AuthResult.ok(testUser, 'Sesión local de prueba');
      }

      final client = _supabase;
      if (client == null) {
        return AuthResult.fail('El servicio de autenticación no está disponible.');
      }
      final response = await client.auth.signInWithPassword(
        email: cleanEmail,
        password: cleanPassword,
      );
      final user = response.user;
      if (user == null) {
        return AuthResult.fail('No se recibió una sesión válida.');
      }
      final authUser = _authUserFromSupabase(user);
      _currentUser = authUser;
      _isLocalTestSession = false;
      _applyRole(authUser.role);
      return AuthResult.ok(authUser, 'Sesión iniciada con Supabase Auth');
    } on AuthException catch (e) {
      return AuthResult.fail(e.message);
    } catch (e) {
      debugPrint('Supabase Auth error: $e');
      return AuthResult.fail('No se pudo conectar al servicio de autenticación.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Solicitud de restablecimiento de contraseña.
  ///
  /// Conexión para backend:
  /// Llama a `_supabase.auth.resetPasswordForEmail(email)`.
  Future<AuthResult> sendPasswordResetEmail({required String email}) async {
    _isLoading = true;
    notifyListeners();

    final cleanEmail = email.trim().toLowerCase();

    try {
      if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
        return AuthResult.fail('Ingresa un correo electrónico válido.');
      }

      final client = _supabase;
      if (client == null) {
        return AuthResult.fail('El servicio de autenticación no está disponible.');
      }
      await client.auth.resetPasswordForEmail(cleanEmail);
      return const AuthResult(
        success: true,
        message:
            'Hemos enviado un enlace de recuperación a tu correo electrónico.',
      );
    } on AuthException catch (e) {
      return AuthResult.fail(e.message);
    } catch (e) {
      debugPrint('Supabase resetPassword error: $e');
      return AuthResult.fail('No se pudo enviar el correo de recuperación.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cierra la sesión activa.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      final client = _supabase;
      if (client != null && !_isLocalTestSession) {
        try {
          await client.auth.signOut();
        } catch (e) {
          debugPrint('Error en Supabase signOut: $e');
        }
      }

      _currentUser = null;
      _isLocalTestSession = false;
      _roleService.switchToUser();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Métodos auxiliares y sincronización de roles
  // ---------------------------------------------------------------------------

  void _applyRole(String role) {
    _roleService.setAuthenticatedRole(role);
  }

  AuthUser? _debugTestUser(String email, String password) {
    if (email == debugAdminEmail && password == debugAdminPassword) {
      return const AuthUser(
        id: 'local_test_admin',
        email: debugAdminEmail,
        name: 'Admin de prueba',
        role: 'admin',
      );
    }
    if (email == debugCashierEmail && password == debugCashierPassword) {
      return const AuthUser(
        id: 'local_test_cashier',
        email: debugCashierEmail,
        name: 'Cajera de prueba',
        role: 'cajero',
      );
    }
    return null;
  }

  AuthUser _authUserFromSupabase(User user) {
    final metadata = user.userMetadata ?? {};
    final role = (metadata['rol'] ?? metadata['role'] ?? 'cajero').toString();
    final name = (metadata['nombre'] ?? metadata['name'] ?? user.email ?? '')
        .toString();
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      name: name.isNotEmpty ? name : 'Usuario',
      role: role,
      branchId: metadata['sucursal_id'] as String?,
      branchName: metadata['sucursal_nombre'] as String?,
    );
  }
}

