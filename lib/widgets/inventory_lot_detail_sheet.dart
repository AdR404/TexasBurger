
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inventory_lot.dart';
import '../theme/app_theme.dart';
import 'inventory_expiry_badge.dart';

class InventoryLotDetailSheet extends StatelessWidget {
  final String ingredientName;
  final List<InventoryLot> lots;
  final bool isDemo;

  const InventoryLotDetailSheet({
    super.key,
    required this.ingredientName,
    required this.lots,
    this.isDemo = false,
  });

  String _date(DateTime value) {
    return DateFormat('dd/MM/yyyy').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Detalle de inventario',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.navyBlue,
              ),
            ),

            const SizedBox(height: 6),

            if (isDemo)
              const Text(
                'MODO DEMOSTRACIÓN: existencias simuladas.',
                style: TextStyle(color: AppTheme.goldDark, fontWeight: FontWeight.bold),
              ),

            Text(
              ingredientName,
              style: const TextStyle(
                fontSize: 18,
                color: AppTheme.textMuted,
              ),
            ),

            const SizedBox(height: 18),

            if (lots.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Todavía no hay lotes registrados '
                        'para este ingrediente.\n\n'
                        'Las cantidades y fechas aparecerán '
                        'cuando conectemos el inventario.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            if (lots.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Disponible: ${inventoryAvailableText(lots)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppTheme.navyBlue,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              ...lots.map(
                    (lot) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lote #${lot.id}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.navyBlue,
                          ),
                        ),

                        const Divider(),

                        Text(
                          'Disponible: '
                              '${formatInventoryQuantity(lot.availableQuantity)} '
                              '${lot.unit}',
                        ),
                        Text(
                          'Cantidad inicial: '
                              '${formatInventoryQuantity(lot.initialQuantity)} '
                              '${lot.unit}',
                        ),
                        Text(
                          'Ubicación: ${lot.location}',
                        ),
                        Text(
                          'Costo unitario: '
                              '\$${lot.unitCost.toStringAsFixed(2)} '
                              'por ${lot.unit}',
                        ),
                        Text(
                          'Valor disponible: '
                              '\$${(lot.availableQuantity * lot.unitCost).toStringAsFixed(2)}',
                        ),
                        Text(
                          'Fecha de entrada: '
                              '${_date(lot.entryDate)}',
                        ),
                        Text(
                          'Caducidad: '
                              '${_date(lot.expirationDate)}'
                              '${lot.estimatedExpiration ? ' (aproximada)' : ''}',
                        ),
                        const SizedBox(height: 10),

                        if (lot.availableQuantity > 0)
                          InventoryExpiryBadge(
                            expirationDate: lot.expirationDate,
                          )
                        else
                          const Text(
                            'Lote sin existencias',
                            style: TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
