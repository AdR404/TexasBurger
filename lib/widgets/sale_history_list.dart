import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/venta.dart';
import '../theme/app_theme.dart';
import 'ticket_dialog.dart';

class SaleHistoryList extends StatelessWidget {
  final List<Venta> sales;
  final Function(String id)? onDelete;

  const SaleHistoryList({
    super.key,
    required this.sales,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No hay ventas en el historial',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
            ),
            const SizedBox(height: 4),
            const Text(
              'Las órdenes que cobres aparecerán aquí',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    final timeFormat = DateFormat('HH:mm:ss');
    final dateFormat = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: sales.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final venta = sales[index];
        final isToday = venta.timestamp.year == now.year &&
            venta.timestamp.month == now.month &&
            venta.timestamp.day == now.day;

        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => TicketDialog(venta: venta),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.navyBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '#${venta.ticketNumber}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navyBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Flexible(
                              child: Text(
                                isToday ? 'Hoy, ${timeFormat.format(venta.timestamp)}' : '${dateFormat.format(venta.timestamp)} ${timeFormat.format(venta.timestamp)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.navyBlue,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getMethodBg(venta.paymentMethod),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                venta.paymentMethod,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getMethodColor(venta.paymentMethod),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${venta.companyName} • ${venta.branchName}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.navyBlue),
                        ),
                        Text(
                          'Atendido por: ${venta.employeeName}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        Text(
                          venta.orderTypeBadge,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          venta.items.map((i) => '${i.quantity}x ${i.product.name}').join(', '),
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${venta.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
                      Text(
                        '${venta.totalItemsCount} items',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getMethodColor(String method) {
    if (method.toLowerCase().contains('efectivo')) return AppTheme.navyBlue;
    if (method.toLowerCase().contains('transfer')) return AppTheme.goldDark;
    if (method.toLowerCase().contains('tarjeta')) return AppTheme.infoBlue;
    return AppTheme.gold;
  }

  Color _getMethodBg(String method) {
    if (method.toLowerCase().contains('efectivo')) return AppTheme.infoSoft;
    if (method.toLowerCase().contains('transfer')) return AppTheme.goldSoft;
    return _getMethodColor(method).withValues(alpha: 0.12);
  }
}
