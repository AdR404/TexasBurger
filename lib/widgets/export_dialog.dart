import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/venta.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';

class ExportDialog extends StatelessWidget {
  final List<Venta> sales;
  final String title;

  const ExportDialog({
    super.key,
    required this.sales,
    this.title = 'Ventas actuales',
  });

  @override
  Widget build(BuildContext context) {
    final reportText = ExportService.generateWhatsAppSalesReport(sales, title);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.file_download_outlined, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Exportar reporte',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.navyBlue),
                      ),
                      Text(
                        '${sales.length} registros seleccionados',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),

            // Preview Box
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.creamBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    reportText,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: reportText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('¡Copiado al portapapeles! Listo para pegar en WhatsApp.')),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.table_chart, size: 18),
                    label: const Text('Guardar CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.navyBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final csvData = ExportService.generateSalesCsv(sales);
                      final path = await ExportService.saveCsvToDesktop(csvData, prefix: 'reporte');
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              path != null
                                  ? '¡Archivo CSV guardado en el escritorio!\n$path'
                                  : 'No se pudo guardar el archivo.',
                            ),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
