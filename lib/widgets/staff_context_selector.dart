import 'package:flutter/material.dart';
import '../data/staff_catalog.dart';
import '../models/sale_context.dart';
import '../services/caja_service.dart';
import '../theme/app_theme.dart';

// Selector de sucursal y cajero en turno
class StaffContextSelector extends StatefulWidget {
  final SaleContext? initialSelection;
  final bool lockBranch;
  final ValueChanged<SaleContext> onChanged;

  const StaffContextSelector({
    super.key,
    this.initialSelection,
    this.lockBranch = false,
    required this.onChanged,
  });

  @override
  State<StaffContextSelector> createState() => _StaffContextSelectorState();
}

class _StaffContextSelectorState extends State<StaffContextSelector> {
  String? _branchId;
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    _branchId = widget.initialSelection?.branchId;
    _employeeId = widget.initialSelection?.employeeId;
  }

  void _notifySelection() {
    if (_branchId != null && _employeeId != null) {
      widget.onChanged(StaffCatalog.selection(_branchId!, _employeeId!));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        SaleContext.texasBurgerName,
        style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('staff-branch'),
        initialValue: _branchId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sucursal'),
        items: StaffCatalog.branches.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: widget.lockBranch
            ? null
            : (value) {
                setState(() => _branchId = value);
                _notifySelection();
              },
      ),
      if (widget.lockBranch)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'La sucursal se conserva hasta cerrar el turno.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('staff-employee'),
        initialValue: _employeeId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Empleado activo'),
        items: StaffCatalog.employees.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: (value) {
          setState(() => _employeeId = value);
          _notifySelection();
        },
      ),
      const SizedBox(height: 8),
      const Text(
        'Empleados ficticios de demostración. Cambia el empleado cuando otra persona atienda.',
        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
      ),
    ],
  );
}

Future<bool> selectStaffContext(BuildContext context, CajaService caja) async {
  SaleContext? selection = caja.saleContext;
  final result = await showDialog<SaleContext>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Personal de turno'),
        content: SingleChildScrollView(
          child: StaffContextSelector(
            initialSelection: caja.saleContext,
            lockBranch: caja.isBranchLocked,
            onChanged: (value) => setDialogState(() => selection = value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: selection == null
                ? null
                : () => Navigator.pop(dialogContext, selection),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  if (result == null) return false;
  try {
    await caja.updateSaleContext(result);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar la selección del personal.'),
        ),
      );
    }
    return false;
  }
}

class StaffContextBar extends StatelessWidget {
  const StaffContextBar({super.key});

  @override
  Widget build(BuildContext context) {
    final caja = CajaService();
    return ListenableBuilder(
      listenable: caja,
      builder: (context, _) {
        final selection = caja.saleContext;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.badge_outlined,
                color: AppTheme.navyBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selection == null
                      ? 'Personal: selecciona sucursal y empleado'
                      : '${selection.branchName}\nAtiende: ${selection.employeeName}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.navyBlue,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => selectStaffContext(context, caja),
                child: Text(selection == null ? 'Seleccionar' : 'Cambiar'),
              ),
            ],
          ),
        );
      },
    );
  }
}
