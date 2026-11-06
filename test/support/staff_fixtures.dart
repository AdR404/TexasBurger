import 'package:texas_burger/data/staff_catalog.dart';
import 'package:texas_burger/models/sale_context.dart';

const testStaffEmployees = [
  StaffEmployee(id: 'demo_ana_torres', name: 'Ana Torres'),
  StaffEmployee(id: 'demo_luis_garcia', name: 'Luis García'),
  StaffEmployee(id: 'demo_sofia_reyes', name: 'Sofía Reyes'),
];

Future<List<StaffEmployee>> loadTestStaffEmployees() async =>
    testStaffEmployees;

SaleContext testStaffSelection(String branchId, String employeeId) {
  const branches = {
    'perimetral_sur': 'Perimetral Sur',
    'norte': 'Norte',
  };
  final branchName = branches[branchId];
  StaffEmployee? employee;
  for (final candidate in testStaffEmployees) {
    if (candidate.id == employeeId) employee = candidate;
  }
  if (branchName == null || employee == null) {
    throw ArgumentError('Fixture de sucursal o empleado desconocido.');
  }
  return SaleContext(
    branchId: branchId,
    branchName: branchName,
    employeeId: employee.id,
    employeeName: employee.name,
  );
}