import 'producto.dart';
import 'producto_extra.dart';

class VentaItem {
  final Producto product;
  int quantity;
  final double unitPrice;
  final List<ProductoExtra> selectedExtras;
  final List<String> removedIngredients;
  final String notes;

  VentaItem({
    required this.product,
    this.quantity = 1,
    required this.unitPrice,
    this.selectedExtras = const [],
    this.removedIngredients = const [],
    this.notes = '',
  });

  double get subtotal => unitPrice * quantity;

  double get extrasTotal =>
      selectedExtras.fold(0.0, (sum, extra) => sum + extra.price);

  String get customizationSummary {
    final parts = <String>[];
    if (selectedExtras.isNotEmpty) {
      parts.add('Con: ${selectedExtras.map((e) => '+${e.name}').join(', ')}');
    }
    if (removedIngredients.isNotEmpty) {
      parts.add(removedIngredients.join(', '));
    }
    if (notes.isNotEmpty) {
      parts.add('Nota: $notes');
    }
    return parts.join(' | ');
  }

  Map<String, dynamic> toJson() => {
    'product': product.toJson(),
    'quantity': quantity,
    'unitPrice': unitPrice,
    'selectedExtras': selectedExtras.map((e) => e.toJson()).toList(),
    'removedIngredients': removedIngredients,
    'notes': notes,
  };

  factory VentaItem.fromJson(Map<String, dynamic> json) => VentaItem(
    product: Producto.fromJson(json['product'] as Map<String, dynamic>),
    quantity: json['quantity'] as int? ?? 1,
    unitPrice: (json['unitPrice'] as num).toDouble(),
    selectedExtras: (json['selectedExtras'] as List<dynamic>?)
            ?.map((e) => ProductoExtra.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    removedIngredients: (json['removedIngredients'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    notes: json['notes'] as String? ?? '',
  );
}