
import 'package:flutter/material.dart';

import '../services/user_role_service.dart';
import '../theme/app_theme.dart';
import '../data/ingredient_catalog.dart';

class InventoryScreen extends StatelessWidget {
  final VoidCallback onBack;

  const InventoryScreen({
    super.key,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    // Segunda comprobación del permiso de administrador.
    if (!UserRoleService().isAdmin) {
      return const Center(
        child: Text('Acceso exclusivo para administradores.'),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.creamBg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onBack,
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

          const Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Total de insumos',
                  value: '—',
                  background: AppTheme.primarySoft,
                  foreground: AppTheme.navyBlue,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  title: 'Por caducar',
                  value: '—',
                  background: AppTheme.goldSoft,
                  foreground: AppTheme.goldDark,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  title: 'Agotados',
                  value: '—',
                  background: AppTheme.dangerSoft,
                  foreground: AppTheme.danger,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          const Text(
            'Control de existencias',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.navyBlue,
            ),
          ),

          const SizedBox(height: 12),

          ...IngredientCatalog.defaultIngredients.map(
                (ingredient) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    title: Text(
                      ingredient,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.navyBlue,
                      ),
                    ),
                    subtitle: const Text(
                      'Existencias pendientes de conectar',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
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
