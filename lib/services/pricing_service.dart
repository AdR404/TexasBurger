import '../models/discount_code.dart';
import '../models/venta_item.dart';

class PricingCalculation {
  final double subtotal;
  final double discount;
  final double taxableSubtotal;
  final double iva;
  final double ivaRate;
  final double total;
  final String? discountReason;
  final String? discountCode;

  const PricingCalculation({
    required this.subtotal,
    required this.discount,
    required this.taxableSubtotal,
    required this.iva,
    required this.ivaRate,
    required this.total,
    this.discountReason,
    this.discountCode,
  });
}

class PricingService {
  // Business rule confirmed: catalog prices include IVA. Never add it again.
  static const defaultIvaRate = 0.16;

  static PricingCalculation calculate({
    required List<VentaItem> items,
    bool forceMartesPromo = false,
    DiscountCode? coupon,
    double ivaRate = defaultIvaRate,
  }) {
    if (!ivaRate.isFinite || ivaRate < 0 || ivaRate > 1) {
      throw ArgumentError.value(ivaRate, 'ivaRate');
    }
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.subtotal);
    var discount = 0.0;
    final reasons = <String>[];
    if (DateTime.now().weekday == DateTime.tuesday || forceMartesPromo) {
      final classicCount = items
          .where((item) => item.product.id == 'hamb_texana_clasica')
          .fold<int>(0, (sum, item) => sum + item.quantity);
      if (classicCount >= 2) {
        discount = (classicCount ~/ 2) * 42.0;
        reasons.add('Promo Martes 2x');
      }
    }
    discount = discount.clamp(0.0, subtotal).toDouble();
    final activeCoupon = coupon != null && coupon.isActive && coupon.isValid
        ? coupon
        : null;
    if (activeCoupon != null) {
      final eligible = (subtotal - discount).clamp(0.0, subtotal).toDouble();
      discount += _roundCurrency(
        activeCoupon.discountFor(eligible),
      ).clamp(0.0, eligible);
      reasons.add(
        '${activeCoupon.description.isEmpty ? 'Cupón' : activeCoupon.description} (${activeCoupon.code})',
      );
    }
    // Preserve the existing charged amount; only the new coupon reduces it.
    final total = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
    final taxableSubtotal = _roundCurrency(total / (1 + ivaRate));
    final iva = _roundCurrency(total - taxableSubtotal);
    return PricingCalculation(
      subtotal: subtotal,
      discount: discount,
      taxableSubtotal: taxableSubtotal,
      iva: iva,
      ivaRate: ivaRate,
      total: total,
      discountReason: reasons.isEmpty ? null : reasons.join(' + '),
      discountCode: activeCoupon?.code,
    );
  }

  static double _roundCurrency(double value) => (value * 100).round() / 100;
}
