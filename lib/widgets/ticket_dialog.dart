import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/venta.dart';
import '../theme/app_theme.dart';

class TicketDialog extends StatelessWidget {
  final Venta venta;

  const TicketDialog({
    super.key,
    required this.venta,
  });

  String _generateTicketText() {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm:ss');
    final buffer = StringBuffer();
    buffer.writeln('🍔 *${venta.companyName}* 🍔');
    buffer.writeln('Ticket #${venta.ticketNumber}');
    buffer.writeln('Sucursal: ${venta.branchName}');
    buffer.writeln('Atendido por: ${venta.employeeName}');
    buffer.writeln('Fecha: ${dateFormat.format(venta.timestamp)}');
    buffer.writeln('Hora: ${timeFormat.format(venta.timestamp)}');
    buffer.writeln('Modalidad: ${venta.orderTypeBadge}');
    if (venta.deliveryAddress != null && venta.deliveryAddress!.isNotEmpty) {
      buffer.writeln('Dirección: ${venta.deliveryAddress}');
    }
    if (venta.customerPhone != null && venta.customerPhone!.isNotEmpty) {
      buffer.writeln('Teléfono: ${venta.customerPhone}');
    }
    buffer.writeln('---------------------------');
    for (final item in venta.items) {
      buffer.writeln('${item.quantity}x ${item.product.name} - \$${item.subtotal.toStringAsFixed(2)}');
      if (item.customizationSummary.isNotEmpty) {
        buffer.writeln('   ↳ ${item.customizationSummary}');
      }
    }
    buffer.writeln('---------------------------');
    if (venta.discount > 0) {
      buffer.writeln('Subtotal: \$${venta.subtotal.toStringAsFixed(2)}');
      buffer.writeln('Descuento: -\$${venta.discount.toStringAsFixed(2)}');
    }
    buffer.writeln('TOTAL: \$${venta.total.toStringAsFixed(2)}');
    buffer.writeln('Método: ${venta.paymentMethod}');
    if (venta.paymentMethod == 'Efectivo' && venta.changeReturned > 0) {
      buffer.writeln('Cambio devuelto: \$${venta.changeReturned.toStringAsFixed(2)}');
    }
    buffer.writeln('¡Gracias por su preferencia!');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm:ss');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 390),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: AppTheme.lightRed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppTheme.primaryRed, size: 36),
              ),
              const SizedBox(height: 10),
              const Text(
                '¡Venta Registrada!',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                venta.companyName,
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
              ),
              Text(
                'Ticket #${venta.ticketNumber}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryRed,
                ),
              ),
              Text(
                'Sucursal: ${venta.branchName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              Text(
                'Atendido por: ${venta.employeeName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              Text(
                'Fecha: ${dateFormat.format(venta.timestamp)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              Text(
                'Hora: ${timeFormat.format(venta.timestamp)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 10),

              // Order Type Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.creamBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Text(
                  venta.orderTypeBadge,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.navyBlue),
                ),
              ),
              if (venta.deliveryAddress != null && venta.deliveryAddress!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  venta.deliveryAddress!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],

              const Divider(height: 22),

              // Items
              ...venta.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.quantity}x ',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Expanded(
                          child: Text(
                            item.product.name,
                            style: const TextStyle(fontSize: 13, color: AppTheme.textDark, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '\$${item.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    if (item.customizationSummary.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 20, top: 2),
                        child: Text(
                          item.customizationSummary,
                          style: const TextStyle(fontSize: 11, color: AppTheme.primaryRed, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
              )),

              const Divider(height: 22),

              if (venta.discount > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:', style: TextStyle(color: AppTheme.textMuted)),
                    Text('\$${venta.subtotal.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Descuento / Promo:', style: TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.w600)),
                    Text('-\$${venta.discount.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL:',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.navyBlue),
                  ),
                  Text(
                    '\$${venta.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.primaryRed),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.creamBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Pago con ${venta.paymentMethod}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.navyBlue),
                    ),
                    if (venta.paymentMethod == 'Efectivo' && venta.changeReturned > 0)
                      Text(
                        'Cambio: \$${venta.changeReturned.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.successGreen),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('WhatsApp', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _generateTicketText()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('¡Ticket copiado al portapapeles!')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Aceptar', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
