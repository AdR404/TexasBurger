import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/app_auth_service.dart';
import '../services/caja_service.dart';
import '../services/db_service.dart';
import '../services/sales_service.dart';
import '../theme/app_theme.dart';
import '../services/sale_actions.dart';
import 'sale_actions_panel.dart';

/// A read-only view: server rows never replace the local history used by Caja.
class RemoteSaleHistory extends StatefulWidget {
  const RemoteSaleHistory({super.key, required this.active, this.load});
  final bool active;
  final Future<List<Map<String, dynamic>>> Function({
    int page,
    String? branchId,
    DateTime? date,
  })?
  load;

  @override
  State<RemoteSaleHistory> createState() => _RemoteSaleHistoryState();
}

class _RemoteSaleHistoryState extends State<RemoteSaleHistory> {
  List<Map<String, dynamic>> _rows = [];
  String? _branch;
  DateTime? _date;
  String _search = '';
  String? _error;
  bool _loading = false;
  bool _more = false;
  int _page = 0;
  int _revision = 0;
  String? _contextBranch;

  @override
  void initState() {
    super.initState();
    _contextBranch = CajaService().saleContext?.branchId;
    _branch = _contextBranch;
    CajaService().addListener(_contextChanged);
    SalesService().addListener(_salesChanged);
    if (widget.active) _refresh();
  }

