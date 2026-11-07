import 'package:texas_burger/services/app_auth_service.dart';

const testBranches = {'perimetral_sur': 'Perimetral Sur', 'norte': 'Norte'};

void authenticateAsTestUser({
  String role = 'admin',
  String employeeId = 'demo_sofia_reyes',
  String employeeName = 'Sofía Reyes',
  String? branchId,
}) {
  AppAuthService().setTestSessionForTesting(
    user: AuthUser(
      id: 'test-$role',
      email: '$role@test.texasburger.invalid',
      name: role == 'admin' ? 'Administradora de prueba' : 'Cajera de prueba',
      role: role,
      businessId: 1,
      employeeId: employeeId,
      employeeName: employeeName,
      branchId: branchId,
      branchName: branchId == null ? null : testBranches[branchId],
    ),
    branches: testBranches,
  );
}

void clearTestSession() {
  AppAuthService().setTestSessionForTesting(branches: testBranches);
}
