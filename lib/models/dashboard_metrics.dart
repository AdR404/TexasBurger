class DashboardMetrics {
  final double totalVendido;
  final double totalRegular;
  final double totalFinal;
  final int totalTickets;
  final double ticketPromedio;
  final double ventaMaxima;
  final double primeraVenta;
  final int totalHamburguesas;
  final double promedioHamburguesasPorVenta;
  final double totalEfectivo;
  final double totalTarjeta;
  final double totalTransferencia;
  final Map<int, double> hourlySales;
  final Map<String, int> topProducts;

  DashboardMetrics({
    this.totalVendido = 0.0,
    this.totalRegular = 0.0,
    this.totalFinal = 0.0,
    this.totalTickets = 0,
    this.ticketPromedio = 0.0,
    this.ventaMaxima = 0.0,
    this.primeraVenta = 0.0,
    this.totalHamburguesas = 0,
    this.promedioHamburguesasPorVenta = 0.0,
    this.totalEfectivo = 0.0,
    this.totalTarjeta = 0.0,
    this.totalTransferencia = 0.0,
    this.hourlySales = const {},
    this.topProducts = const {},
  });

  static DashboardMetrics empty() => DashboardMetrics();
}