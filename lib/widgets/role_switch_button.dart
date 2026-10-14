import 'package:flutter/material.dart';
import '../services/user_role_service.dart';
import '../theme/app_theme.dart';

class RoleSwitchButton extends StatefulWidget {
  const RoleSwitchButton({super.key});

  @override
  State<RoleSwitchButton> createState() => _RoleSwitchButtonState();
}

class _RoleSwitchButtonState extends State<RoleSwitchButton> {
  final UserRoleService _roleService = UserRoleService();

  @override
  void initState() {
    super.initState();
    _roleService.addListener(_onRoleChanged);
  }

  @override
  void dispose() {
    _roleService.removeListener(_onRoleChanged);
    super.dispose();
  }

  void _onRoleChanged() {
    if (mounted) setState(() {});
  }

  void _showAdminLoginDialog() {
    final userController = TextEditingController();
    final passController = TextEditingController();
    String? errorMessage;
    bool obscurePassword = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.navyBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppTheme.navyBlue,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Modo Administrador',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppTheme.navyBlue,
                          ),
                        ),
                        Text(
                          'Ingresa credenciales de acceso',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.lightRed,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.primaryRed.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppTheme.primaryRed,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: AppTheme.primaryRed,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    TextField(
                      controller: userController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Usuario',
                        hintText: 'admin',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: passController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        hintText: 'admin',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) {
                        final ok = _roleService.loginAdmin(
                          userController.text,
                          passController.text,
                        );
                        if (ok) {
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppTheme.navyBlue,
                              content: Row(
                                children: [
                                  Icon(Icons.verified, color: AppTheme.gold),
                                  SizedBox(width: 10),
                                  Text(
                                    'Modo Administrador activado con éxito.',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        } else {
                          setDialogState(() {
                            errorMessage =
                                'Credenciales incorrectas. Simulación: admin / admin';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Demo: usuario "admin" | contraseña "admin"',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final ok = _roleService.loginAdmin(
                      userController.text,
                      passController.text,
                    );
                    if (ok) {
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: AppTheme.navyBlue,
                          content: Row(
                            children: [
                              Icon(Icons.verified, color: AppTheme.gold),
                              SizedBox(width: 10),
                              Text(
                                'Modo Administrador activado con éxito.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } else {
                      setDialogState(() {
                        errorMessage =
                            'Credenciales incorrectas. Simulación: admin / admin';
                      });
                    }
                  },
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Entrar como Admin'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.navyBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSwitchToUserDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.person_outline, color: AppTheme.navyBlue),
            SizedBox(width: 10),
            Expanded(
              child: Text('Cambiar a Modo Usuario'),
            ),
          ],
        ),
        content: const Text(
          '¿Deseas volver a la vista de usuario? En esta vista no se pueden modificar precios ni agregar productos o promociones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _roleService.switchToUser();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white),
                      SizedBox(width: 10),
                      Text('Has regresado a la vista de Usuario.'),
                    ],
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.navyBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cambiar a Usuario'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _roleService.isAdmin;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isAdmin ? _showSwitchToUserDialog : _showAdminLoginDialog,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isAdmin
                ? AppTheme.gold
                : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isAdmin ? Colors.white : Colors.white.withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              if (isAdmin)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.person,
                color: isAdmin ? AppTheme.navyBlue : Colors.white,
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                isAdmin ? 'Admin' : 'Usuario',
                style: TextStyle(
                  color: isAdmin ? AppTheme.navyBlue : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.swap_horiz,
                color: isAdmin ? AppTheme.navyBlue : Colors.white70,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
