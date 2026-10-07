import 'producto_extra.dart';

class Producto {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final bool isPromo;
  final String? promoNote;
  final bool isAvailable;
  final List<ProductoExtra> availableExtras;

  Producto({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    this.isPromo = false,
    this.promoNote,
    this.isAvailable = true,
    this.availableExtras = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'category': category,
    'isPromo': isPromo,
    'promoNote': promoNote,
    'isAvailable': isAvailable,
    'availableExtras': availableExtras.map((e) => e.toJson()).toList(),
  };

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    price: (json['price'] as num).toDouble(),
    category: json['category'] as String? ?? 'Hamburguesas',
    isPromo: json['isPromo'] as bool? ?? false,
    promoNote: json['promoNote'] as String?,
    isAvailable: json['isAvailable'] as bool? ?? true,
    availableExtras: (json['availableExtras'] as List<dynamic>?)
            ?.map((e) => ProductoExtra.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );

  Producto copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? category,
    bool? isPromo,
    String? promoNote,
    bool? isAvailable,
    List<ProductoExtra>? availableExtras,
  }) => Producto(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    price: price ?? this.price,
    category: category ?? this.category,
    isPromo: isPromo ?? this.isPromo,
    promoNote: promoNote ?? this.promoNote,
    isAvailable: isAvailable ?? this.isAvailable,
    availableExtras: availableExtras ?? this.availableExtras,
  );
}