  @override
  void didUpdateWidget(covariant RemoteSaleHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void dispose() {
    _revision++;
    CajaService().removeListener(_contextChanged);
    SalesService().removeListener(_salesChanged);
    super.dispose();
  }

  void _contextChanged() {
    final branch = CajaService().saleContext?.branchId;
    if (branch == _contextBranch) return;
    _contextBranch = branch;
    _branch = branch;
    _refresh();
  }

  void _salesChanged() {
    if (widget.active) _refresh();
  }

  Future<void> _refresh({int page = 0}) async {
    final revision = ++_revision;
    setState(() {
      _page = page;
      _rows = [];
      _more = false;
      _error = null;
      _loading = true;
    });
    if (!widget.active) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await (widget.load ?? DbService.consultarHistorial)(
        page: page,
        branchId: _branch,
        date: _date,
      );
      if (widget.load == null) await SalesService().applyRemoteStates(rows);
      if (!mounted || revision != _revision) return;
      setState(() {
        _rows = rows.take(50).toList();
        _more = rows.length > 50;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(
        () => _error =
            'No se pudo consultar el historial remoto. '
            'Revisa la conexión y los permisos de lectura. No se muestran ventas locales como sustituto.',
      );
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  bool _matches(Map<String, dynamic> sale) {
    final terms = [
      sale['id'],
      sale['metodo_pago'],
      sale['empresa_nombre'],
      sale['sucursal_nombre'],
      sale['empleado_nombre'],
      ..._details(sale).map((d) => (d['productos'] as Map?)?['nombre']),
    ];
    final query = _search.trim().toLowerCase().replaceFirst(RegExp(r'^#'), '');
    return terms.any(
      (term) => term?.toString().toLowerCase().contains(query) ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows.where(_matches).toList();
    final totalsKnown = rows.every((r) => r['total'] is num);
    final total = rows.fold<double>(
      0,
      (s, r) =>
          s +
          (r['estado'] == 'cancelada'
              ? 0
              : ((r['total'] as num?)?.toDouble() ?? 0)),
    );
    final showEmpty = !_loading && _error == null && rows.isEmpty;
    return Scaffold(
      backgroundColor: AppTheme.creamBg,
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
                        onChanged: (value) => setState(() => _search = value),
                        decoration: InputDecoration(
                          hintText:
                              'Ticket, producto, pago, sucursal o empleado...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppTheme.navyBlue,
                          ),
                          filled: true,
                          fillColor: AppTheme.creamBg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _date == null
                          ? 'Filtrar por fecha'
                          : DateFormat('dd/MM/yyyy').format(_date!),
                      icon: Icon(
                        Icons.calendar_today_outlined,
                        color: _date == null
                            ? AppTheme.navyBlue
                            : AppTheme.infoBlue,
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (!mounted || picked == null) return;
                        _date = picked;
                        _refresh();
                      },
                    ),
                    if (_date != null)
                      IconButton(
                        tooltip: 'Quitar filtro de fecha',
                        icon: const Icon(
                          Icons.close,
                          color: AppTheme.textMuted,
                        ),
                        onPressed: () {
                          _date = null;
                          _refresh();
                        },
                      ),
                    IconButton(
                      tooltip: 'Actualizar historial',
                      icon: const Icon(Icons.refresh, color: AppTheme.navyBlue),
                      onPressed: _loading ? null : () => _refresh(),
                    ),
                    if (AppAuthService().isAdmin)
                      PopupMenuButton<String>(
                        tooltip: 'Filtrar por sucursal',
                        icon: Icon(
                          Icons.filter_alt_outlined,
                          color: _branch == null
                              ? AppTheme.navyBlue
                              : AppTheme.infoBlue,
                        ),
                        onSelected: (value) {
                          _branch = value.isEmpty ? null : value;
                          _refresh();
                        },
                        itemBuilder: (context) => [
                          CheckedPopupMenuItem(
                            value: '',
                            checked: _branch == null,
                            child: const Text('Todas las sucursales'),
                          ),
                          ...AppAuthService().branches.entries.map(
                            (entry) => CheckedPopupMenuItem(
                              value: entry.key,
                              checked: _branch == entry.key,
                              child: Text(entry.value),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${rows.length} ventas encontradas',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                    Tooltip(
                      message:
                          'Suma de esta página; excluye ventas canceladas. El ID remoto no es el folio local.',
                      child: Text(
                        'Total: ${totalsKnown ? _money(total) : 'No disponible'}',
                        style: const TextStyle(
                          color: AppTheme.navyBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                  TextButton(
                    onPressed: () => _refresh(page: _page),
                    child: const Text('Reintentar consulta'),
                  ),
                ],
                if (_loading) const LinearProgressIndicator(),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _loading && rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _error != null
                          ? 0
                          : rows.length + 1 + (showEmpty ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (_error != null) {
                          return const SizedBox.shrink();
                        }
                        if (showEmpty && index == 0) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Text('No hay ventas para esos filtros.'),
                            ),
                          );
                        }
                        final pageIndex = rows.length + (showEmpty ? 1 : 0);
                        if (index == pageIndex) {
                          return Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _loading || _page == 0
                                    ? null
                                    : () => _refresh(page: _page - 1),
                                child: const Text('Anterior'),
                              ),
                              Text('Página ${_page + 1}'),
                              TextButton(
                                onPressed: _loading || !_more
                                    ? null
                                    : () => _refresh(page: _page + 1),
                                child: const Text('Siguiente'),
                              ),
                            ],
                          );
                        }
                        final sale = rows[index - (showEmpty ? 1 : 0)];
                        return _RemoteSaleCard(
                          sale: sale,
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => _RemoteSaleDetails(
                              sale: sale,
                              onChanged: () async {
                                await _refresh(page: _page);
                                await CajaService().refreshRemote();
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteSaleCard extends StatelessWidget {
  const _RemoteSaleCard({required this.sale, required this.onTap});
  final Map<String, dynamic> sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = _details(sale);
    final units = details.fold<int>(
      0,
      (sum, detail) => sum + ((detail['cantidad'] as num?)?.toInt() ?? 0),
    );
    final date = DateTime.tryParse(
      sale['fecha_hora']?.toString() ?? '',
    )?.toLocal();
    final now = DateTime.now();
    final timeText = date == null
        ? 'Fecha no disponible'
        : DateUtils.isSameDay(date, now)
        ? 'Hoy, ${DateFormat('HH:mm:ss').format(date)}'
        : DateFormat('dd/MM/yyyy HH:mm:ss').format(date);
    final cancelled = sale['estado'] == 'cancelada';
    final productText = details
        .map((detail) {
          final name =
              (detail['productos'] as Map?)?['nombre']?.toString() ??
              'Producto';
          return '${detail['cantidad'] ?? '?'}x $name';
        })
        .join(', ');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.navyBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#${_text(sale['id'])}',
                  style: const TextStyle(
                    color: AppTheme.navyBlue,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          timeText,
                          style: const TextStyle(
                            color: AppTheme.navyBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _RemoteBadge(
                          label: _text(sale['metodo_pago']),
                          color: AppTheme.infoSoft,
                          foreground: AppTheme.navyBlue,
                        ),
                        if (cancelled)
                          _RemoteBadge(
                            label: 'CANCELADA',
                            color: AppTheme.dangerSoft,
                            foreground: AppTheme.danger,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_text(sale['empresa_nombre'])} • ${_text(sale['sucursal_nombre'])}',
                      style: const TextStyle(color: AppTheme.navyBlue),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Atendido por: ${_text(sale['empleado_nombre'])}',
                      style: const TextStyle(color: AppTheme.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (productText.isNotEmpty)
                      Text(
                        productText,
                        style: const TextStyle(color: AppTheme.textMuted),
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
                    _money(sale['total']),
                    style: const TextStyle(
                      color: AppTheme.navyBlue,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '$units items',
                    style: const TextStyle(color: AppTheme.textMuted),
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

class _RemoteBadge extends StatelessWidget {
  const _RemoteBadge({
    required this.label,
    required this.color,
    required this.foreground,
  });
  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

String _text(Object? value) => value == null || value.toString().trim().isEmpty
    ? 'No disponible'
    : value.toString();
String _money(Object? value) =>
    value is num ? '\$${value.toStringAsFixed(2)}' : 'No disponible';
String _dateText(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Fecha no disponible'
      : DateFormat('dd/MM/yyyy HH:mm:ss').format(date.toLocal());
}

List<Map<String, dynamic>> _details(Map<String, dynamic> sale) =>
    (sale['detalle_venta'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

class _RemoteSaleDetails extends StatelessWidget {
  const _RemoteSaleDetails({required this.sale, required this.onChanged});
  final Future<void> Function() onChanged;
  final Map<String, dynamic> sale;

  Future<void> _copyTicket(
    BuildContext context,
    List<Map<String, dynamic>> details,
  ) async {
    final date = DateTime.tryParse(
      sale['fecha_hora']?.toString() ?? '',
    )?.toLocal();
    final text = StringBuffer()
      ..writeln('Texas Burger')
      ..writeln('Ticket remoto #${_text(sale['id'])}')
      ..writeln(
        'Fecha: ${date == null ? 'No disponible' : DateFormat('dd/MM/yyyy').format(date)}',
      )
      ..writeln(
        'Hora: ${date == null ? 'No disponible' : DateFormat('HH:mm:ss').format(date)}',
      )
      ..writeln('Sucursal: ${_text(sale['sucursal_nombre'])}')
      ..writeln('Atendió: ${_text(sale['empleado_nombre'])}')
      ..writeln('Pago: ${_text(sale['metodo_pago'])}')
      ..writeln('---------------------------');
    for (final detail in details) {
      final product =
          (detail['productos'] as Map?)?['nombre']?.toString() ??
          'Producto no disponible';
      text.writeln(
        '${detail['cantidad'] ?? '?'}x $product · ${_money(detail['precio_unitario'])}',
      );
    }
    text
      ..writeln('---------------------------')
      ..writeln('Subtotal: ${_money(sale['subtotal'])}')
      ..writeln('Descuento: ${_money(sale['descuento'])}')
      ..writeln('Código aplicado: ${_text(sale['codigo_descuento'])}')
      ..writeln('IVA: ${_money(sale['iva'])}')
      ..writeln('Total: ${_money(sale['total'])}');
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Ticket copiado al portapapeles.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details(sale);
    final completeAmounts =
        details.isNotEmpty &&
        details.every(
          (d) => d['cantidad'] is num && d['precio_unitario'] is num,
        );
    final detailSubtotal = completeAmounts
        ? details.fold<double>(
            0,
            (s, d) =>
                s + (d['cantidad'] as num) * (d['precio_unitario'] as num),
          )
        : null;
    final differs =
        detailSubtotal != null &&
        sale['subtotal'] is num &&
        (detailSubtotal - (sale['subtotal'] as num)).abs() > 0.01;
    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
    final cancelled = sale['estado'] == 'cancelada';
    final date = DateTime.tryParse(
      sale['fecha_hora']?.toString() ?? '',
    )?.toLocal();
    final includesTax = sale['iva_incluido'] == true;
    final taxRate = sale['tasa_iva'] is num
        ? ((sale['tasa_iva'] as num) * 100).round()
        : null;
    final tax = (sale['iva'] as num?)?.toDouble();
    final total = (sale['total'] as num?)?.toDouble();
    final taxableBase = includesTax && tax != null && total != null
        ? total - tax
        : null;
    return AlertDialog(
      title: Column(
        children: [
          Icon(
            cancelled ? Icons.cancel_rounded : Icons.check_circle_rounded,
            color: cancelled ? AppTheme.danger : AppTheme.successGreen,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            cancelled ? 'Venta CANCELADA' : '¡Venta Registrada!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.navyBlue,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            _text(sale['empresa_nombre']),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.navyBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          Tooltip(
            message: 'Este número es el ID remoto, no el folio local.',
            child: Text(
              'Ticket #${_text(sale['id'])}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.navyBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 390,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sucursal: ${_text(sale['sucursal_nombre'])}',
                textAlign: TextAlign.center,
              ),
              Text(
                'Atendido por: ${_text(sale['empleado_nombre'])}',
                textAlign: TextAlign.center,
              ),
              Text(
                date == null
                    ? 'Fecha y hora: No disponible'
                    : 'Fecha: ${DateFormat('dd/MM/yyyy').format(date)}  ·  Hora: ${DateFormat('HH:mm:ss').format(date)}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (cancelled) ...[
                const SizedBox(height: 10),
                field('Motivo', _text(sale['cancelacion_motivo'])),
                field('Cancelada el', _dateText(sale['cancelada_en'])),
                field('Administrador (UUID)', _text(sale['cancelada_por'])),
                field(
                  'Inventario reintegrado',
                  sale['inventario_reintegrado'] == true ? 'Sí' : 'No',
                ),
                if (SaleActions.verifiedCashEnabled &&
                    sale['metodo_pago'] == 'Efectivo')
                  field(
                    'Efectivo',
                    switch (sale['efectivo_cancelacion_estado']) {
                      'no_cobrado' => 'Nunca se cobró',
                      'devuelto' => 'Devuelto',
                      _ => 'Pendiente de conciliación',
                    },
                  ),
              ],
              const Divider(height: 24),
              if (details.isEmpty)
                const Text(
                  'Esta venta no tiene detalles disponibles. No se puede verificar su integridad.',
                ),
              if (differs || (!completeAmounts && details.isNotEmpty))
                const Text(
                  'Detalles incompletos o importes distintos del subtotal registrado. Revisa la BD.',
                ),
              if (details.length >= 201)
                const Text(
                  'Solo se muestran los primeros 201 detalles. Consulta la BD para revisar el resto.',
                ),
              ...details.map((detail) {
                final product =
                    (detail['productos'] as Map?)?['nombre']?.toString() ??
                    'Producto sin nombre disponible (ID ${_text(detail['producto_id'])})';
                final quantity = detail['cantidad'];
                final amount =
                    quantity is num && detail['precio_unitario'] is num
                    ? _money(quantity * (detail['precio_unitario'] as num))
                    : 'No disponible';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_text(quantity)}x '),
                      Expanded(
                        child: Text(
                          product,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(amount),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
              field('Subtotal:', _money(sale['subtotal'])),
              if (((sale['descuento'] as num?)?.toDouble() ?? 0) > 0)
                field('Descuento / Promo:', '-${_money(sale['descuento'])}'),
              if (sale['codigo_descuento'] != null)
                field('Código aplicado:', _text(sale['codigo_descuento'])),
              if (taxableBase != null)
                field('Base sin IVA:', _money(taxableBase)),
              if (sale['iva'] != null)
                field(
                  includesTax && taxRate != null
                      ? 'IVA incluido ($taxRate%):'
                      : 'IVA registrado:',
                  _money(sale['iva']),
                ),
              field('Total:', _money(sale['total'])),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.creamBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Pago con ${_text(sale['metodo_pago'])}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.navyBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      buttonPadding: EdgeInsets.zero,
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyTicket(context, details),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    minimumSize: const Size(0, 52),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('WhatsApp', softWrap: false),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SaleActionsPanel(
                  sale: sale,
                  onChanged: onChanged,
                  ticketStyle: true,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    minimumSize: const Size(0, 52),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Aceptar', softWrap: false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
