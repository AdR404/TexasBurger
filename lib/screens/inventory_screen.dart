
import 'package:flutter/material.dart';

import '../services/user_role_service.dart';
import '../theme/app_theme.dart';
import '../data/ingredient_catalog.dart';
import '../widgets/add_inventory_lot_sheet.dart';
import '../models/inventory_lot.dart';
import '../widgets/inventory_lot_detail_sheet.dart';
import '../data/inventory_demo_data.dart';
import '../widgets/inventory_expiry_badge.dart';
import '../widgets/inventory_movements_sheet.dart';

class InventoryScreen extends StatefulWidget {
  final VoidCallback onBack;
  final List<InventoryLot> lots;

  const InventoryScreen({
    super.key,
    required this.onBack,
    this.lots = const [],
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _search = '';
  String _locationFilter = 'Todos';
  bool _demoMode = false;

  @override
  Widget build(BuildContext context) {
    // Segunda comprobación del permiso de administrador.
    if (!UserRoleService().isAdmin) {
      return const Center(
        child: Text('Acceso exclusivo para administradores.'),
      );
    }

    final search = _search.trim().toLowerCase();

    final displayedLots =
    _demoMode ? InventoryDemoData.create() : widget.lots;


    final totalIngredients =
        IngredientCatalog.defaultIngredients.length;

// Ingredientes que tienen algún lote disponible
// que caduca entre hoy y los próximos 30 días.
    final expiringIngredients = displayedLots
        .where((lot) {
      final days = inventoryDaysToExpire(
        lot.expirationDate,
      );

      return lot.availableQuantity > 0 &&
          days >= 0 &&
          days <= 30;
    })
        .map((lot) => lot.ingredientName)
        .toSet()
        .length;

// Ingredientes que tienen lotes registrados.
    final ingredientsWithLots = displayedLots
        .map((lot) => lot.ingredientName)
        .toSet();

// Ingredientes cuyos lotes están todos agotados.
    final outOfStockIngredients =
        ingredientsWithLots.where((ingredient) {
          final ingredientLots = displayedLots.where(
                (lot) => lot.ingredientName == ingredient,
          );

          return ingredientLots.every(
                (lot) => lot.availableQuantity <= 0,
          );
        }).length;

// Si no hay lotes cargados, no mostramos
// cantidades de alerta como si fueran reales.
    final hasLotData = displayedLots.isNotEmpty;


    final filteredIngredients =
    IngredientCatalog.defaultIngredients.where((ingredient) {
      // Primero aplicamos el buscador.
      final matchesSearch =
      ingredient.toLowerCase().contains(search);

      if (!matchesSearch) return false;

      // Todos muestra el catálogo completo.
      if (_locationFilter == 'Todos') {
        return true;
      }

      // Las demás opciones requieren lotes con ubicación.
      return displayedLots.any(
            (lot) =>
        lot.ingredientName == ingredient &&
            lot.location == _locationFilter,
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.creamBg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onBack,
              child: const Text('Volver al menú'),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Inventario de materia prima',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.navyBlue,
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.gold,
                width: 1.5,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo administrador activo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.navyBlue,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Controla tus insumos, lotes y fechas de caducidad. '
                      'Cada nueva entrada sumará existencias.',
                  style: TextStyle(
                    color: AppTheme.navyBlue,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),


          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Total de insumos',
                  value: '$totalIngredients',
                  background: AppTheme.primarySoft,
                  foreground: AppTheme.navyBlue,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _SummaryCard(
                  title: 'Por caducar',
                  value: hasLotData
                      ? '$expiringIngredients'
                      : '—',
                  background: AppTheme.goldSoft,
                  foreground: AppTheme.goldDark,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _SummaryCard(
                  title: 'Agotados',
                  value: hasLotData
                      ? '$outOfStockIngredients'
                      : '—',
                  background: AppTheme.dangerSoft,
                  foreground: AppTheme.danger,
                ),
              ),
            ],
          ),


          const SizedBox(height: 24),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Mostrar datos simulados',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.navyBlue,
              ),
            ),
            subtitle: const Text(
              'Solo para probar la interfaz. '
                  'No se guardan en Supabase.',
            ),
            value: _demoMode,
            onChanged: (enabled) {
              setState(() {
                _demoMode = enabled;
              });
            },
          ),

          const SizedBox(height: 12),

          const Text(
            'Control de existencias',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.navyBlue,
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final draft = await showAddInventoryLotSheet(context);

                if (draft == null || !context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Lote de ${draft.ingredientName} validado. '
                          'Todavía no se guardó en Supabase.',
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              },
              child: const Text('Agregar lote'),
            ),
          ),


          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final draft = await showInventoryMovementsSheet(
                  context,
                  lots: displayedLots,
                  isDemo: _demoMode,
                );

