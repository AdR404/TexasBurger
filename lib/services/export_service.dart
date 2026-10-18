import 'dart:io';
import 'package:intl/intl.dart';
import '../models/venta.dart';
import '../models/corte_caja.dart';
import '../models/sale_context.dart';

class ExportService {
  static String generateSalesCsv(List<Venta> sales) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm:ss');

    final buffer = StringBuffer();
    // UTF-8 BOM so Excel opens accented Spanish characters correctly
    buffer.write('\uFEFF');
    buffer.writeln(
      'Ticket,Fecha,Hora,Modalidad,Detalle_Modalidad,Productos,Metodo_Pago,Subtotal,Descuento,Total,Notas,Empresa_ID,Empresa,Sucursal_ID,Sucursal,Empleado_ID,Atendido_Por',
    );

    for (final sale in sales) {
      final ticket = '#${sale.ticketNumber}';
      final fecha = dateFormat.format(sale.timestamp);
      final hora = timeFormat.format(sale.timestamp);
      final modalidad = sale.orderType;

      String detalleModalidad = '';
      if (sale.orderType == 'Comer aquí') {
        detalleModalidad = sale.tableNumber ?? 'Sin mesa';
      } else if (sale.orderType == 'Para llevar') {
        detalleModalidad = sale.customerName ?? 'Mostrador';
      } else if (sale.orderType == 'A domicilio') {
        detalleModalidad = '${sale.customerName ?? ''} - ${sale.customerPhone ?? ''} - ${sale.deliveryAddress ?? ''}';
      }

      final productosStr = sale.items
          .map((i) => '${i.quantity}x ${i.product.name}${i.customizationSummary.isNotEmpty ? " (${i.customizationSummary})" : ""}')
          .join(' + ')
          .replaceAll('"', '""');

      final metodo = sale.paymentMethod;
      final subtotal = sale.subtotal.toStringAsFixed(2);
      final descuento = sale.discount.toStringAsFixed(2);
      final total = sale.total.toStringAsFixed(2);
      final notas = sale.notes.replaceAll('"', '""');
      final staffColumns = [
        sale.saleContext?.companyId ?? SaleContext.texasBurgerId,
        sale.companyName,
        sale.saleContext?.branchId ?? '',
        sale.branchName,
        sale.saleContext?.employeeId ?? '',
        sale.employeeName,
      ].map((value) => '"${value.replaceAll('"', '""')}"').join(',');

      buffer.writeln(
        '"$ticket","$fecha","$hora","$modalidad","${detalleModalidad.replaceAll('"', '""')}","$productosStr","$metodo",$subtotal,$descuento,$total,"$notas",$staffColumns',
      );
    }

    return buffer.toString();
  }

