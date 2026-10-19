/// Snapshot of the staff selection when a sale is completed.
/// Names are retained so later catalog changes cannot rewrite old tickets.
class SaleContext {
  static const texasBurgerId = 'texas_burger';
  static const texasBurgerName = 'Texas Burger';
  static const notRecorded = 'No registrado';

  final String companyId;
  final String companyName;
  final String branchId;
  final String branchName;
  final String employeeId;
  final String employeeName;

  const SaleContext({
    this.companyId = texasBurgerId,
    this.companyName = texasBurgerName,
    required this.branchId,
    required this.branchName,
    required this.employeeId,
    required this.employeeName,
  });

  Map<String, dynamic> toJson() => {
    'companyId': companyId,
    'companyName': companyName,
    'branchId': branchId,
    'branchName': branchName,
    'employeeId': employeeId,
    'employeeName': employeeName,
  };

  factory SaleContext.fromJson(Map<String, dynamic> json) => SaleContext(
    companyId: json['companyId'] as String? ?? texasBurgerId,
    companyName: json['companyName'] as String? ?? texasBurgerName,
    branchId: json['branchId'] as String,
    branchName: json['branchName'] as String,
    employeeId: json['employeeId'] as String,
    employeeName: json['employeeName'] as String,
  );
}
