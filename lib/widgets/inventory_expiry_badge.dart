
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum InventoryExpiryStatus {
  expired,
  today,
  urgent,
  approaching,
  valid,
}

// Calcula días calendario, sin problemas
// por cambios de horario.
int inventoryDaysToExpire(
    DateTime expiration, {
      DateTime? today,
    }) {
  final reference = today ?? DateTime.now();

  final first = DateTime.utc(
    reference.year,
    reference.month,
    reference.day,
  );

  final second = DateTime.utc(
    expiration.year,
    expiration.month,
    expiration.day,
  );

  return second.difference(first).inDays;
}

InventoryExpiryStatus inventoryExpiryStatus(
    DateTime expiration, {
      DateTime? today,
    }) {
  final days = inventoryDaysToExpire(
    expiration,
    today: today,
  );

  if (days < 0) return InventoryExpiryStatus.expired;
  if (days == 0) return InventoryExpiryStatus.today;
  if (days <= 15) return InventoryExpiryStatus.urgent;
  if (days <= 30) return InventoryExpiryStatus.approaching;

  return InventoryExpiryStatus.valid;
}

class InventoryExpiryBadge extends StatelessWidget {
  final DateTime expirationDate;

  const InventoryExpiryBadge({
    super.key,
    required this.expirationDate,
  });

  @override
  Widget build(BuildContext context) {
    final days = inventoryDaysToExpire(expirationDate);

    late final String label;
    late final Color textColor;
    late final Color backgroundColor;

    if (days < 0) {
      label = 'Caducado hace ${-days} día(s)';
      textColor = AppTheme.danger;
      backgroundColor = AppTheme.dangerSoft;
    } else if (days == 0) {
      label = 'Caduca hoy';
      textColor = AppTheme.danger;
      backgroundColor = AppTheme.dangerSoft;
    } else if (days <= 15) {
      label = 'Caduca en $days día(s)';
      textColor = Colors.deepOrange.shade700;
      backgroundColor = AppTheme.goldSoft;
    } else if (days <= 30) {
      label = 'Por vencer: $days días';
      textColor = AppTheme.goldDark;
      backgroundColor = AppTheme.goldSoft;
    } else {
      label = 'Vigente: $days días';
      textColor = AppTheme.navyBlue;
      backgroundColor = AppTheme.primarySoft;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
