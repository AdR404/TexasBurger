import 'package:flutter/material.dart';

import '../services/user_role_service.dart';
import '../services/inventory_repository.dart';
import '../services/db_service.dart';
import '../services/caja_service.dart';
import '../services/operator_session.dart';
import '../widgets/staff_context_selector.dart';
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
  final InventoryRepository? repository;

  const InventoryScreen({
    super.key,
    required this.onBack,
    this.lots = const [],
    this.repository,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _search = '';
  String _locationFilter = 'Todos';
  bool _demoMode = false;
  late final InventoryRepository _repository;
  OperatorSession? _session;
  String? _actor;
  String? _branch;
  InventoryData? _data;
  String? _error;
  bool _loading = false;
  bool _working = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? InventoryRepository();
    _branch = CajaService().saleContext?.branchId;
    _session = DbService.session;
    _actor = _repository.operatorId;
    _session?.addListener(_sessionChanged);
    CajaService().addListener(_branchChanged);
    _load();
  }

  @override
  void dispose() {
    _session?.removeListener(_sessionChanged);
    CajaService().removeListener(_branchChanged);
    _revision++;
    super.dispose();
  }

  void _branchChanged() {
    final branch = CajaService().saleContext?.branchId;
    if (_branch == branch) return;
    _branch = branch;
    if (!_demoMode) _load();
  }

  void _sessionChanged() {
    if (_actor == _repository.operatorId) return;
    _actor = _repository.operatorId;
    if (!_demoMode) _load();
  }

  Future<bool> _load() async {
    final revision = ++_revision;
    final branch = _branch;
    setState(() {
      _data = null;
      _error = null;
      _loading = false;
    });
    if (_demoMode) return false;
    if (_repository.operatorId == null) {
      setState(
        () => _error =
            'Inicia sesión remota con una cuenta autorizada para inventario.',
      );
      return false;
    }
    if (branch == null) {
      setState(
        () => _error = 'Selecciona una sucursal para consultar inventario.',
      );
      return false;
    }
    setState(() => _loading = true);
    try {
      final data = await _repository.load(branch);
      if (!mounted || revision != _revision) return false;
      setState(() => _data = data);
      return true;
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _error = e.toString());
      }
      return false;
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
    );
  }

  Future<void> _addLot() async {
    if (_working || _loading || !UserRoleService().isAdmin) return;
    final demo = _demoMode;
    final actor = _repository.operatorId;
    final branch = _branch;
    final ingredients = _data?.ingredients;
    if (!demo && (ingredients == null || branch == null || actor == null)) {
      return;
    }
    setState(() => _working = true);
    try {
      final draft = await showAddInventoryLotSheet(
        context,
        ingredients: demo ? null : ingredients,
      );
      if (draft == null || !mounted) return;
      if (demo) {
        _message('Lote validado en demostración. No se guardó en Supabase.');
        return;
      }
      if (!UserRoleService().isAdmin ||
          actor != _repository.operatorId ||
          branch != _branch) {
        throw const InventoryException(
          'Cambió el acceso o la sucursal. Abre el formulario de nuevo.',
        );
      }
      final ingredient = ingredients!.firstWhere(
        (i) => i.id == draft.ingredientId,
      );
      final id = await _repository.registerLot(
        ingredient: ingredient,
        branch: branch!,
        location: draft.location,
        quantity: draft.quantity,
        cost: draft.unitCost,
        entry: draft.entryDate,
        expiration: draft.expirationDate,
        estimated: draft.estimatedExpiration,
      );
      if (!mounted) return;
      final loaded = await _load();
      _message(
        loaded
            ? 'Lote #$id registrado. Inventario actualizado.'
            : 'Lote #$id registrado, pero no se pudo actualizar la consulta. No repitas el alta; pulsa Actualizar.',
      );
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _movements() async {
    if (_working || _loading || !UserRoleService().isAdmin) return;
    final demo = _demoMode;
    final actor = _repository.operatorId;
    final branch = _branch;
    if (!demo && (_data == null || actor == null)) return;
    setState(() => _working = true);
    try {
      final draft = await showInventoryMovementsSheet(
        context,
        lots: demo ? InventoryDemoData.create() : _data!.lots,
        isDemo: demo,
        history: demo ? const [] : _data!.movements,
      );
      if (draft == null || !mounted) return;
      if (demo) {
        _message(
          'Movimiento validado en demostración. No se descontaron existencias.',
        );
        return;
      }
      if (!UserRoleService().isAdmin ||
          actor != _repository.operatorId ||
          branch != _branch) {
        throw const InventoryException(
          'Cambió el acceso o la sucursal. Abre el formulario de nuevo.',
        );
      }
      final id = await _repository.registerDecrease(
        lotId: draft.lotId,
        type: draft.type.name,
        quantity: draft.quantity,
        reason: draft.reason,
        isDemo: draft.isDemo,
      );
      if (!mounted) return;
      final loaded = await _load();
      _message(
        loaded
            ? 'Movimiento #$id registrado. Inventario actualizado.'
            : 'Movimiento #$id registrado, pero no se pudo actualizar la consulta. No lo repitas; pulsa Actualizar.',
      );
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Segunda comprobación del permiso de administrador.
    if (!UserRoleService().isAdmin) {
      return const Center(
        child: Text('Acceso exclusivo para administradores.'),
      );
    }

    final search = _search.trim().toLowerCase();

    final displayedLots = _demoMode
      ? InventoryDemoData.create()
      : (_data?.lots ?? const <InventoryLot>[]);
    final ingredientNames = _demoMode
      ? IngredientCatalog.defaultIngredients
      : (_data?.ingredients.map((i) => i.name).toList() ?? <String>[]);

    final totalIngredients = ingredientNames.length;

    // Ingredientes que tienen algún lote disponible
    // que caduca entre hoy y los próximos 30 días.
    final expiringIngredients = displayedLots
        .where((lot) {
          final days = inventoryDaysToExpire(lot.expirationDate);

          return lot.availableQuantity > 0 && days >= 0 && days <= 30;
        })
        .map((lot) => lot.ingredientName)
        .toSet()
        .length;

    // Ingredientes que tienen lotes registrados.
    final ingredientsWithLots = displayedLots
        .map((lot) => lot.ingredientName)
        .toSet();

    // Ingredientes cuyos lotes están todos agotados.
    final outOfStockIngredients = ingredientsWithLots.where((ingredient) {
      final ingredientLots = displayedLots.where(
        (lot) => lot.ingredientName == ingredient,
      );

      return ingredientLots.every((lot) => lot.availableQuantity <= 0);
    }).length;

    // Si no hay lotes cargados, no mostramos
    // cantidades de alerta como si fueran reales.
    final hasLotData = displayedLots.isNotEmpty;

    final filteredIngredients = ingredientNames.where((ingredient) {
      // Primero aplicamos el buscador.
      final matchesSearch = ingredient.toLowerCase().contains(search);

      if (!matchesSearch) return false;

      // Todos muestra el catálogo completo.
      if (_locationFilter == 'Todos') {
        return true;
      }

      // Las demás opciones requieren lotes con ubicación.
      return displayedLots.any(
        (lot) =>
            lot.ingredientName == ingredient && lot.location == _locationFilter,
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
              border: Border.all(color: AppTheme.gold, width: 1.5),
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
                  'Consulta y administra insumos, lotes y fechas de caducidad con una cuenta autorizada.',
                  style: TextStyle(color: AppTheme.navyBlue),
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
                  value: hasLotData ? '$expiringIngredients' : '—',
                  background: AppTheme.goldSoft,
                  foreground: AppTheme.goldDark,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _SummaryCard(
                  title: 'Agotados',
                  value: hasLotData ? '$outOfStockIngredients' : '—',
                  background: AppTheme.dangerSoft,
                  foreground: AppTheme.danger,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (!_demoMode) ...[
            StaffContextBar(enabled: !_working && !_loading),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            TextButton(
              onPressed: _working || _loading ? null : _load,
              child: const Text('Actualizar inventario'),
            ),
            if (_data != null && _data!.lots.isEmpty)
              const Text('No hay lotes registrados en esta sucursal.'),
          ],
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
            onChanged: _working
                ? null
                : (enabled) {
                    setState(() {
                      _demoMode = enabled;
                      _revision++;
                      _loading = false;
                      _data = null;
                    });
                    if (!enabled) _load();
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
                  onPressed: _working || _loading || _data == null
                    ? null
                    : _addLot,
              child: const Text('Agregar lote'),
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
                onPressed: _working || _loading || _data == null
                  ? null
                  : _movements,
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
            children: ['Todos', 'Almacén', 'Refrigerador'].map((location) {
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
            final lotsWithStock =
                ingredientLots
                    .where((lot) => lot.availableQuantity > 0)
                    .toList()
                  ..sort(
                    (a, b) => a.expirationDate.compareTo(b.expirationDate),
                  );

            final nextLot = lotsWithStock.isEmpty ? null : lotsWithStock.first;

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
                          'Sin lotes registrados',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                expirationDate: nextLot.expirationDate,
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
                            'al registrar un lote en esta sucursal.'
                      : 'No se encontraron ingredientes '
                            'en $_locationFilter.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textMuted),
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
