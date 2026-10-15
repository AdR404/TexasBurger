import '../models/sale_context.dart';

/// Stable local IDs. Demo employee IDs are NOT IDs from Supabase usuarios.
class StaffCatalog {
  static const branches = {
    'perimetral_sur': 'Perimetral Sur',
    'norte': 'Norte',
  };

  static const employees = {
    'demo_ana_torres': 'Ana Torres',
    'demo_luis_garcia': 'Luis García',
    'demo_sofia_reyes': 'Sofía Reyes',
  };

  static SaleContext selection(String branchId, String employeeId) {
    if (!branches.containsKey(branchId) || !employees.containsKey(employeeId)) {
      throw ArgumentError(
        'Selecciona una sucursal y un empleado del catálogo.',
      );
    }
    return SaleContext(
      branchId: branchId,
      branchName: branches[branchId]!,
      employeeId: employeeId,
      employeeName: employees[employeeId]!,
    );
  }
}