                if (draft == null || !context.mounted) return;

                final movementName =
                draft.type == InventoryMovementKind.salida
                    ? 'Salida'
                    : 'Descarte';

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$movementName de '
                          '${formatInventoryQuantity(draft.quantity)} '
                          '${draft.unit} de ${draft.ingredientName} '
                          'validado. No se guardó ni se '
                          'descontaron existencias.',
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              },
              child: const Text('Movimientos de inventario'),
            ),
          ),

          const SizedBox(height: 12),


          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar ingrediente...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _search = value;
              });
            },
          ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            'Todos',
            'Almacén',
            'Refrigerador',
          ].map((location) {
            return ChoiceChip(
              label: Text(location),
              selected: _locationFilter == location,
              selectedColor: AppTheme.goldSoft,
              showCheckmark: false,
              labelStyle: const TextStyle(
                color: AppTheme.navyBlue,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _locationFilter = location;
                  });
                }
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 12),



          ...filteredIngredients.map((ingredient) {
            final ingredientLots = displayedLots.where((lot) {
              return lot.ingredientName == ingredient &&
                  (_locationFilter == 'Todos' ||
                      lot.location == _locationFilter);
            }).toList();

            final locations = ingredientLots
                .map((lot) => lot.location)
                .toSet()
                .join(' / ');

            // Muestra primero la caducidad del lote
            // que vence antes y todavía tiene existencias.
            final lotsWithStock = ingredientLots
                .where((lot) => lot.availableQuantity > 0)
                .toList()
              ..sort(
                    (a, b) =>
                    a.expirationDate.compareTo(b.expirationDate),
              );

            final nextLot =
            lotsWithStock.isEmpty ? null : lotsWithStock.first;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    ingredient,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.navyBlue,
                    ),
                  ),
                  subtitle: ingredientLots.isEmpty
                      ? const Text(
                    'Existencias pendientes de conectar',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  )
                      : Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        '${ingredientLots.length} lote(s) '
                            '· $locations\n'
                            'Existencia registrada: '
                            '${inventoryAvailableText(ingredientLots)}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (nextLot != null)
                        InventoryExpiryBadge(
                          expirationDate:
                          nextLot.expirationDate,
                        ),
                      if (nextLot == null)
                        const Text(
                          'Sin existencias',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: ingredientLots.isNotEmpty,
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.navyBlue,
                  ),
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (_) => InventoryLotDetailSheet(
                        ingredientName: ingredient,
                        lots: ingredientLots,
                      ),
                    );
                  },
                ),
              ),
            );
          }),


          if (filteredIngredients.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      _locationFilter == 'Todos'
                        ? 'No se encontraron ingredientes.'
                        : displayedLots.isEmpty
                          ? 'Todavía no hay lotes con ubicación '
                            'registrada. Los datos aparecerán '
                            'cuando conectemos el inventario.'
                          : 'No se encontraron ingredientes '
                            'en $_locationFilter.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color background;
  final Color foreground;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: foreground,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
