
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/ingredient_catalog.dart';
import '../services/user_role_service.dart';
import '../theme/app_theme.dart';

// Datos validados de una nueva entrada.
// Todavía no se guardan en Supabase.
class InventoryLotDraft {
  final String ingredientName;
  final double quantity;
  final String unit;
  final String location;
  final double unitCost;
  final DateTime entryDate;
  final DateTime expirationDate;
  final bool estimatedExpiration;

  const InventoryLotDraft({
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    required this.location,
    required this.unitCost,
    required this.entryDate,
    required this.expirationDate,
    required this.estimatedExpiration,
  });
}

Future<InventoryLotDraft?> showAddInventoryLotSheet(
    BuildContext context,
    ) {
  return showModalBottomSheet<InventoryLotDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _AddInventoryLotSheet(),
  );
}

class _AddInventoryLotSheet extends StatefulWidget {
  const _AddInventoryLotSheet();

  @override
  State<_AddInventoryLotSheet> createState() =>
      _AddInventoryLotSheetState();
}

class _AddInventoryLotSheetState
    extends State<_AddInventoryLotSheet> {
  final _formKey = GlobalKey<FormState>();

  final _quantityController = TextEditingController();
  final _costController = TextEditingController();
  final _expirationController = TextEditingController();

  late final TextEditingController _entryController;

  String? _ingredient;
  String _unit = 'kg';
  String _location = 'Refrigerador';
  bool _estimatedExpiration = false;

  DateTime _entryDate = DateUtils.dateOnly(DateTime.now());
  DateTime? _expirationDate;

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  void initState() {
    super.initState();

    _entryController = TextEditingController(
      text: _formatDate(_entryDate),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _entryController.dispose();
    _expirationController.dispose();
    super.dispose();
  }

  double? _parseNumber(String text) {
    return double.tryParse(
      text.trim().replaceAll(',', '.'),
    );
  }

  String? _validatePositive(String? text) {
    final number = _parseNumber(text ?? '');

    if (number == null || !number.isFinite || number <= 0) {
      return 'Introduce un número mayor que cero.';
    }

    return null;
  }

  Future<void> _selectDate({
    required bool expiration,
  }) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: expiration
          ? (_expirationDate ?? _entryDate)
          : _entryDate,
      firstDate: expiration
          ? _entryDate
          : DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selected == null || !mounted) return;

    setState(() {
      if (expiration) {
        _expirationDate = selected;
        _expirationController.text = _formatDate(selected);
      } else {
        _entryDate = selected;
        _entryController.text = _formatDate(selected);

        if (_expirationDate != null &&
            _expirationDate!.isBefore(_entryDate)) {
          _expirationDate = null;
          _expirationController.clear();
        }
      }
    });
  }

  void _validateDraft() {
    if (!UserRoleService().isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso exclusivo para administradores.'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final draft = InventoryLotDraft(
      ingredientName: _ingredient!,
      quantity: _parseNumber(_quantityController.text)!,
      unit: _unit,
      location: _location,
      unitCost: _parseNumber(_costController.text)!,
      entryDate: _entryDate,
      expirationDate: _expirationDate!,
      estimatedExpiration: _estimatedExpiration,
    );

    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Agregar lote de inventario',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navyBlue,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Registra una entrada de materia prima.',
              ),

              const SizedBox(height: 20),

              DropdownButtonFormField<String>(
                initialValue: _ingredient,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Ingrediente',
                  border: OutlineInputBorder(),
                ),
                items: IngredientCatalog.defaultIngredients.map(
                      (ingredient) => DropdownMenuItem(
                    value: ingredient,
                    child: Text(
                      ingredient,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ).toList(),
                onChanged: (value) {
                  setState(() => _ingredient = value);
                },
                validator: (value) => value == null
                    ? 'Selecciona un ingrediente.'
                    : null,
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      keyboardType:
                      const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validatePositive,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: const InputDecoration(
                        labelText: 'Unidad',
                        border: OutlineInputBorder(),
                      ),
                      items: ['kg', 'g', 'pzas', 'L', 'ml']
                          .map(
                            (unit) => DropdownMenuItem(
                          value: unit,
                          child: Text(unit),
                        ),
                      )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _unit = value);
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                initialValue: _location,
                decoration: const InputDecoration(
                  labelText: 'Ubicación',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Almacén',
                    child: Text('Almacén'),
                  ),
                  DropdownMenuItem(
                    value: 'Refrigerador',
                    child: Text('Refrigerador'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _location = value);
                  }
                },
              ),

              const SizedBox(height: 14),

              TextFormField(
                controller: _costController,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Costo por unidad',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                validator: _validatePositive,
              ),

              const SizedBox(height: 14),

              TextFormField(
                controller: _entryController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Fecha de entrada',
                  border: OutlineInputBorder(),
                ),
                onTap: () => _selectDate(expiration: false),
              ),

              const SizedBox(height: 14),

              TextFormField(
                controller: _expirationController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Fecha de caducidad',
                  hintText: 'Seleccionar fecha',
                  border: OutlineInputBorder(),
                ),
                onTap: () => _selectDate(expiration: true),
                validator: (_) => _expirationDate == null
                    ? 'Selecciona una fecha de caducidad.'
                    : null,
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Caducidad aproximada'),
                subtitle: const Text(
                  'Activa si la fecha es una estimación.',
                ),
                value: _estimatedExpiration,
                onChanged: (value) {
                  setState(() {
                    _estimatedExpiration = value;
                  });
                },
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _validateDraft,
                      child: const Text('Validar datos'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              const Text(
                'Versión de prueba: los datos todavía '
                    'no se guardarán en la base de datos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
