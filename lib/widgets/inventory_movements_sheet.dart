
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inventory_lot.dart';
import '../services/user_role_service.dart';
import '../theme/app_theme.dart';
import 'inventory_expiry_badge.dart';

enum InventoryMovementKind { salida, descarte }

// Datos preparados para una futura conexión.
// Esta clase NO guarda ni modifica inventario.
class InventoryMovementDraft {
  final InventoryMovementKind type;
  final int lotId;
  final int ingredientId;
  final String ingredientName;
  final double quantity;
  final String unit;
  final String reason;
  final DateTime createdAt;
  final bool isDemo;

  const InventoryMovementDraft({
    required this.type,
    required this.lotId,
    required this.ingredientId,
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    required this.reason,
    required this.createdAt,
    required this.isDemo,
  });
}

Future<InventoryMovementDraft?> showInventoryMovementsSheet(
    BuildContext context, {
      required List<InventoryLot> lots,
      required bool isDemo,
    }) {
  return showModalBottomSheet<InventoryMovementDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _InventoryMovementsSheet(
      lots: lots,
      isDemo: isDemo,
    ),
  );
}

class _InventoryMovementsSheet extends StatefulWidget {
  final List<InventoryLot> lots;
  final bool isDemo;

  const _InventoryMovementsSheet({
    required this.lots,
    required this.isDemo,
  });

  @override
  State<_InventoryMovementsSheet> createState() =>
      _InventoryMovementsSheetState();
}

