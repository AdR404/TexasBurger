import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PromoBadge extends StatelessWidget {
  final String text;
  final bool isSpecial;

  const PromoBadge({
    super.key,
    required this.text,
    this.isSpecial = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSpecial ? AppTheme.gold : AppTheme.promo,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: (isSpecial ? AppTheme.gold : AppTheme.promo).withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSpecial ? Icons.star_rounded : Icons.local_fire_department,
            color: isSpecial ? AppTheme.navyBlue : Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSpecial ? AppTheme.navyBlue : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
