class ProductoExtra {
  final String id;
  final String name;
  final double price;

  const ProductoExtra({
    required this.id,
    required this.name,
    required this.price,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
  };

  factory ProductoExtra.fromJson(Map<String, dynamic> json) => ProductoExtra(
    id: json['id'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductoExtra && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
