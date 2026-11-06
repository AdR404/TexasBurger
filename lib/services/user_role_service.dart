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

  /// Local UI permission check; this is not backend authentication.
  void requireAdmin() {
    if (!isAdmin) {
      throw StateError('Esta operación requiere el modo administrador.');
    }
  }

  void setAuthenticatedRole(String role) {
    _role = role.toLowerCase() == 'admin' ? UserRole.admin : UserRole.user;
    notifyListeners();
  }

  void switchToUser() {
    _role = UserRole.user;
    notifyListeners();
  }

}
