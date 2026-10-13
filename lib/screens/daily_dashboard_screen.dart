import 'package:flutter/material.dart';
import '../services/sales_service.dart';
import '../services/dashboard_service.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/sale_chart.dart';
import '../widgets/export_dialog.dart';


class DailyDashboardScreen extends StatefulWidget {
  const DailyDashboardScreen({super.key});

  @override
  State<DailyDashboardScreen> createState() => _DailyDashboardScreenState();
}

class _DailyDashboardScreenState extends State<DailyDashboardScreen> {
  final SalesService _salesService = SalesService();
  DashboardPeriod _selectedPeriod = DashboardPeriod.hoy;

  @override
  void initState() {
    super.initState();
    _salesService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _salesService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sales = _salesService.sales;
    final metrics = DashboardService.computeMetrics(sales, _selectedPeriod);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period Selector Tabs with Export
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    child: Row(
                      children: [
                        _buildPeriodTab('Hoy', DashboardPeriod.hoy),
                        _buildPeriodTab('Semana', DashboardPeriod.semana),
                        _buildPeriodTab('Mes', DashboardPeriod.mes),
                        _buildPeriodTab('Todo', DashboardPeriod.todo),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, color: AppTheme.primary),
                  tooltip: 'Exportar Ventas del Periodo',
                  onPressed: () {
                    final pSales = DashboardService.filterSales(sales, _selectedPeriod);
                    showDialog(
                      context: context,
                      builder: (ctx) => ExportDialog(
                        sales: pSales,
                        title: 'Periodo ${_selectedPeriod.name.toUpperCase()}',
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Top Hero Card: Total Vendido
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.navyBlue, AppTheme.navyBlueLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.navyBlue.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Vendido',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.gold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${metrics.totalTickets} Tickets',
                          style: const TextStyle(
                            color: AppTheme.navyBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\$${metrics.totalVendido.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHeroSubmetric('Ticket Promedio', '\$${metrics.ticketPromedio.toStringAsFixed(2)}'),
                      _buildHeroSubmetric('Ticket Más Alto', '\$${metrics.ventaMaxima.toStringAsFixed(2)}'),
                      _buildHeroSubmetric('Hamburguesas', '${metrics.totalHamburguesas} pzas'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Metrics Grid
            const Text(
              'Métricas Clave',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.navyBlue,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                MetricCard(
                  title: 'Venta Máxima',
                  value: '\$${metrics.ventaMaxima.toStringAsFixed(2)}',
                  subtitle: 'Ticket récord del periodo',
                  icon: Icons.emoji_events_rounded,
                  accentColor: AppTheme.gold,
                ),
                MetricCard(
                  title: 'Primera Venta',
                  value: '\$${metrics.primeraVenta.toStringAsFixed(2)}',
                  subtitle: 'Apertura de turno',
                  icon: Icons.wb_sunny_rounded,
                  accentColor: AppTheme.infoBlue,
                ),
                MetricCard(
                  title: 'Promedio / Ticket',
                  value: '\$${metrics.ticketPromedio.toStringAsFixed(2)}',
                  subtitle: 'Gasto medio por cliente',
                  icon: Icons.trending_up_rounded,
                  accentColor: AppTheme.successGreen,
                ),
                MetricCard(
                  title: 'Burgers / Venta',
                  value: metrics.promedioHamburguesasPorVenta.toStringAsFixed(1),
                  subtitle: 'Unidades promedio',
                  icon: Icons.lunch_dining_rounded,
                  accentColor: AppTheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Payment Methods Breakdown
            const Text(
              'Desglose por Método de Pago',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.navyBlue,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                children: [
                  _buildPaymentRow('Efectivo', metrics.totalEfectivo, metrics.totalVendido, AppTheme.successGreen, Icons.money_rounded),
                  const Divider(height: 20),
                  _buildPaymentRow('Tarjeta', metrics.totalTarjeta, metrics.totalVendido, AppTheme.infoBlue, Icons.credit_card_rounded),
                  const Divider(height: 20),
                  _buildPaymentRow('Transferencia', metrics.totalTransferencia, metrics.totalVendido, AppTheme.gold, Icons.account_balance_rounded),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sales Chart (fl_chart)
            SaleChart(hourlySales: metrics.hourlySales),
            const SizedBox(height: 20),

            // Top Products
            if (metrics.topProducts.isNotEmpty) ...[
              const Text(
                'Productos Más Vendidos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Column(
                  children: metrics.topProducts.entries.take(5).map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.primarySoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.lunch_dining, size: 16, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.navyBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${entry.value} vendidas',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppTheme.navyBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodTab(String title, DashboardPeriod period) {
    final isSelected = _selectedPeriod == period;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedPeriod = period),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textMuted,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSubmetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(String method, double amount, double total, Color color, IconData icon) {
    final pct = total > 0 ? (amount / total * 100).toStringAsFixed(0) : '0';
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            method,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$pct%',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}