import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/operator_session.dart';
import '../theme/app_theme.dart';

/// Shows the same verified session used by the application login.
class OperatorAccessCard extends StatelessWidget {
  const OperatorAccessCard({
    super.key,
    this.session,
    this.environmentLabel,
    this.contextMessage,
  });
  final OperatorSession? session;
  final String? environmentLabel;
  final String? contextMessage;

  @override
  Widget build(BuildContext context) {
    final controller = session ?? DbService.session;
    final label =
        environmentLabel ?? DbService.environment?.label ?? 'Sin configurar';
    if (controller == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Sesión remota no disponible. El inventario requiere iniciar sesión; consulta el estado de ventas en Configuración.',
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = switch (controller.state) {
          OperatorState.local => 'Sin sesión remota de inventario',
          OperatorState.authenticated =>
            controller.authenticated
                ? 'Cuenta autenticada mediante Supabase'
                : 'Sesión expirada',
          OperatorState.checking => 'Comprobando sesión',
          OperatorState.offline => 'Sesión sin conexión verificada',
          OperatorState.expired => 'Sesión expirada',
          OperatorState.error => 'Acceso remoto pendiente',
        };
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Acceso remoto · $label',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navyBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(status),
                if (controller.email != null) Text(controller.email!),
                if (controller.sessionOperatorId != null)
                  Text(
                    'Operador: ${controller.sessionOperatorId}',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (controller.message != null) Text(controller.message!),
                const SizedBox(height: 8),
                Text(
                  contextMessage ??
                      'Esta sesión permite acceder al inventario según los permisos de la cuenta. Las ventas dependen de la opción de guardado remoto y de la configuración de esta compilación.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (controller.sessionOperatorId != null) ...[
                      OutlinedButton(
                        onPressed: controller.busy ? null : controller.refresh,
                        child: const Text('Comprobar acceso'),
                      ),
                      TextButton(
                        onPressed: controller.busy ? null : controller.signOut,
                        child: const Text('Cerrar sesión de la aplicación'),
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
}
