import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../theme/app_theme.dart';

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({super.key, required this.product, this.size = 64});

  final Producto product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = product.isPromo
        ? Icons.star_rate_rounded
        : switch (product.category) {
            'Hamburguesas' => Icons.lunch_dining_rounded,
            'Complementos' => Icons.fastfood_rounded,
            'Bebidas' => Icons.local_drink_rounded,
            'Promociones' => Icons.local_offer_rounded,
            _ => Icons.restaurant_menu,
          };
    final fallback = Icon(
      icon,
      color: product.isPromo ? AppTheme.promo : AppTheme.navyBlue,
      size: size < 64 ? 20 : 26,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.infoSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: product.imagePath == null
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                product.imagePath!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
            ),
    );
  }
}