class _InventoryMovementsSheetState
    extends State<_InventoryMovementsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  String _section = 'Entradas';
  int? _selectedLotId;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double? _parseQuantity(String text) {
    return double.tryParse(
      text.trim().replaceAll(',', '.'),
    );
  }

  void _validateMovement(InventoryLot? selectedLot) {
    if (!UserRoleService().isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso exclusivo para administradores.'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    if (selectedLot == null) return;

    final quantity = _parseQuantity(
      _quantityController.text,
    )!;

    final type = _section == 'Salidas'
        ? InventoryMovementKind.salida
        : InventoryMovementKind.descarte;

    // Validación adicional antes de regresar los datos.
    if (quantity <= 0 ||
        quantity > selectedLot.availableQuantity ||
        (type == InventoryMovementKind.salida &&
            inventoryDaysToExpire(
              selectedLot.expirationDate,
            ) <
                0)) {
      return;
    }

    Navigator.pop(
      context,
      InventoryMovementDraft(
        type: type,
        lotId: selectedLot.id,
        ingredientId: selectedLot.ingredientId,
        ingredientName: selectedLot.ingredientName,
        quantity: quantity,
        unit: selectedLot.unit,
        reason: _reasonController.text.trim(),
        createdAt: DateTime.now(),
        isDemo: widget.isDemo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSalida = _section == 'Salidas';

    final eligibleLots = widget.lots.where((lot) {
      if (lot.availableQuantity <= 0) return false;

      // Un lote caducado no puede seleccionarse
      // para una salida de consumo.
      if (isSalida &&
          inventoryDaysToExpire(lot.expirationDate) < 0) {
        return false;
      }

      return true;
    }).toList()
      ..sort(
            (a, b) =>
            a.expirationDate.compareTo(b.expirationDate),
      );

    InventoryLot? selectedLot;

    for (final lot in eligibleLots) {
      if (lot.id == _selectedLotId) {
        selectedLot = lot;
        break;
      }
    }

    final maxAvailable = selectedLot?.availableQuantity;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            18, 8, 18, 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Movimientos de inventario',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navyBlue,
                ),
              ),

              const SizedBox(height: 8),

              if (widget.isDemo)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.goldSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'MODO DEMOSTRACIÓN: estos lotes '
                        'son simulados y no se guardarán.',
                    style: TextStyle(
                      color: AppTheme.navyBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'Entradas',
                  'Salidas',
                  'Descartes',
                ].map((section) {
                  return ChoiceChip(
                    label: Text(section),
                    selected: _section == section,
                    selectedColor: AppTheme.goldSoft,
                    showCheckmark: false,
                    onSelected: (selected) {
                      if (!selected) return;

                      setState(() {
                        _section = section;
                        _selectedLotId = null;
                        _quantityController.clear();
                        _reasonController.clear();
                      });
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              if (_section == 'Entradas') ...[
                const Text(
                  'Entradas de mercancía',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navyBlue,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Las entradas se registran desde '
                      'el botón "Agregar lote" de Inventario. '
                      'Cada entrada debe crear un lote nuevo.',
                ),

                const SizedBox(height: 12),

                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Volver para agregar lote',
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'Lotes recibidos (consulta)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navyBlue,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Esta lista muestra los lotes '
                      'disponibles en pantalla, no un '
                      'historial completo de movimientos.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 12),

                if (widget.lots.isEmpty)
                  const Text(
                    'Todavía no hay lotes conectados.',
                  ),

                ...widget.lots.map(
                      (lot) => Card(
                    child: ListTile(
                      title: Text(
                        '${lot.ingredientName} · Lote #${lot.id}',
                      ),
                      subtitle: Text(
                        'Entrada: '
                            '${DateFormat('dd/MM/yyyy').format(lot.entryDate)}\n'
                            'Cantidad inicial: '
                            '${formatInventoryQuantity(lot.initialQuantity)} '
                            '${lot.unit} · ${lot.location}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  isSalida
                      ? 'Registrar salida'
                      : 'Registrar descarte',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navyBlue,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  isSalida
                      ? 'Selecciona el lote del que se '
                      'utilizará materia prima. '
                      'Los lotes caducados no están '
                      'disponibles para consumo.'
                      : 'Selecciona el lote que deseas '
                      'descartar e indica el motivo.',
                ),

                const SizedBox(height: 16),

                if (eligibleLots.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No hay lotes disponibles para '
                            'esta operación. Activa los datos '
                            'simulados para probar la interfaz.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                if (eligibleLots.isNotEmpty)
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<int>(
                          key: ValueKey(_section),
                          initialValue: _selectedLotId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Lote',
                            border: OutlineInputBorder(),
                          ),
                          items: eligibleLots.map((lot) {
                            return DropdownMenuItem<int>(
                              value: lot.id,
                              child: Text(
                                '${lot.ingredientName} '
                                    '· #${lot.id} '
                                    '· ${formatInventoryQuantity(lot.availableQuantity)} '
                                    '${lot.unit}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedLotId = value;
                            });
                          },
                          validator: (value) => value == null
                              ? 'Selecciona un lote.'
                              : null,
                        ),

                        const SizedBox(height: 14),

                        if (selectedLot != null)
                          Text(
                            'Disponible: '
                                '${formatInventoryQuantity(selectedLot.availableQuantity)} '
                                '${selectedLot.unit}\n'
                                'Ubicación: ${selectedLot.location}',
                            style: const TextStyle(
                              color: AppTheme.navyBlue,
                            ),
                          ),

                        const SizedBox(height: 14),

                        TextFormField(
                          controller: _quantityController,
                          keyboardType:
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: selectedLot == null
                                ? 'Cantidad'
                                : 'Cantidad (${selectedLot.unit})',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (text) {
                            final quantity =
                            _parseQuantity(text ?? '');

                            if (quantity == null ||
                                !quantity.isFinite ||
                                quantity <= 0) {
                              return 'Introduce una cantidad válida.';
                            }

                            if (maxAvailable != null &&
                                quantity > maxAvailable) {
                              return 'Supera las existencias '
                                  'del lote.';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 14),

                        TextFormField(
                          controller: _reasonController,
                          maxLines: 2,
                          maxLength: 180,
                          decoration: const InputDecoration(
                            labelText: 'Motivo',
                            hintText:
                            'Ej. Preparación de alimentos',
                            border: OutlineInputBorder(),
                          ),
                          validator: (text) =>
                          (text == null ||
                              text.trim().isEmpty)
                              ? 'Indica el motivo.'
                              : null,
                        ),

                        const SizedBox(height: 16),

                        ElevatedButton(
                          onPressed: () =>
                              _validateMovement(selectedLot),
                          child: Text(
                            isSalida
                                ? 'Validar salida'
                                : 'Validar descarte',
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                const Text(
                  'Versión de prueba: validar no '
                      'descuenta existencias ni guarda '
                      'movimientos en Supabase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
