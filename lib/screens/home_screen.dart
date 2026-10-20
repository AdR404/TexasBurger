import 'package:flutter/material.dart';
import '../widgets/texas_header.dart';
import '../widgets/role_switch_button.dart';
import '../services/user_role_service.dart';
import '../theme/app_theme.dart';
import 'quick_sale_screen.dart';
import 'daily_dashboard_screen.dart';
import 'history_screen.dart';
import 'caja_screen.dart';
import 'settings_screen.dart';

enum _Section { sale, dashboard, history, caja, catalog }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Section _selected = _Section.sale;

  List<_Section> get _destinations => _roleService.isAdmin
      ? _Section.values
      : [_Section.sale, _Section.catalog, _Section.history];
  final UserRoleService _roleService = UserRoleService();

  @override
  void initState() {
    super.initState();
    _roleService.addListener(_onRoleChanged);
  }

  @override
  void dispose() {
    _roleService.removeListener(_onRoleChanged);
    super.dispose();
  }

  void _onRoleChanged() {
    if (mounted) {
      setState(() {
        if (!_destinations.contains(_selected)) _selected = _Section.sale;
      });
    }
  }

  // Fixed slots retain the sale/cart and catalog state when nav order changes.
  // Restricted screens are unmounted as soon as the role changes.
  List<Widget> get _screens => [
    const QuickSaleScreen(),
    _roleService.isAdmin
        ? const DailyDashboardScreen()
        : const SizedBox.shrink(),
    const HistoryScreen(),
    _roleService.isAdmin ? const CajaScreen() : const SizedBox.shrink(),
    const SettingsScreen(),
  ];

  List<String> get _subtitles => [
    'Punto de venta / venta rápida',
    'Métricas diarias y rendimiento',
    'Historial de tickets y órdenes',
    'Arqueo de turno y control de efectivo',
    _roleService.isAdmin
        ? 'Configuración y administración del menú'
        : 'Catálogo del menú (modo consulta)',
  ];

  NavigationDestination _navigationDestination(_Section section) {
    final (label, icon, selectedIcon) = switch (section) {
      _Section.sale => (
        'Venta',
        Icons.point_of_sale_outlined,
        Icons.point_of_sale,
      ),
      _Section.dashboard => (
        'Dashboard',
        Icons.analytics_outlined,
        Icons.analytics,
      ),
      _Section.history => (
        'Historial',
        Icons.receipt_long_outlined,
        Icons.receipt_long,
      ),
      _Section.caja => ('Caja', Icons.savings_outlined, Icons.savings),
      _Section.catalog => (
        _roleService.isAdmin ? 'Menú' : 'Catálogo',
        Icons.menu_book_outlined,
        Icons.menu_book,
      ),
    };
    return NavigationDestination(
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon, color: AppTheme.primary),
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    return Scaffold(
      body: Column(
        children: [
          TexasHeader(
            subtitle: _subtitles[_selected.index],
            trailing: const RoleSwitchButton(),
          ),
          Expanded(
            child: IndexedStack(index: _selected.index, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: destinations.indexOf(_selected),
          onDestinationSelected: (index) => setState(() {
            final destination = destinations[index];
            _selected = _destinations.contains(destination)
                ? destination
                : _Section.sale;
          }),
          destinations: destinations.map(_navigationDestination).toList(),
        ),
      ),
    );
  }
}
