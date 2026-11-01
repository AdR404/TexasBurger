
class InventoryLot {
  final int id;
  final int ingredientId;
  final String ingredientName;
  final String location;
  final String unit;

  final double initialQuantity;
  final double availableQuantity;
  final double unitCost;

  final DateTime entryDate;
  final DateTime expirationDate;
  final bool estimatedExpiration;

  const InventoryLot({
    required this.id,
    required this.ingredientId,
    required this.ingredientName,
    required this.location,
    required this.unit,
    required this.initialQuantity,
    required this.availableQuantity,
    required this.unitCost,
    required this.entryDate,
    required this.expirationDate,
    required this.estimatedExpiration,
  });
}

String formatInventoryQuantity(double quantity) {
  return quantity
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'\.?0+$'), '');
}

String inventoryAvailableText(
    Iterable<InventoryLot> lots,
    ) {
  final totals = <String, double>{};

  for (final lot in lots) {
    totals.update(
      lot.unit,
          (previous) => previous + lot.availableQuantity,
      ifAbsent: () => lot.availableQuantity,
    );
  }

  if (totals.isEmpty) return 'Sin datos';

  return totals.entries.map((entry) {
    return '${formatInventoryQuantity(entry.value)} ${entry.key}';
  }).join(' + ');
}
