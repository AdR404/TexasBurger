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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
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
    if (mounted) setState(() {});
  }

  final List<Widget> _screens = const [
    QuickSaleScreen(),
    DailyDashboardScreen(),
    HistoryScreen(),
    CajaScreen(),
    SettingsScreen(),
  ];

  List<String> get _subtitles => [
    'Punto de Venta / Venta Rápida',
    'Métricas Diarias y Rendimiento',
    'Historial de Tickets y Órdenes',
    'Arqueo de Turno y Control de Efectivo',
    _roleService.isAdmin
        ? 'Configuración y Administración del Menú'
        : 'Catálogo del Menú (Modo Consulta)',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TexasHeader(
            subtitle: _subtitles[_currentIndex],
            trailing: const RoleSwitchButton(),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
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
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined),
              selectedIcon: Icon(Icons.point_of_sale, color: AppTheme.primary),
              label: 'Venta',
            ),
            /*const NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics, color: AppTheme.primary),
              label: 'Dashboard',
            ),*/
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long, color: AppTheme.primary),
              label: 'Historial',
            ),
            const NavigationDestination(
              icon: Icon(Icons.savings_outlined),
              selectedIcon: Icon(Icons.savings, color: AppTheme.primary),
              label: 'Caja',
            ),
            NavigationDestination(
              icon: Icon(
                _roleService.isAdmin ? Icons.menu_book_outlined : Icons.menu_book,
              ),
              selectedIcon: const Icon(Icons.menu_book, color: AppTheme.primary),
              label: _roleService.isAdmin ? 'Menú' : 'Catálogo',
            ),
          ],
        ),
      ),
    );
  }
}