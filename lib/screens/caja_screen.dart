import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/corte_caja.dart';
import '../models/sale_context.dart';
import '../services/caja_service.dart';
import '../services/sales_service.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/staff_context_selector.dart';

class CajaScreen extends StatefulWidget {
  const CajaScreen({super.key});

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  final CajaService _cajaService = CajaService();
  final SalesService _salesService = SalesService();

  @override
  void initState() {
    super.initState();
    _cajaService.addListener(_onUpdate);
    _salesService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _cajaService.removeListener(_onUpdate);
    _salesService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _showAbrirCajaDialog() {
    final controller = TextEditingController(text: '500');
    final presets = [300, 500, 800, 1000, 1500];
    SaleContext? selection = _cajaService.saleContext;
    bool opening = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.point_of_sale, color: AppTheme.primaryRed),
              SizedBox(width: 8),
              Text('Apertura de Caja', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StaffContextSelector(
                initialSelection: _cajaService.saleContext,
                onChanged: (value) => setDialogState(() => selection = value),
              ),
              const SizedBox(height: 16),
              const Text('Ingresa el monto del fondo inicial en efectivo para cambio:'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  filled: true,
                  fillColor: AppTheme.creamBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: presets.map((val) => ActionChip(
                  label: Text('\$$val'),
                  backgroundColor: controller.text == '$val' ? AppTheme.lightRed : AppTheme.creamBg,
                  onPressed: () {
                    setDialogState(() {
                      controller.text = '$val';
                    });
                  },
                )).toList(),
              ),
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selection == null || opening ? null : () async {
                setDialogState(() => opening = true);
                final amount = double.tryParse(controller.text) ?? 0.0;
                await _cajaService.abrirCaja(amount, saleContext: selection!);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Iniciar Turno'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMovimientoDialog({required String type}) {
    final amountController = TextEditingController();
    final conceptController = TextEditingController();
    final isGasto = type == 'salida';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isGasto ? Icons.remove_circle : Icons.add_circle, color: isGasto ? Colors.red : AppTheme.successGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isGasto ? 'Registrar Gasto / Salida' : 'Registrar Entrada de Efectivo',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Monto en efectivo',
                prefixText: '\$ ',
                filled: true,
                fillColor: AppTheme.creamBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: conceptController,
              decoration: InputDecoration(
                labelText: 'Concepto o motivo',
                hintText: isGasto ? 'Ej. Hielo, verduras, pago gas, etc.' : 'Ej. Aporte de cambio extra',
                filled: true,
                fillColor: AppTheme.creamBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isGasto ? Colors.red : AppTheme.successGreen,
            ),
            onPressed: () async {
              final amount = double.tryParse(amountController.text) ?? 0.0;
              final concept = conceptController.text.trim();
              if (amount > 0 && concept.isNotEmpty) {
                await _cajaService.registrarMovimiento(type: type, amount: amount, concept: concept);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showCierreCajaDialog(CorteCaja live) {
    final countedController = TextEditingController(text: live.expectedCash.toStringAsFixed(0));
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final counted = double.tryParse(countedController.text) ?? 0.0;
          final diff = counted - live.expectedCash;

          Color diffColor = AppTheme.successGreen;
          String diffText = 'Caja Cuadrada (Exacto)';
          if (diff > 0) {
            diffColor = Colors.blue.shade700;
            diffText = 'Sobrante: +\$${diff.toStringAsFixed(2)}';
          } else if (diff < 0) {
            diffColor = Colors.red;
            diffText = 'Faltante: -\$${diff.abs().toStringAsFixed(2)}';
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.inventory_rounded, color: AppTheme.primaryRed),
                SizedBox(width: 8),
                Text('Arqueo y Corte de Caja', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.creamBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildRow('Fondo Inicial:', '\$${live.initialCash.toStringAsFixed(2)}'),
                        _buildRow('Ventas Efectivo:', '+\$${live.cashSales.toStringAsFixed(2)}'),
                        if (live.cashIn > 0) _buildRow('Entradas extra:', '+\$${live.cashIn.toStringAsFixed(2)}'),
                        if (live.cashOut > 0) _buildRow('Gastos / Salidas:', '-\$${live.cashOut.toStringAsFixed(2)}', isNegative: true),
                        const Divider(height: 16),
                        _buildRow('EFECTIVO ESPERADO:', '\$${live.expectedCash.toStringAsFixed(2)}', isBold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Efectivo real contado en caja:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: countedController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    onChanged: (val) => setDialogState(() {}),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: diffColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: diffColor),
                    ),
                    child: Text(
                      diffText,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notas del cierre (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
                onPressed: () async {
                  final closedCorte = await _cajaService.cerrarCaja(
                    actualCashCounted: counted,
                    notes: notesController.text.trim(),
                    allSales: _salesService.sales,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showCorteResultDialog(closedCorte);
                  }
                },
                child: const Text('Cerrar Turno'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCorteResultDialog(CorteCaja corte) {
    final report = ExportService.generateWhatsAppCorteReport(corte);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¡Corte de Caja Finalizado!', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El turno ha sido cerrado con éxito. Puedes copiar el resumen para enviarlo por WhatsApp al dueño/administrador:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.creamBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(report, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Aceptar')),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar para WhatsApp'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('¡Corte copiado! Puedes pegarlo en WhatsApp.')),
              );
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
              color: isNegative ? Colors.red : (isBold ? AppTheme.navyBlue : AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _cajaService.isCajaOpen;
    final live = _cajaService.computeLiveShift(_salesService.sales);
    final history = _cajaService.cortesHistory;
    final dtFormat = DateFormat('dd/MM/yyyy hh:mm a');

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StaffContextBar(),
            const SizedBox(height: 12),
            // Status Card
            if (!isOpen) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.borderLight),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppTheme.creamBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_clock, size: 36, color: AppTheme.navyBlue),
                    ),
                    const SizedBox(height: 12),
                    const Text('Caja Actualmente Cerrada', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppTheme.navyBlue)),
                    const SizedBox(height: 6),
                    const Text(
                      'Inicia el turno ingresando el fondo de caja en efectivo para registrar ventas, gastos y arqueo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Abrir Caja / Iniciar Turno'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      onPressed: _showAbrirCajaDialog,
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Open Shift Live Dashboard
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.navyBlue, Color(0xFF1E3A5F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppTheme.navyBlue.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(color: AppTheme.successGreen, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            const Text('TURNO EN CURSO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                          ],
                        ),
                        Text(
                          'Apertura: ${DateFormat('hh:mm a').format(live.openedAt)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Efectivo Esperado en Cajón', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '\$${live.expectedCash.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _buildMiniMetric('Fondo', '\$${live.initialCash.toStringAsFixed(0)}')),
                          Expanded(child: _buildMiniMetric('Ventas Efec.', '+\$${live.cashSales.toStringAsFixed(0)}')),
                          Expanded(child: _buildMiniMetric('Entradas', '+\$${live.cashIn.toStringAsFixed(0)}')),
                          Expanded(child: _buildMiniMetric('Gastos', '-\$${live.cashOut.toStringAsFixed(0)}')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.credit_card, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '\$${live.cardSales.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.phone_android, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '\$${live.transferSales.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Total: \$${live.totalSales.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.gold, fontWeight: FontWeight.bold, fontSize: 13),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons for Open Caja
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      label: const Text('Registrar Gasto', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _showMovimientoDialog(type: 'salida'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_circle_outline, color: AppTheme.successGreen),
                      label: const Text('Entrada Efectivo', style: TextStyle(color: AppTheme.successGreen)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.successGreen),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _showMovimientoDialog(type: 'entrada'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Hacer Corte de Caja (Cerrar Turno)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _showCierreCajaDialog(live),
                ),
              ),

              // Shift Movements List
              if (live.movimientos.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Movimientos del Turno', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.navyBlue)),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: live.movimientos.length,
                    separatorBuilder: (context, i) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = live.movimientos[i];
                      final isGasto = m.type == 'salida';
                      return ListTile(
                        dense: true,
                        leading: Icon(isGasto ? Icons.arrow_downward : Icons.arrow_upward, color: isGasto ? Colors.red : AppTheme.successGreen),
                        title: Text(m.concept, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(DateFormat('hh:mm a').format(m.timestamp), style: const TextStyle(fontSize: 11)),
                        trailing: Text(
                          '${isGasto ? '-' : '+'}\$${m.amount.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isGasto ? Colors.red : AppTheme.successGreen),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],

            // History Section
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Historial de Cortes Anteriores', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.navyBlue)),
                Text('${history.length} cortes', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 10),

            if (history.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: const Center(
                  child: Text('Aún no hay cortes registrados en el historial.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final c = history[index];
                  final diff = c.difference ?? 0.0;
                  Color diffBadgeColor = AppTheme.successGreen;
                  String diffLabel = 'Cuadrado (\$0)';
                  if (diff > 0) {
                    diffBadgeColor = Colors.blue;
                    diffLabel = 'Sobrante +\$${diff.toStringAsFixed(2)}';
                  } else if (diff < 0) {
                    diffBadgeColor = Colors.red;
                    diffLabel = 'Faltante -\$${diff.abs().toStringAsFixed(2)}';
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                dtFormat.format(c.openedAt),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.navyBlue),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: diffBadgeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: diffBadgeColor),
                                ),
                                child: Text(diffLabel, style: TextStyle(color: diffBadgeColor, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${c.ordersCount} órdenes', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text('Venta Total: \$${c.totalSales.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryRed)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Esperado: \$${c.expectedCash.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Contado: \$${(c.actualCashCounted ?? 0).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share, size: 18, color: AppTheme.navyBlue),
                                tooltip: 'Compartir reporte',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                onPressed: () => _showCorteResultDialog(c),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
