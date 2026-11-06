import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'operator_auth_service.dart';
import 'app_auth_service.dart';

enum OperatorState { local, authenticated, checking, offline, expired, error }

/// Compatibility adapter: uses the application's single Auth session/profile.
class OperatorSession extends ChangeNotifier {
  OperatorSession(this.auth, this.prefs, {required this.projectId});
  final OperatorAuthGateway auth;
  final SharedPreferences prefs;
  final String projectId;
  final AppAuthService _app = AppAuthService();
  bool get busy => _app.isLoading;
  String? get message => _app.message;
  OperatorState get state => busy
      ? OperatorState.checking
      : authenticated
      ? OperatorState.authenticated
      : OperatorState.local;
  bool get authenticated => _app.isAuthenticated;
  String? get email => _app.currentUserEmail;
  String? get sessionOperatorId => _app.currentUser?.id;
  String? get validOperatorId => _app.currentUser?.id;
  int? get businessUserId => _app.currentUser?.businessId;
  String? get employeeId => _app.currentUser?.employeeId;
  Future<void> initialize() async {
    _app.addListener(notifyListeners);
  }

  Future<void> refresh() => _app.refresh();
  Future<void> signOut() => _app.signOut();
  @override
  void dispose() {
    _app.removeListener(notifyListeners);
    super.dispose();
  }
}
