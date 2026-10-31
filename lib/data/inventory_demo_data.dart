
import '../models/inventory_lot.dart';

class InventoryDemoData {
  static List<InventoryLot> create() {
    final now = DateTime.now();

    DateTime date(int offset) {
      return DateTime(
        now.year,
        now.month,
        now.day + offset,
      );
    }

    InventoryLot example({
      required int id,
      required String ingredient,
      required String location,
      required String unit,
      required double remaining,
      required double cost,
      required int expiresIn,
      double? received,
      bool estimated = false,
    }) {
      return InventoryLot(
        id: -id,
        ingredientId: -id,
        ingredientName: ingredient,
        location: location,
        unit: unit,
        initialQuantity: received ?? remaining,
        availableQuantity: remaining,
        unitCost: cost,
        entryDate: date(-10),
        expirationDate: date(expiresIn),
        estimatedExpiration: estimated,
      );
    }

    return [
      example(
        id: 101,
        ingredient: 'Carne de res',
        location: 'Refrigerador',
        unit: 'kg',
        remaining: 5,
        cost: 120,
        expiresIn: 7,
      ),
      example(
        id: 102,
        ingredient: 'Carne de res',
        location: 'Refrigerador',
        unit: 'kg',
        remaining: 8,
        cost: 125,
        expiresIn: 45,
      ),
      example(
        id: 103,
        ingredient: 'Pollo',
        location: 'Refrigerador',
        unit: 'kg',
        remaining: 3,
        cost: 85,
        expiresIn: 20,
        estimated: true,
      ),
      example(
        id: 104,
        ingredient: 'Lechuga',
        location: 'Refrigerador',
        unit: 'pzas',
        remaining: 2,
        cost: 18,
        expiresIn: -2,
      ),
      example(
        id: 105,
        ingredient: 'Queso cheddar',
        location: 'Refrigerador',
        unit: 'pzas',
        remaining: 10,
        cost: 7,
        expiresIn: 0,
      ),
      example(
        id: 106,
        ingredient: 'Pan de hamburguesa',
        location: 'Almacén',
        unit: 'pzas',
        received: 12,
        remaining: 0,
        cost: 6,
        expiresIn: 25,
      ),
      example(
        id: 107,
        ingredient: 'Salsa BBQ',
        location: 'Almacén',
        unit: 'L',
        remaining: 4,
        cost: 60,
        expiresIn: 40,
      ),
    ];
  }
}
