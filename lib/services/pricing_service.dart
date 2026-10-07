import '../models/venta_item.dart';

class PricingCalculation {
  final double subtotal;
  final double discount;
  final double total;
  final String? discountReason;

  PricingCalculation({
    required this.subtotal,
    required this.discount,
    required this.total,
    this.discountReason,
  });
}

class PricingService {
  static PricingCalculation calculate({
    required List<VentaItem> items,
    bool forceMartesPromo = false,
  }) {
    double subtotal = 0.0;
    for (var item in items) {
      subtotal += item.subtotal;
    }

    double discount = 0.0;
    String? reason;

    // Check Tuesday promo condition: 2 classic Texas burgers for 150 MXN (regular is 96*2 = 192, savings of 42 MXN)
    final now = DateTime.now();
    final isTuesday = (now.weekday == DateTime.tuesday) || forceMartesPromo;

    if (isTuesday) {
      // Check if classic burgers are present
      final classicItems = items.where((i) => i.product.id == 'hamb_texana_clasica').toList();
      if (classicItems.isNotEmpty) {
        int classicCount = classicItems.fold(0, (sum, i) => sum + i.quantity);
        int promoPairs = classicCount ~/ 2;
        if (promoPairs > 0) {
          // Normal price for 2 is 96 * 2 = 192. Promo price is 150. Discount is 42 per pair.
          discount += promoPairs * 42.0;
          reason = 'Promo Martes 2x aplicada ()';
        }
      }
    }

    double total = (subtotal - discount).clamp(0.0, double.infinity);

    return PricingCalculation(
      subtotal: subtotal,
      discount: discount,
      total: total,
      discountReason: reason,
    );
  }
}