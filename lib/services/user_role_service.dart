import 'package:flutter/foundation.dart';
import 'app_auth_service.dart';

enum UserRole { user, admin }

/// UI permissions derived from the verified server profile, never a local toggle.
class UserRoleService extends ChangeNotifier {
  static final UserRoleService _instance = UserRoleService._internal();
  factory UserRoleService() => _instance;
  UserRoleService._internal() {
    AppAuthService().addListener(notifyListeners);
  }
  UserRole get currentRole => isAdmin ? UserRole.admin : UserRole.user;
  bool get isAdmin => AppAuthService().isAdmin;
  bool get isUser => !isAdmin;
  void requireAdmin() {
    if (!isAdmin) {
      throw StateError('Se requiere una sesión de administrador autorizada.');
    }
  }

  // Legacy callers cannot elevate permissions. Removed from the UI.
  bool loginAdmin(String username, String password) => false;
  void switchToUser() {
    notifyListeners();
  }

  void toggleRoleDirectly() {
    notifyListeners();
  }
}
