import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/sales_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sale_history_list.dart';
import '../widgets/export_dialog.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SalesService _salesService = SalesService();
  String _searchFilter = '';
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _salesService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _salesService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showExportDialog(List salesToExport) {
    showDialog(
      context: context,
      builder: (ctx) => ExportDialog(
        sales: salesToExport.cast(),
        title: _selectedDate != null
            ? 'Ventas ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}'
            : 'Historial Completo',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSales = _salesService.sales;

    final filteredSales = allSales.where((sale) {
      if (_selectedDate != null) {
        if (!DateUtils.isSameDay(sale.timestamp, _selectedDate!)) {
          return false;
        }
      }
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        final matchTicket = '#${sale.ticketNumber}'.contains(q) || '${sale.ticketNumber}'.contains(q);
        final matchMethod = sale.paymentMethod.toLowerCase().contains(q);
        final matchOrderType = sale.orderType.toLowerCase().contains(q);
        final matchCustomer = (sale.customerName ?? '').toLowerCase().contains(q);
        final matchProducts = sale.items.any((i) => i.product.name.toLowerCase().contains(q));
        final matchStaff = sale.branchName.toLowerCase().contains(q) ||
            sale.employeeName.toLowerCase().contains(q) ||
            sale.companyName.toLowerCase().contains(q);
        return matchTicket || matchMethod || matchOrderType || matchCustomer || matchProducts || matchStaff;
      }
      return true;
    }).toList();

    final totalAmount = filteredSales.fold<double>(0.0, (sum, s) => sum + s.total);

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) => setState(() => _searchFilter = val),
                        decoration: InputDecoration(
                          hintText: 'Ticket, cliente, producto, sucursal o empleado...',
                          prefixIcon: const Icon(Icons.search, color: AppTheme.navyBlue),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          filled: true,
                          fillColor: AppTheme.creamBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        _selectedDate == null ? Icons.calendar_today_outlined : Icons.calendar_month,
                        color: _selectedDate == null ? AppTheme.navyBlue : AppTheme.primaryRed,
                      ),
                      tooltip: 'Filtrar por fecha',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                    ),
                    if (_selectedDate != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _selectedDate = null),
                      ),
                    IconButton(
                      icon: const Icon(Icons.file_download_outlined, color: AppTheme.primaryRed),
                      tooltip: 'Exportar a CSV o WhatsApp',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showExportDialog(filteredSales),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${filteredSales.length} ventas encontradas',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'Total: \$${totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.primaryRed, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SaleHistoryList(
              sales: filteredSales,
              onDelete: (id) => _salesService.cancelSale(id),
            ),
          ),
        ],
      ),
    );
  }
}
