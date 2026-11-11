import 'package:flutter/material.dart';
import '../services/app_auth_service.dart';
import '../services/db_service.dart';
import '../services/operator_session.dart';
import '../theme/app_theme.dart';

/// Shows the same verified session used by the application login.
class OperatorAccessCard extends StatelessWidget {
  const OperatorAccessCard({super.key, this.session});
  final OperatorSession? session;

  @override
  Widget build(BuildContext context) {
    final controller = session ?? DbService.session;
    return ListenableBuilder(
      listenable: controller ?? AppAuthService(),
      builder: (context, _) {
        final user = AppAuthService().currentUser;
        final isAdmin = user?.isAdmin ?? false;
        final connected = controller?.authenticated ?? false;
        final role = switch (user?.role) {
          'admin' => 'Administrador',
          'cajero' => 'Cajero',
          _ => 'Sin sesión',
        };
        final busy = controller?.busy ?? false;
        final connectionStatus = busy
            ? 'Comprobando...'
            : connected
            ? 'Conectado'
            : 'Sin conexión';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.manage_accounts_outlined,
                      color: AppTheme.navyBlue,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Cuenta y acceso remoto',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navyBlue,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    _StatusChip(
                      label: connectionStatus,
                      connected: connected,
                      checking: busy,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _AccessInfoRow(
                  label: 'Estado de conexión',
                  value: connectionStatus,
                  valueColor: connected
                      ? AppTheme.successGreen
                      : AppTheme.danger,
                ),
                _AccessInfoRow(label: 'Rol', value: role),
                _AccessInfoRow(
                  label: 'Correo electrónico',
                  value: controller?.email ?? user?.email ?? 'No disponible',
                ),
                _AccessInfoRow(
                  label: 'Acceso al inventario',
                  value: connected && isAdmin ? 'Autorizado' : 'No autorizado',
                  valueColor: connected && isAdmin
                      ? AppTheme.successGreen
                      : AppTheme.danger,
                ),
                _AccessInfoRow(
                  label: 'Permisos administrativos',
                  value: isAdmin ? 'Activos' : 'Inactivos',
                  valueColor: isAdmin
                      ? AppTheme.successGreen
                      : AppTheme.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  'El acceso administrativo y al inventario depende de los permisos de esta cuenta.',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (controller?.sessionOperatorId != null) ...[
                      OutlinedButton(
                        onPressed: busy ? null : controller!.refresh,
                        child: const Text('Comprobar conexión y permisos'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => _confirmSignOut(context, controller!),
                        child: const Text('Cerrar sesión en este equipo'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    OperatorSession controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión en este equipo'),
        content: const Text(
          'Esta acción cerrará tu sesión solo en este dispositivo. '
          'No afectará tu sesión en otros dispositivos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.signOut();
  }
}

class _AccessInfoRow extends StatelessWidget {
  const _AccessInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.connected,
    required this.checking,
  });

  final String label;
  final bool connected;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final color = checking
        ? AppTheme.navyBlue
        : connected
        ? AppTheme.successGreen
        : AppTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
