import '../models/venta.dart';
import '../models/dashboard_metrics.dart';

enum DashboardPeriod { hoy, semana, mes, todo }

class DashboardService {
  static List<Venta> filterSales(List<Venta> allSales, DashboardPeriod period) {
    final now = DateTime.now();
    return allSales.where((v) {
      switch (period) {
        case DashboardPeriod.hoy:
          return v.timestamp.year == now.year &&
              v.timestamp.month == now.month &&
              v.timestamp.day == now.day;
        case DashboardPeriod.semana:
          final diff = now.difference(v.timestamp).inDays;
          return diff <= 7;
        case DashboardPeriod.mes:
          return v.timestamp.year == now.year && v.timestamp.month == now.month;
        case DashboardPeriod.todo:
          return true;
      }
    }).toList();
  }

  static DashboardMetrics computeMetrics(List<Venta> allSales, DashboardPeriod period) {
    if (allSales.isEmpty) return DashboardMetrics.empty();

    final filtered = filterSales(allSales, period);
    if (filtered.isEmpty) return DashboardMetrics.empty();

    double totalVendido = 0.0;
    double totalRegular = 0.0;
    double ventaMaxima = 0.0;
    double primeraVenta = 0.0;
    int totalHamburguesas = 0;
    double totalEfectivo = 0.0;
    double totalTarjeta = 0.0;
    double totalTransferencia = 0.0;
    Map<int, double> hourlySales = {};
    Map<String, int> topProducts = {};

    // Sort ascending for primera venta
    final chronological = List<Venta>.from(filtered)..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    primeraVenta = chronological.first.total;

    for (var v in filtered) {
      totalVendido += v.total;
      totalRegular += v.subtotal;
      if (v.total > ventaMaxima) {
        ventaMaxima = v.total;
      }

      // Payment method breakdown
      if (v.paymentMethod.toLowerCase().contains('efectivo')) {
        totalEfectivo += v.total;
      } else if (v.paymentMethod.toLowerCase().contains('tarjeta')) {
        totalTarjeta += v.total;
      } else if (v.paymentMethod.toLowerCase().contains('transf')) {
        totalTransferencia += v.total;
      }

      // Hourly grouping
      int hour = v.timestamp.hour;
      hourlySales[hour] = (hourlySales[hour] ?? 0.0) + v.total;

      // Products counting
      for (var item in v.items) {
        totalHamburguesas += item.quantity;
        topProducts[item.product.name] = (topProducts[item.product.name] ?? 0) + item.quantity;
      }
    }

    int totalTickets = filtered.length;
    double ticketPromedio = totalTickets > 0 ? (totalVendido / totalTickets) : 0.0;
    double promedioHamburguesasPorVenta = totalTickets > 0 ? (totalHamburguesas / totalTickets) : 0.0;

    return DashboardMetrics(
      totalVendido: totalVendido,
      totalRegular: totalRegular,
      totalFinal: totalVendido,
      totalTickets: totalTickets,
      ticketPromedio: ticketPromedio,
      ventaMaxima: ventaMaxima,
      primeraVenta: primeraVenta,
      totalHamburguesas: totalHamburguesas,
      promedioHamburguesasPorVenta: promedioHamburguesasPorVenta,
      totalEfectivo: totalEfectivo,
      totalTarjeta: totalTarjeta,
      totalTransferencia: totalTransferencia,
      hourlySales: hourlySales,
      topProducts: topProducts,
    );
  }
}