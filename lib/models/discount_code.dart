enum DiscountKind { percentage, fixedAmount }

class DiscountCode {
  final String code;
  final String description;
  final DiscountKind kind;
  final double value;
  final bool isActive;

  const DiscountCode({
    required this.code,
    required this.description,
    required this.kind,
    required this.value,
    this.isActive = true,
  });

  bool get isValid =>
      code.trim().isNotEmpty &&
      value.isFinite &&
      value > 0 &&
      (kind != DiscountKind.percentage || value <= 100);

  double discountFor(double amount) {
    if (!isActive || !isValid || !amount.isFinite || amount <= 0) return 0;
    final discount = kind == DiscountKind.percentage
        ? amount * value / 100
        : value;
    return discount.clamp(0.0, amount).toDouble();
  }

  Map<String, dynamic> toSupabase() => {
    'codigo': code.trim().toUpperCase(),
    'descripcion': description.trim(),
    'tipo': kind == DiscountKind.percentage ? 'porcentaje' : 'monto_fijo',
    'valor': value,
    'activo': isActive,
  };

  factory DiscountCode.fromSupabase(Map<String, dynamic> row) {
    final kind = switch (row['tipo']) {
      'porcentaje' => DiscountKind.percentage,
      'monto_fijo' => DiscountKind.fixedAmount,
      _ => throw const FormatException('Tipo de cupón desconocido'),
    };

    final coupon = DiscountCode(
      code: row['codigo'] as String,
      description: row['descripcion'] as String? ?? '',
      kind: kind,
      value: (row['valor'] as num).toDouble(),
      isActive: row['activo'] as bool? ?? true,
    );

    if (!coupon.isValid) {
      throw const FormatException('Los datos del cupón no son válidos');
    }

    return coupon;
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'description': description,
    'kind': kind.name,
    'value': value,
    'isActive': isActive,
  };

  factory DiscountCode.fromJson(Map<String, dynamic> json) => DiscountCode(
    code: json['code'] as String,
    description: json['description'] as String? ?? '',
    kind: DiscountKind.values.firstWhere(
      (kind) => kind.name == json['kind'],
      orElse: () => throw const FormatException('Tipo de cupón desconocido'),
    ),
    value: (json['value'] as num).toDouble(),
    isActive: json['isActive'] as bool? ?? true,
  );

  DiscountCode copyWith({bool? isActive}) => DiscountCode(
    code: code,
    description: description,
    kind: kind,
    value: value,
    isActive: isActive ?? this.isActive,
  );
}
