class AppConfig {
  final String businessName;
  final String slogan;
  final String establishedYear;
  final String currency;
  final String address;
  final String phone;

  const AppConfig({
    this.businessName = 'TEXAS BURGER',
    this.slogan = 'Deliciosamente asadas al carbón',
    this.establishedYear = '1995',
    this.currency = 'MXN',
    this.address = 'Texas Burger Sucursal',
    this.phone = '',
  });

  Map<String, dynamic> toJson() => {
    'businessName': businessName,
    'slogan': slogan,
    'establishedYear': establishedYear,
    'currency': currency,
    'address': address,
    'phone': phone,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    businessName: json['businessName'] as String? ?? 'TEXAS BURGER',
    slogan: json['slogan'] as String? ?? 'Deliciosamente asadas al carbón',
    establishedYear: json['establishedYear'] as String? ?? '1995',
    currency: json['currency'] as String? ?? 'MXN',
    address: json['address'] as String? ?? 'Texas Burger Sucursal',
    phone: json['phone'] as String? ?? '',
  );
}