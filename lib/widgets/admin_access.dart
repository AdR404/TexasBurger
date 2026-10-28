import 'package:flutter/material.dart';
import '../services/user_role_service.dart';

/// Rechecks the local role even for direct routes and already-open dialogs.
class AdminAccess extends StatelessWidget {
  const AdminAccess({super.key, required this.builder, this.dialog = false});

  final WidgetBuilder builder;
  final bool dialog;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: UserRoleService(),
    builder: (context, _) {
      if (UserRoleService().isAdmin) return builder(context);
      const message = Text('Disponible solo en modo administrador.');
      if (dialog) {
        return AlertDialog(
          content: message,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      }
      return const Center(child: message);
    },
  );
}

Future<T?> showAdminDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  if (!UserRoleService().isAdmin) return null;
  return showDialog<T>(
    context: context,
    builder: (context) => AdminAccess(dialog: true, builder: builder),
  );
}
