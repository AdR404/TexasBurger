import 'venta_item.dart';

class Venta {
  final String id;
  final int ticketNumber;
  final List<VentaItem> items;
  final double subtotal;
  final double discount;
  final double total;
  final String paymentMethod;
  final double cashGiven;
  final double changeReturned;
  final DateTime timestamp;
  final String notes;

  // Modalidad de Pedido
  final String orderType; // 'Comer aquí', 'Para llevar', 'A domicilio'
  final String? tableNumber;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;

  Venta({
    required this.id,
    required this.ticketNumber,
    required this.items,
    required this.subtotal,
    this.discount = 0.0,
    required this.total,
    required this.paymentMethod,
    this.cashGiven = 0.0,
    this.changeReturned = 0.0,
    required this.timestamp,
    this.notes = '',
    this.orderType = 'Comer aquí',
    this.tableNumber,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
  });

  int get totalItemsCount => items.fold(0, (sum, i) => sum + i.quantity);

  String get orderTypeBadge {
    switch (orderType) {
      case 'Para llevar':
        return customerName != null && customerName!.isNotEmpty
            ? '🛍️ Para Llevar • $customerName'
            : '🛍️ Para Llevar';
      case 'A domicilio':
        return customerName != null && customerName!.isNotEmpty
            ? '🛵 Domicilio • $customerName'
            : '🛵 A Domicilio';
      case 'Comer aquí':
      default:
        return tableNumber != null && tableNumber!.isNotEmpty
            ? '🍽️ Comer Aquí • $tableNumber'
            : '🍽️ Comer Aquí';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ticketNumber': ticketNumber,
    'items': items.map((i) => i.toJson()).toList(),
    'subtotal': subtotal,
    'discount': discount,
    'total': total,
    'paymentMethod': paymentMethod,
    'cashGiven': cashGiven,
    'changeReturned': changeReturned,
    'timestamp': timestamp.toIso8601String(),
    'notes': notes,
    'orderType': orderType,
    'tableNumber': tableNumber,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'deliveryAddress': deliveryAddress,
  };

  factory Venta.fromJson(Map<String, dynamic> json) => Venta(
    id: json['id'] as String,
    ticketNumber: json['ticketNumber'] as int? ?? 1,
    items: (json['items'] as List<dynamic>)
        .map((i) => VentaItem.fromJson(i as Map<String, dynamic>))
        .toList(),
    subtotal: (json['subtotal'] as num).toDouble(),
    discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
    total: (json['total'] as num).toDouble(),
    paymentMethod: json['paymentMethod'] as String? ?? 'Efectivo',
    cashGiven: (json['cashGiven'] as num?)?.toDouble() ?? 0.0,
    changeReturned: (json['changeReturned'] as num?)?.toDouble() ?? 0.0,
    timestamp: DateTime.parse(json['timestamp'] as String),
    notes: json['notes'] as String? ?? '',
    orderType: json['orderType'] as String? ?? 'Comer aquí',
    tableNumber: json['tableNumber'] as String?,
    customerName: json['customerName'] as String?,
    customerPhone: json['customerPhone'] as String?,
    deliveryAddress: json['deliveryAddress'] as String?,
  );
}