import 'package:flutter/material.dart';
import '../screens/auth/admin_register_user_screen.dart';
import '../services/app_auth_service.dart';
import '../services/user_role_service.dart';
import '../theme/app_theme.dart';

class UserSessionButton extends StatelessWidget {
  const UserSessionButton({super.key});

  void _showUserMenu(BuildContext context) {
    final authService = AppAuthService();
    final roleService = UserRoleService();
    final user = authService.currentUser;
    final isAdmin = roleService.isAdmin || (user?.isAdmin ?? false);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Barra de agarre
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Perfil del Usuario
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: isAdmin
                          ? AppTheme.goldLight
                          : AppTheme.primarySoft,
                      child: Icon(
                        isAdmin
                            ? Icons.admin_panel_settings_rounded
                            : Icons.person_rounded,
                        color: AppTheme.navyBlue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user?.name ??
                                      (isAdmin ? 'Administrador' : 'Cajero'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.navyBlue,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isAdmin
                                      ? AppTheme.goldLight
                                      : AppTheme.primarySoft,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isAdmin
                                        ? AppTheme.gold
                                        : AppTheme.navyBlueLight,
                                  ),
                                ),
                                child: Text(
                                  isAdmin ? 'ADMIN' : 'CAJERO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isAdmin
                                        ? AppTheme.goldDark
                                        : AppTheme.navyBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? 'Sesión local activa',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(),

                // Opción exclusiva de Admin: Registrar Nuevo Usuario
                if (isAdmin) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.goldLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: AppTheme.navyBlue,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Registrar Nuevo Usuario',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.navyBlue,
                      ),
                    ),
                    subtitle: const Text(
                      'Alta de cajeros y administradores',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.navyBlue,
                    ),
                    onTap: () {
                      Navigator.pop(bottomSheetCtx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminRegisterUserScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                ],
                // Cerrar Sesión
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: AppTheme.danger,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Cerrar Sesión',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.danger,
                    ),
                  ),
                  subtitle: const Text(
                    'Salir de la cuenta actual de Texas Burger',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(bottomSheetCtx);
                    await authService.signOut();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleService = UserRoleService();
    final authService = AppAuthService();

    return ListenableBuilder(
      listenable: Listenable.merge([roleService, authService]),
      builder: (context, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showUserMenu(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.more_vert, color: Colors.white70, size: 14),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
