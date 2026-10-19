import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';

class SaleChart extends StatelessWidget {
  final Map<int, double> hourlySales;

  const SaleChart({
    super.key,
    required this.hourlySales,
  });

  @override
  Widget build(BuildContext context) {
    if (hourlySales.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'No hay ventas registradas en este periodo',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    int minHour = hourlySales.keys.reduce((a, b) => a < b ? a : b);
    int maxHour = hourlySales.keys.reduce((a, b) => a > b ? a : b);
    if (maxHour - minHour < 4) {
      minHour = (minHour - 1).clamp(0, 23);
      maxHour = (maxHour + 2).clamp(0, 23);
    }

    double maxVal = hourlySales.values.reduce((a, b) => a > b ? a : b);
    if (maxVal <= 0) maxVal = 100.0;

    List<BarChartGroupData> barGroups = [];
    for (int h = minHour; h <= maxHour; h++) {
      final amount = hourlySales[h] ?? 0.0;
      barGroups.add(
        BarChartGroupData(
          x: h,
          barRods: [
            BarChartRodData(
              toY: amount,
              color: amount > 0 ? AppTheme.primary : Colors.grey.shade300,
              width: 14,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              gradient: amount > 0
                  ? const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.gold],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    )
                  : null,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ventas por hora (\$)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navyBlue,
                ),
              ),
              Icon(Icons.show_chart_rounded, color: AppTheme.primary, size: 20),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxVal * 1.25,
                barGroups: barGroups,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppTheme.borderLight,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (val, meta) {
                        if (val == 0) return const SizedBox.shrink();
                        return Text(
                          '\$${val.toInt()}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (val, meta) {
                        int h = val.toInt();
                        String label = '$h:00';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.navyBlue,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}