import 'package:flutter/material.dart';

import '../models/discount_code.dart';
import '../services/discount_code_service.dart';
import '../theme/app_theme.dart';
import '../services/user_role_service.dart';
import 'admin_access.dart';

class DiscountCodesDialog extends StatefulWidget {
  const DiscountCodesDialog({super.key});

  @override
  State<DiscountCodesDialog> createState() => _DiscountCodesDialogState();
}

class _DiscountCodesDialogState extends State<DiscountCodesDialog> {
  final DiscountCodeService _service = DiscountCodeService();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  DiscountKind _kind = DiscountKind.percentage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    _service.init();
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    _codeController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _busy = false;

  Future<void> _runAdmin(Future<void> Function() action) async {
    if (_busy || !UserRoleService().isAdmin) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo guardar el cambio. Los datos anteriores se conservan.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCode() async {
    if (!UserRoleService().isAdmin) return;
    final code = _codeController.text.trim();
    final value = double.tryParse(
      _valueController.text.trim().replaceAll(',', '.'),
    );
    if (code.isEmpty ||
        value == null ||
        !value.isFinite ||
        value <= 0 ||
        (_kind == DiscountKind.percentage && value > 100)) {
      setState(
        () => _error = _kind == DiscountKind.percentage
            ? 'Escribe un código y un porcentaje entre 0.01 y 100.'
            : 'Escribe un código y una cantidad mayor que 0.',
      );
      return;
    }

    await _service.save(
      DiscountCode(
        code: code,
        description: _descriptionController.text.trim(),
        kind: _kind,
        value: value,
      ),
    );
    if (!mounted) return;
    _codeController.clear();
    _descriptionController.clear();
    _valueController.clear();
    setState(() => _error = null);
  }

  String _description(DiscountCode coupon) {
    final value = coupon.kind == DiscountKind.percentage
        ? '${coupon.value.toStringAsFixed(coupon.value % 1 == 0 ? 0 : 2)}%'
        : '\$${coupon.value.toStringAsFixed(2)}';
    return '${coupon.description.isEmpty ? 'Descuento' : coupon.description} • $value';
  }

  @override
  Widget build(BuildContext context) =>
      AdminAccess(dialog: true, builder: _buildAdmin);

  Widget _buildAdmin(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Códigos locales'),
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_service.loadFailed)
              const Text(
                'No se pudieron cargar los códigos. Los datos guardados no se han modificado.',
              ),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Código'),
            ),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la promoción',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<DiscountKind>(
                    initialValue: _kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(
                        value: DiscountKind.percentage,
                        child: Text('Porcentaje'),
                      ),
                      DropdownMenuItem(
                        value: DiscountKind.fixedAmount,
                        child: Text('Cantidad fija'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _kind = value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _valueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _kind == DiscountKind.percentage
                          ? 'Porcentaje'
                          : 'MXN',
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy || _service.loadFailed
                    ? null
                    : () => _runAdmin(_saveCode),
                icon: const Icon(Icons.add),
                label: const Text('Guardar código'),
              ),
            ),
            const Divider(height: 12),
            SizedBox(
              height: 180,
              child: _service.codes.isEmpty
                  ? const Center(child: Text('Aún no hay códigos guardados.'))
                  : ListView.separated(
                      itemCount: _service.codes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final coupon = _service.codes[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            coupon.code,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(_description(coupon)),
                          leading: const Icon(
                            Icons.local_offer,
                            color: AppTheme.primary,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: coupon.isActive,
                                onChanged: _busy
                                    ? null
                                    : (value) => _runAdmin(
                                        () => _service.setActive(
                                          coupon.code,
                                          value,
                                        ),
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Eliminar código',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _runAdmin(
                                        () => _service.remove(coupon.code),
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
