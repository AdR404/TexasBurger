import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote identity only. Never reads or changes the local UI role.
abstract class OperatorAuthGateway {
  String? get currentOperatorId;
  String? get validOperatorId;
  String? get email;
  Stream<void> get changes;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> verifySession();
}

class OperatorAuthService implements OperatorAuthGateway {
  OperatorAuthService(this.client);
  final SupabaseClient client;
  @override
  String? get email => client.auth.currentUser?.email;
  @override
  Stream<void> get changes => client.auth.onAuthStateChange.map((_) {});

  @override
  String? get currentOperatorId => client.auth.currentSession?.user.id;
  @override
  String? get validOperatorId {
    final session = client.auth.currentSession;
    return session == null || session.isExpired ? null : session.user.id;
  }

  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (validOperatorId == null) {
      throw StateError('Sesión remota no disponible');
    }
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut(scope: SignOutScope.local);
    // Supabase.initialize restores storage asynchronously. If that restoration
    // finishes during logout, clear the recovered session as well.
    if (client.auth.currentSession != null) {
      await client.auth.signOut(scope: SignOutScope.local);
    }
    if (client.auth.currentSession != null) {
      throw StateError('No se pudo confirmar el cierre de sesión local');
    }
  }

  @override
  Future<void> verifySession() async {
    final operator = validOperatorId;
    if (operator == null) throw StateError('Se requiere una sesión válida');
    final result = await client.auth.getUser();
    if (result.user?.id != operator || validOperatorId != operator) {
      throw StateError('La identidad remota cambió');
    }
  }
}
