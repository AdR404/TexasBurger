import 'dart:async';
import 'dart:convert';
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'role': role,
    'branchId': branchId,
    'branchName': branchName,
  };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String,
    role: json['role'] as String? ?? 'cajero',
    branchId: json['branchId'] as String?,
    branchName: json['branchName'] as String?,
  );
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
/// para Supabase Auth. Cuenta con soporte de demostración/desarrollo local
/// para no bloquear el frontend mientras el backend configura los usuarios en Supabase.
class AppAuthService extends ChangeNotifier {
  static final AppAuthService _instance = AppAuthService._internal();
  factory AppAuthService() => _instance;
  AppAuthService._internal();

  static const String _userSessionPrefKey = 'texas_auth_current_user_v1';
  static const String _customUsersPrefKey = 'texas_auth_registered_users_v1';

  final UserRoleService _roleService = UserRoleService();

  AuthUser? _currentUser;
  bool _initialized = false;
  bool _isLoading = false;

  /// Controla si se permiten las credenciales de prueba predefinidas en desarrollo.
  /// El equipo de backend puede cambiar esto a `false` una vez configurado Supabase Auth.
  bool enableMockFallback = true;

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
      final userJson = prefs.getString(_userSessionPrefKey);
      if (userJson != null) {
        final decoded = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUser = AuthUser.fromJson(decoded);
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
  /// Conexión para backend:
  /// Utiliza `_supabase.auth.signInWithPassword` si está disponible.
  /// Si falla o está en modo offline/mock, evalúa credenciales demo predefinidas.
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    final cleanEmail = email.trim().toLowerCase();
    final cleanPass = password.trim();

    try {
      // 1. Intento con Supabase Auth si el cliente está disponible
      final client = _supabase;
      if (client != null) {
        try {
          final response = await client.auth.signInWithPassword(
            email: cleanEmail,
            password: cleanPass,
          );

          final user = response.user;
          if (user != null) {
            final metadata = user.userMetadata ?? {};
            final role = (metadata['rol'] ?? metadata['role'] ?? 'cajero')
                .toString();
            final name =
                (metadata['nombre'] ?? metadata['name'] ?? user.email ?? '')
                    .toString();
            final branchId = metadata['sucursal_id'] as String?;
            final branchName = metadata['sucursal_nombre'] as String?;

            final authUser = AuthUser(
              id: user.id,
              email: user.email ?? cleanEmail,
              name: name.isNotEmpty ? name : 'Usuario',
              role: role,
              branchId: branchId,
              branchName: branchName,
            );

            await _saveSession(authUser);
            _applyRole(authUser.role);
            return AuthResult.ok(authUser, 'Sesión iniciada con Supabase Auth');
          }
        } on AuthException catch (e) {
          // Si Supabase responde credenciales inválidas y no usamos mock fallback, propagar error
          if (!enableMockFallback) {
            return AuthResult.fail(e.message);
          }
        } catch (e) {
          debugPrint('Supabase Auth error o no disponible: $e');
          if (!enableMockFallback) {
            return AuthResult.fail('No se pudo conectar al servidor de autenticación: $e');
          }
        }
      }

      // 2. Modo demostración / desarrollo local para pruebas del frontend
      if (enableMockFallback) {
        final mockUser = await _checkMockCredentials(cleanEmail, cleanPass);
        if (mockUser != null) {
          await _saveSession(mockUser);
          _applyRole(mockUser.role);
          return AuthResult.ok(mockUser, 'Sesión iniciada (Modo desarrollo)');
        }
      }

      return AuthResult.fail(
        'Credenciales incorrectas. Verifica tu correo y contraseña.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Registro de nuevos colaboradores realizado por un Administrador.
  ///
  /// Conexión para backend:
  /// El backend puede implementar este método llamando a:
  /// - Un Supabase Edge Function con Service Role (`admin.auth.admin.createUser`)
  /// - O una función RPC postgres en Supabase que inserte en `auth.users` y `public.usuarios`
  /// sin cerrar la sesión del admin actual.
  Future<AuthResult> registerUser({
    required String name,
    required String email,
    required String password,
    required String role, // 'cajero' | 'admin'
    String? branchId,
    String? branchName,
  }) async {
    _isLoading = true;
    notifyListeners();

    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPass = password.trim();
    final cleanRole = role.trim().toLowerCase();

    try {
      // Validaciones básicas de frontend
      if (cleanName.isEmpty) return AuthResult.fail('El nombre es obligatorio.');
      if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
        return AuthResult.fail('Ingresa un correo electrónico válido.');
      }
      if (cleanPass.length < 6) {
        return AuthResult.fail('La contraseña debe tener al menos 6 caracteres.');
      }

      // 1. Intento de llamada a Supabase (vía Edge Function o RPC si el backend la implementa)
      final client = _supabase;
      if (client != null && !enableMockFallback) {
        try {
          // NOTA PARA BACKEND:
          // Invocación recomendada para registrar usuario sin perder la sesión del admin:
          // final res = await client.functions.invoke('create-user', body: {
          //   'email': cleanEmail,
          //   'password': cleanPass,
          //   'name': cleanName,
          //   'role': cleanRole,
          //   'branch_id': branchId,
          // });
          // return AuthResult.ok(...);
        } catch (e) {
          debugPrint('Error en registro remoto: $e');
        }
      }

      // 2. Registro local/demo para pruebas de interfaz
      final newUser = AuthUser(
        id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
        email: cleanEmail,
        name: cleanName,
        role: cleanRole,
        branchId: branchId,
        branchName: branchName,
      );

      await _saveCustomUser(newUser, cleanPass);
      return AuthResult.ok(newUser, 'Usuario registrado con éxito.');
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
      if (client != null) {
        try {
          await client.auth.resetPasswordForEmail(cleanEmail);
          return const AuthResult(
            success: true,
            message:
                'Hemos enviado un enlace de recuperación a tu correo electrónico.',
          );
        } catch (e) {
          debugPrint('Supabase resetPassword error: $e');
          if (!enableMockFallback) {
            return AuthResult.fail(
              'No se pudo enviar el correo de recuperación: $e',
            );
          }
        }
      }

      // Simulación en modo desarrollo
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return const AuthResult(
        success: true,
        message:
            'Hemos enviado un enlace de recuperación a tu correo electrónico.',
      );
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
      if (client != null) {
        try {
          await client.auth.signOut();
        } catch (e) {
          debugPrint('Error en Supabase signOut: $e');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userSessionPrefKey);
      _currentUser = null;
      _roleService.switchToUser();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Obtiene la lista de usuarios registrados creados localmente durante pruebas.
  Future<List<AuthUser>> getRegisteredUsers() async {
    final list = <AuthUser>[
      const AuthUser(
        id: 'usr_admin_default',
        email: 'admin@texasburger.com',
        name: 'Administrador Texas',
        role: 'admin',
        branchId: 'norte',
        branchName: 'Norte',
      ),
      const AuthUser(
        id: 'usr_cajero_default',
        email: 'cajero@texasburger.com',
        name: 'Ana Torres (Cajera)',
        role: 'cajero',
        branchId: 'perimetral_sur',
        branchName: 'Perimetral Sur',
      ),
    ];

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString(_customUsersPrefKey);
      if (storedJson != null) {
        final List<dynamic> decoded = jsonDecode(storedJson) as List<dynamic>;
        for (final item in decoded) {
          final data = item as Map<String, dynamic>;
          list.add(AuthUser.fromJson(data['user'] as Map<String, dynamic>));
        }
      }
    } catch (e) {
      debugPrint('Error al leer usuarios creados: $e');
    }

    return list;
  }

  // ---------------------------------------------------------------------------
  // Métodos auxiliares y sincronización de roles
  // ---------------------------------------------------------------------------

  void _applyRole(String role) {
    if (role.toLowerCase() == 'admin') {
      _roleService.loginAdmin('admin', 'admin');
    } else {
      _roleService.switchToUser();
    }
  }

  Future<void> _saveSession(AuthUser user) async {
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userSessionPrefKey, jsonEncode(user.toJson()));
  }

  Future<void> _saveCustomUser(AuthUser user, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedJson = prefs.getString(_customUsersPrefKey);
    final List<dynamic> list = storedJson != null
        ? jsonDecode(storedJson) as List<dynamic>
        : [];

    list.add({
      'user': user.toJson(),
      'password': password,
    });

    await prefs.setString(_customUsersPrefKey, jsonEncode(list));
  }

  Future<AuthUser?> _checkMockCredentials(String email, String password) async {
    // 1. Usuarios demo preconfigurados
    if ((email == 'admin@texasburger.com' || email == 'admin') &&
        (password == 'admin123' || password == 'admin')) {
      return const AuthUser(
        id: 'usr_admin_demo',
        email: 'admin@texasburger.com',
        name: 'Administrador General',
        role: 'admin',
        branchId: 'norte',
        branchName: 'Norte',
      );
    }

    if ((email == 'cajero@texasburger.com' || email == 'cajero') &&
        (password == 'caja123' || password == 'caja')) {
      return const AuthUser(
        id: 'usr_cajero_demo',
        email: 'cajero@texasburger.com',
        name: 'Ana Torres',
        role: 'cajero',
        branchId: 'perimetral_sur',
        branchName: 'Perimetral Sur',
      );
    }

    // 2. Usuarios creados por el admin en la app
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString(_customUsersPrefKey);
      if (storedJson != null) {
        final List<dynamic> list = jsonDecode(storedJson) as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final userMap = map['user'] as Map<String, dynamic>;
          final storedEmail = (userMap['email'] as String).toLowerCase();
          final storedPass = map['password'] as String;

          if (storedEmail == email && storedPass == password) {
            return AuthUser.fromJson(userMap);
          }
        }
      }
    } catch (_) {}

    return null;
  }
}

