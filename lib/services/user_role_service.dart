import 'package:flutter/foundation.dart';

enum UserRole {
  user,
  admin,
}

class UserRoleService extends ChangeNotifier {
  static final UserRoleService _instance = UserRoleService._internal();
  factory UserRoleService() => _instance;
  UserRoleService._internal();

  // Siempre inicia en modo usuario por requerimiento del cliente
  UserRole _role = UserRole.user;

  UserRole get currentRole => _role;
  bool get isAdmin => _role == UserRole.admin;
  bool get isUser => _role == UserRole.user;

  /// Simulación de autenticación sin backend
  /// Usuario: admin
  /// Contraseña: admin
  bool loginAdmin(String username, String password) {
    if (username.trim().toLowerCase() == 'admin' && password.trim() == 'admin') {
      _role = UserRole.admin;
      notifyListeners();
      return true;
    }
    return false;
  }

  void switchToUser() {
    _role = UserRole.user;
    notifyListeners();
  }

  void toggleRoleDirectly() {
    _role = _role == UserRole.admin ? UserRole.user : UserRole.admin;
    notifyListeners();
  }
}
