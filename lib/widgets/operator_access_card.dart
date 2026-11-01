import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/operator_session.dart';
import '../theme/app_theme.dart';

/// Remote identity never changes UserRoleService or unlocks local admin tools.
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
                    if (controller.sessionOperatorId == null)
                      FilledButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) => _OperatorLoginDialog(
                                  session: controller,
                                  environment: label,
                                ),
                              ),
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar sesión remota'),
                      ),
                    if (controller.sessionOperatorId != null) ...[
                      OutlinedButton(
                        onPressed: controller.busy ? null : controller.refresh,
                        child: const Text('Comprobar acceso'),
                      ),
                      TextButton(
                        onPressed: controller.busy ? null : controller.signOut,
                        child: const Text('Cerrar sesión remota'),
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

class _OperatorLoginDialog extends StatefulWidget {
  const _OperatorLoginDialog({
    required this.session,
    required this.environment,
  });
  final OperatorSession session;
  final String environment;
  @override
  State<_OperatorLoginDialog> createState() => _OperatorLoginDialogState();
}

class _OperatorLoginDialogState extends State<_OperatorLoginDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await widget.session.signIn(_email.text.trim(), _password.text);
    _password.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.session.sessionOperatorId != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Acceso Supabase · ${widget.environment}'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Usa tu cuenta individual asignada. Este acceso no modifica el rol local de demostración.',
              ),
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                ),
                validator: (value) => value != null && value.contains('@')
                    ? null
                    : 'Escribe tu correo',
              ),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Contraseña remota',
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Escribe tu contraseña'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (widget.session.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(widget.session.message!),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Entrar'),
        ),
      ],
    ),
  );
}
