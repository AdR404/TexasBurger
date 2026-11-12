import 'package:flutter/material.dart';
import '../services/sale_actions.dart';

class SaleActionsPanel extends StatefulWidget {
  const SaleActionsPanel({
    super.key,
    required this.sale,
    required this.onChanged,
    this.actions,
    this.ticketStyle = false,
  });
  final Map<String, dynamic> sale;
  final Future<void> Function() onChanged;
  final SaleActions? actions;
  final bool ticketStyle;
  @override
  State<SaleActionsPanel> createState() => _SaleActionsPanelState();
}

class _SaleActionsPanelState extends State<SaleActionsPanel> {
  late final SaleActions actions = widget.actions ?? SaleActions();
  bool _busy = false;
  // After any submitted mutation, require a fresh server view before another.
  bool _submitted = false;
  String? _message;

  Future<void> _form(bool reconcile) async {
    String note = '';
    bool restore = false, confirmed = false;
    String state = 'no_cobrado';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(reconcile ? 'Conciliar efectivo' : 'Cancelar venta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reconcile) ...[
                  DropdownButtonFormField<String>(
                    initialValue: state,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'no_cobrado',
                        child: Text('Nunca se cobró'),
                      ),
                      DropdownMenuItem(
                        value: 'devuelto',
                        child: Text('Cobrado y devuelto'),
                      ),
                    ],
                    onChanged: (v) => update(() => state = v!),
                  ),
                  const Text(
                    'No debe existir otra salida de Caja por esta devolución. Si ya existe, requiere revisión administrativa para evitar descontar dos veces. No se devuelve dinero automáticamente.',
                  ),
                ],
                TextField(
                  maxLines: 3,
                  onChanged: (value) => update(() => note = value),
                  decoration: InputDecoration(
                    labelText: reconcile
                        ? 'Nota obligatoria'
                        : 'Motivo obligatorio',
                  ),
                ),
                if (!reconcile)
                  CheckboxListTile(
                    value: restore,
                    onChanged: (v) => update(() => restore = v!),
                    title: const Text('Reintegrar ingredientes consumidos'),
                  ),
                CheckboxListTile(
                  value: confirmed,
                  onChanged: (v) => update(() => confirmed = v!),
                  title: Text(
                    reconcile
                        ? 'Confirmo el estado y que NO existe otra salida por esta devolución'
                        : 'Confirmo la cancelación. El ticket se conservará.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: confirmed && note.trim().isNotEmpty
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    final reason = note;
    if (accepted != true || !mounted || _busy || _submitted) return;
    setState(() {
      _busy = true;
      _submitted = true;
    });
    try {
      final r = reconcile
          ? await actions.reconcile(widget.sale, state, reason, confirmed)
          : await actions.cancel(widget.sale, reason, restore: restore);
      if (!mounted) return;
      setState(
        () => _message = r['repetida'] == true
            ? 'La operación ya estaba registrada. Actualiza el historial.'
            : reconcile
            ? 'Conciliación registrada. Actualiza Caja antes de cerrar.'
            : 'Venta cancelada. El ticket se conserva.',
      );
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message =
              '${e is StateError ? e.message : 'No se pudo confirmar la operación'}. Cierra este detalle y actualiza antes de intentar nuevamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    if (!actions.canManage(sale)) return const SizedBox.shrink();
    final cancel = actions.cancelEnabled && sale['estado'] == 'activa';
    final reconcile =
        actions.cashEnabled &&
        sale['estado'] == 'cancelada' &&
        sale['metodo_pago'] == 'Efectivo' &&
        sale['efectivo_cancelacion_estado'] == null;
    final actionButton = widget.ticketStyle
        ? Tooltip(
            message: reconcile ? 'Conciliar efectivo' : 'Cancelar venta',
            child: TextButton.icon(
              onPressed: _busy || _submitted ? null : () => _form(reconcile),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade800,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                minimumSize: const Size(0, 52),
                textStyle: const TextStyle(fontSize: 11),
              ),
              icon: Icon(
                reconcile ? Icons.payments_outlined : Icons.cancel_outlined,
                size: 18,
              ),
              label: Text(reconcile ? 'Conciliar' : 'Cancelar'),
            ),
          )
        : TextButton.icon(
            onPressed: _busy || _submitted ? null : () => _form(reconcile),
            icon: Icon(
              reconcile ? Icons.payments_outlined : Icons.cancel_outlined,
            ),
            label: Text(reconcile ? 'Conciliar efectivo' : 'Cancelar venta'),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_message != null) Text(_message!),
        if (_busy) const LinearProgressIndicator(),
        if (cancel || reconcile) ...[
          if (!widget.ticketStyle)
            const Text(
              'Requiere permiso explícito para esta sucursal; el servidor validará la autorización.',
            ),
          actionButton,
        ],
      ],
    );
  }
}