  static Future<String?> saveCsvToDesktop(String csvContent, {String prefix = 'ventas'}) async {
    try {
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'texas_burger_${prefix}_$nowStr.csv';
      
      // Target Desktop directory
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\andyr';
      final desktopDir = Directory('$userProfile\\Desktop');
      
      final file = File('${desktopDir.path}\\$filename');
      await file.writeAsString(csvContent);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  static String generateWhatsAppCorteReport(CorteCaja corte) {
    final dtFormat = DateFormat('dd/MM/yyyy hh:mm a');
    final openedStr = dtFormat.format(corte.openedAt);
    final closedStr = corte.closedAt != null ? dtFormat.format(corte.closedAt!) : 'Turno en curso';

    final buffer = StringBuffer();
    buffer.writeln('🍔 *TEXAS BURGER - CORTE DE CAJA* 🍔');
    buffer.writeln('Empresa: ${corte.openingContext?.companyName ?? SaleContext.texasBurgerName}');
    buffer.writeln('Sucursal: ${corte.openingContext?.branchName ?? SaleContext.notRecorded}');
    buffer.writeln('Abrió caja: ${corte.openingContext?.employeeName ?? SaleContext.notRecorded}');
    buffer.writeln('----------------------------------');
    buffer.writeln('📅 *Apertura:* $openedStr');
    buffer.writeln('🏁 *Cierre:* $closedStr');
    buffer.writeln('🧾 *Órdenes cobradas:* ${corte.ordersCount}');
    buffer.writeln('----------------------------------');
    buffer.writeln('💼 *Fondo Inicial:* \$${corte.initialCash.toStringAsFixed(2)}');
    buffer.writeln('➕ *Ventas en Efectivo:* \$${corte.cashSales.toStringAsFixed(2)}');
    if (corte.cashIn > 0) {
      buffer.writeln('➕ *Entradas a Caja:* \$${corte.cashIn.toStringAsFixed(2)}');
    }
    if (corte.cashOut > 0) {
      buffer.writeln('➖ *Gastos/Salidas:* \$${corte.cashOut.toStringAsFixed(2)}');
    }
    buffer.writeln('----------------------------------');
    buffer.writeln('💰 *EFECTIVO ESPERADO:* \$${corte.expectedCash.toStringAsFixed(2)}');
    
    if (corte.actualCashCounted != null) {
      buffer.writeln('💵 *EFECTIVO CONTADO:* \$${corte.actualCashCounted!.toStringAsFixed(2)}');
      final diff = corte.difference ?? 0.0;
      if (diff == 0) {
        buffer.writeln('✅ *DIFERENCIA:* \$0.00 (Caja Cuadrada)');
      } else if (diff > 0) {
        buffer.writeln('🟢 *SOBRANTE:* +\$${diff.toStringAsFixed(2)}');
      } else {
        buffer.writeln('🔴 *FALTANTE:* -\$${diff.abs().toStringAsFixed(2)}');
      }
    }
    
    buffer.writeln('----------------------------------');
    buffer.writeln('💳 *Tarjeta:* \$${corte.cardSales.toStringAsFixed(2)}');
    buffer.writeln('📱 *Transferencia:* \$${corte.transferSales.toStringAsFixed(2)}');
    buffer.writeln('⭐ *VENTA TOTAL:* \$${corte.totalSales.toStringAsFixed(2)}');

    if (corte.movimientos.isNotEmpty) {
      buffer.writeln('----------------------------------');
      buffer.writeln('📋 *Movimientos de Caja:*');
      for (final m in corte.movimientos) {
        final symbol = m.type == 'entrada' ? '➕' : '➖';
        buffer.writeln('$symbol \$${m.amount.toStringAsFixed(2)} - ${m.concept}');
      }
    }

    if (corte.notes.isNotEmpty) {
      buffer.writeln('----------------------------------');
      buffer.writeln('📝 *Notas:* ${corte.notes}');
    }

    return buffer.toString();
  }

  static String generateWhatsAppSalesReport(List<Venta> sales, String periodName) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final total = sales.fold<double>(0.0, (sum, s) => sum + s.total);
    final cash = sales.where((s) => s.paymentMethod == 'Efectivo').fold<double>(0.0, (sum, s) => sum + s.total);
    final card = sales.where((s) => s.paymentMethod == 'Tarjeta').fold<double>(0.0, (sum, s) => sum + s.total);
    final transfer = sales.where((s) => s.paymentMethod == 'Transferencia').fold<double>(0.0, (sum, s) => sum + s.total);

    final buffer = StringBuffer();
    buffer.writeln('🍔 *TEXAS BURGER - REPORTE DE VENTAS* 🍔');
    buffer.writeln('📅 Periodo: $periodName (${dateFormat.format(DateTime.now())})');
    buffer.writeln('🧾 Total de tickets: ${sales.length}');
    buffer.writeln('----------------------------------');
    buffer.writeln('💵 Efectivo: \$${cash.toStringAsFixed(2)}');
    buffer.writeln('💳 Tarjeta: \$${card.toStringAsFixed(2)}');
    buffer.writeln('📱 Transferencia: \$${transfer.toStringAsFixed(2)}');
    buffer.writeln('----------------------------------');
    buffer.writeln('💰 *VENTA TOTAL:* \$${total.toStringAsFixed(2)}');

    if (sales.isNotEmpty) {
      final saleDate = DateFormat('dd/MM/yyyy');
      final saleTime = DateFormat('HH:mm:ss');
      buffer.writeln('----------------------------------');
      buffer.writeln('📋 *Tickets:*');
      for (final sale in sales) {
        buffer.writeln('#${sale.ticketNumber} — ${sale.companyName}');
        buffer.writeln('Sucursal: ${sale.branchName}');
        buffer.writeln('Atendido por: ${sale.employeeName}');
        buffer.writeln('Fecha: ${saleDate.format(sale.timestamp)} | Hora: ${saleTime.format(sale.timestamp)}');
      }
    }

    return buffer.toString();
  }
}
