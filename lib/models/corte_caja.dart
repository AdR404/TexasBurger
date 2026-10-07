class CajaMovimiento {
  final String id;
  final String type; // 'entrada', 'salida'
  final double amount;
  final String concept;
  final DateTime timestamp;

  CajaMovimiento({
    required this.id,
    required this.type,
    required this.amount,
    required this.concept,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'amount': amount,
    'concept': concept,
    'timestamp': timestamp.toIso8601String(),
  };

  factory CajaMovimiento.fromJson(Map<String, dynamic> json) => CajaMovimiento(
    id: json['id'] as String,
    type: json['type'] as String,
    amount: (json['amount'] as num).toDouble(),
    concept: json['concept'] as String? ?? '',
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

class CorteCaja {
  final String id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double initialCash;
  final double cashIn;
  final double cashOut;
  final double cashSales;
  final double cardSales;
  final double transferSales;
  final double totalSales;
  final int ordersCount;
  final double expectedCash;
  final double? actualCashCounted;
  final double? difference;
  final String notes;
  final bool isClosed;
  final List<CajaMovimiento> movimientos;

  CorteCaja({
    required this.id,
    required this.openedAt,
    this.closedAt,
    required this.initialCash,
    this.cashIn = 0.0,
    this.cashOut = 0.0,
    this.cashSales = 0.0,
    this.cardSales = 0.0,
    this.transferSales = 0.0,
    this.totalSales = 0.0,
    this.ordersCount = 0,
    required this.expectedCash,
    this.actualCashCounted,
    this.difference,
    this.notes = '',
    this.isClosed = false,
    this.movimientos = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'openedAt': openedAt.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
    'initialCash': initialCash,
    'cashIn': cashIn,
    'cashOut': cashOut,
    'cashSales': cashSales,
    'cardSales': cardSales,
    'transferSales': transferSales,
    'totalSales': totalSales,
    'ordersCount': ordersCount,
    'expectedCash': expectedCash,
    'actualCashCounted': actualCashCounted,
    'difference': difference,
    'notes': notes,
    'isClosed': isClosed,
    'movimientos': movimientos.map((m) => m.toJson()).toList(),
  };

  factory CorteCaja.fromJson(Map<String, dynamic> json) => CorteCaja(
    id: json['id'] as String,
    openedAt: DateTime.parse(json['openedAt'] as String),
    closedAt: json['closedAt'] != null ? DateTime.parse(json['closedAt'] as String) : null,
    initialCash: (json['initialCash'] as num).toDouble(),
    cashIn: (json['cashIn'] as num?)?.toDouble() ?? 0.0,
    cashOut: (json['cashOut'] as num?)?.toDouble() ?? 0.0,
    cashSales: (json['cashSales'] as num?)?.toDouble() ?? 0.0,
    cardSales: (json['cardSales'] as num?)?.toDouble() ?? 0.0,
    transferSales: (json['transferSales'] as num?)?.toDouble() ?? 0.0,
    totalSales: (json['totalSales'] as num?)?.toDouble() ?? 0.0,
    ordersCount: json['ordersCount'] as int? ?? 0,
    expectedCash: (json['expectedCash'] as num).toDouble(),
    actualCashCounted: (json['actualCashCounted'] as num?)?.toDouble(),
    difference: (json['difference'] as num?)?.toDouble(),
    notes: json['notes'] as String? ?? '',
    isClosed: json['isClosed'] as bool? ?? false,
    movimientos: (json['movimientos'] as List<dynamic>?)
            ?.map((m) => CajaMovimiento.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
