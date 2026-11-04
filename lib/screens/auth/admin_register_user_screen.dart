import 'package:flutter/material.dart';
import '../../data/staff_catalog.dart';
import '../../services/app_auth_service.dart';
import '../../services/user_role_service.dart';
import '../../theme/app_theme.dart';

class AdminRegisterUserScreen extends StatefulWidget {
  const AdminRegisterUserScreen({super.key});

  @override
  State<AdminRegisterUserScreen> createState() =>
      _AdminRegisterUserScreenState();
}

class _AdminRegisterUserScreenState extends State<AdminRegisterUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authService = AppAuthService();
  final _roleService = UserRoleService();

  String _selectedRole = 'cajero';
  String _selectedBranchId = 'perimetral_sur';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  List<AuthUser> _usersList = [];
  bool _loadingUsers = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final list = await _authService.getRegisteredUsers();
    if (mounted) {
      setState(() {
        _usersList = list;
        _loadingUsers = false;
      });
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Las contraseñas no coinciden.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    final branchName = StaffCatalog.branches[_selectedBranchId] ?? 'General';

    final result = await _authService.registerUser(
      name: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      role: _selectedRole,
      branchId: _selectedBranchId,
      branchName: branchName,
    );

    if (!mounted) return;

    if (result.success) {
      // Limpiar formulario
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.navyBlue,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¡Colaborador "${result.user?.name}" registrado con éxito!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      _loadUsers();
    } else {
      setState(() {
        _errorMessage = result.message ?? 'No se pudo registrar el usuario.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _roleService.isAdmin || _authService.isAdmin;

    return Scaffold(
      backgroundColor: AppTheme.creamBg,
      appBar: AppBar(
        backgroundColor: AppTheme.texasYellow,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.navyBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Registro de Usuarios',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppTheme.navyBlue,
          ),
        ),
      ),
      body: !isAdmin
          ? _buildRestrictedView()
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: 16),
                        _buildFormCard(),
                        const SizedBox(height: 24),
                        _buildUserListSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildRestrictedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.gpp_bad_rounded, size: 64, color: AppTheme.danger),
            const SizedBox(height: 16),
            const Text(
              'Acceso Restringido',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.navyBlue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Solo los administradores pueden registrar nuevos usuarios en el sistema.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.goldLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.gold),
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: AppTheme.navyBlue,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Alta de Personal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navyBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 8),
                    Badge(
                      label: Text('ADMIN'),
                      backgroundColor: AppTheme.navyBlue,
                      textColor: AppTheme.gold,
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Crea cuentas con rol de Cajero o Administrador para el punto de venta.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.borderLight, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppTheme.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Nombre Completo
              const Text(
                'Nombre Completo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration(
                  hint: 'ej. Roberto Sánchez',
                  icon: Icons.person_outline,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa el nombre del colaborador.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Correo Electrónico
              const Text(
                'Correo Electrónico de Acceso',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: _inputDecoration(
                  hint: 'ej. roberto@texasburger.com',
                  icon: Icons.alternate_email,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa el correo electrónico.';
                  }
                  if (!val.contains('@') || !val.contains('.')) {
                    return 'Ingresa un correo válido.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Fila de Rol y Sucursal
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selector de Rol (Cajero / Admin)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rol Asignado',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.navyBlue,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedRole,
                          isExpanded: true,
                          decoration: _inputDecoration(
                            hint: 'Rol',
                            icon: Icons.badge_outlined,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'cajero',
                              child: Text('Cajero'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Administrador'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedRole = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Selector de Sucursal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sucursal',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.navyBlue,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedBranchId,
                          isExpanded: true,
                          decoration: _inputDecoration(
                            hint: 'Sucursal',
                            icon: Icons.store_outlined,
                          ),
                          items: StaffCatalog.branches.entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedBranchId = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Contraseña Inicial
              const Text(
                'Contraseña Inicial',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _inputDecoration(
                  hint: 'Mínimo 6 caracteres',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppTheme.navyBlue,
                      size: 20,
                    ),
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 6) {
                    return 'Mínimo 6 caracteres.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Confirmar Contraseña
              const Text(
                'Confirmar Contraseña',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: _inputDecoration(
                  hint: 'Vuelve a escribir la contraseña',
                  icon: Icons.lock_clock_outlined,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppTheme.navyBlue,
                      size: 20,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Confirma la contraseña.';
                  }
                  if (val != _passwordController.text) {
                    return 'Las contraseñas no coinciden.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Botón de Registrar
              ListenableBuilder(
                listenable: _authService,
                builder: (context, _) {
                  final loading = _authService.isLoading;
                  return ElevatedButton(
                    onPressed: loading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_add_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Registrar Colaborador',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.people_alt_outlined, color: AppTheme.navyBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Personal y Cuentas Registradas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navyBlue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingUsers)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else
          Card(
            color: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.borderLight),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _usersList.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final u = _usersList[index];
                final isAdminRole = u.isAdmin;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isAdminRole
                        ? AppTheme.goldLight
                        : AppTheme.primarySoft,
                    child: Icon(
                      isAdminRole
                          ? Icons.admin_panel_settings
                          : Icons.point_of_sale,
                      color: AppTheme.navyBlue,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    u.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.navyBlue,
                    ),
                  ),
                  subtitle: Text(
                    '${u.email} • ${u.branchName ?? "Sin sucursal"}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isAdminRole
                          ? AppTheme.goldLight
                          : AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isAdminRole
                            ? AppTheme.gold
                            : AppTheme.navyBlueLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      isAdminRole ? 'ADMIN' : 'CAJERO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isAdminRole
                            ? AppTheme.goldDark
                            : AppTheme.navyBlue,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, color: AppTheme.navyBlueLight, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppTheme.primarySoft.withValues(alpha: 0.35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.navyBlue, width: 1.8),
      ),
    );
  }
}

