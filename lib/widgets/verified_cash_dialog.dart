import 'package:flutter/material.dart';

class CashSummaryView extends StatelessWidget {
  const CashSummaryView({super.key, required this.summary});
  final Map<String, dynamic> summary;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final e in const {
        'total_bruto': 'Total bruto',
        'total_cancelado': 'Cancelado',
        'total_neto': 'Total neto',
        'fondo_inicial': 'Fondo inicial',
        'entradas': 'Entradas',
        'salidas': 'Salidas',
        'efectivo_base_neta': 'Efectivo esperado',
      }.entries)
        Text('${e.value}: \$${(summary[e.key] as num).toStringAsFixed(2)}'),
      for (final method in ['Efectivo', 'Tarjeta', 'Transferencia'])
        Text(
          '$method neto: \$${((summary['por_metodo'] as Map)[method]['neto'] as num).toStringAsFixed(2)}',
        ),
      Text(
        'Órdenes válidas: ${summary['ordenes_validas']} · Canceladas: ${summary['ordenes_canceladas']}',
      ),
      if ((summary['efectivo_cancelado_sin_conciliar'] as num) > 0)
        const Text(
          'Hay efectivo pendiente. Concilia las ventas desde el historial remoto antes de cerrar.',
        ),
    ],
  );
}

/// Refresh first, then display that exact fingerprint until explicit confirmation.
class VerifiedCashDialog extends StatefulWidget {
  const VerifiedCashDialog({
    super.key,
    required this.load,
    required this.close,
  });
  final Future<Map<String, dynamic>> Function() load;
  final Future<void> Function(String, double, String) close;
  @override
  State<VerifiedCashDialog> createState() => _VerifiedCashDialogState();
}

class _VerifiedCashDialogState extends State<VerifiedCashDialog> {
  final _cash = TextEditingController(), _notes = TextEditingController();
  Map<String, dynamic>? _summary;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cash.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _summary = null;
    });
    try {
      final s = await widget.load();
      if (!mounted) return;
      if (s['cerrado'] != false) throw StateError('El turno ya está cerrado.');
      setState(() => _summary = s);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : 'No se pudo consultar el resumen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final s = _summary;
    final cash = double.tryParse(_cash.text);
    if (_busy || s == null) return;
    if (cash == null || !cash.isFinite || cash < 0) {
      setState(() => _error = 'Ingresa un efectivo contado válido.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.close(s['huella'] as String, cash, _notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summary = null;
        _error =
            '${e is StateError ? e.message : 'Cierre sin confirmar'}. Revisa el estado actualizado antes de confirmar nuevamente.';
      });
      // Read-only refresh, never resubmit or fall back to the previous RPC.
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Revisar y cerrar Caja'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_summary != null) CashSummaryView(summary: _summary!),
            TextField(
              controller: _cash,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Efectivo contado'),
            ),
            TextField(
              controller: _notes,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Actualizar resumen'),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  _summary == null ||
                  (_summary!['efectivo_cancelado_sin_conciliar'] as num) > 0
              ? null
              : _close,
          child: const Text('Confirmar cierre'),
        ),
      ],
    ),
  );
}
