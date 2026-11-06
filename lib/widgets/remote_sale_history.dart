import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/app_auth_service.dart';
import '../services/caja_service.dart';
import '../services/db_service.dart';
import '../services/sales_service.dart';
import '../theme/app_theme.dart';

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
      (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0),
    );
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                hintText: 'ID remoto, producto, pago, sucursal o empleado...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(_branch),
              initialValue: _branch ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sucursal del historial',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Todas las sucursales'),
                ),
                ...AppAuthService().branches.entries.map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                ),
              ],
              onChanged: !AppAuthService().isAdmin
                  ? null
                  : (value) {
                      _branch = value == '' ? null : value;
                      _refresh();
                    },
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _date == null
                        ? 'Filtrar por fecha'
                        : DateFormat('dd/MM/yyyy').format(_date!),
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
                    tooltip: 'Quitar fecha',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _date = null;
                      _refresh();
                    },
                  ),
                IconButton(
                  tooltip: 'Actualizar historial',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : () => _refresh(),
                ),
              ],
            ),
            const Text(
              'Supabase · Solo consulta. Búsqueda y suma sobre esta página (50 ventas máximo). '
              'El ID remoto no es el folio del ticket local.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
              TextButton(
                onPressed: () => _refresh(page: _page),
                child: const Text('Reintentar consulta'),
              ),
            ],
            if (!_loading && _error == null) ...[
              Text(
                '${rows.length} ventas · Total visible: ${totalsKnown ? _money(total) : 'No disponible'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay ventas para los filtros de esta página.'),
                ),
              ...rows.map(
                (sale) => Card(
                  child: ListTile(
                    title: Text(
                      'Venta remota #${_text(sale['id'])} · ${_money(sale['total'])}',
                    ),
                    subtitle: Text(
                      '${_dateText(sale['fecha_hora'])}\n'
                      '${_text(sale['metodo_pago'])} · ${_text(sale['sucursal_nombre'])}\n'
                      'Atendió: ${_text(sale['empleado_nombre'])}',
                    ),
                    isThreeLine: true,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _RemoteSaleDetails(sale: sale),
                    ),
                  ),
                ),
              ),
            ],
            Wrap(
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
            ),
          ],
        ),
      ),
    );
  }
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
  const _RemoteSaleDetails({required this.sale});
  final Map<String, dynamic> sale;

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
    return AlertDialog(
      title: Text('Venta remota #${_text(sale['id'])}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_dateText(sale['fecha_hora'])),
              field('Empresa', _text(sale['empresa_nombre'])),
              field('Sucursal', _text(sale['sucursal_nombre'])),
              field('Atendió', _text(sale['empleado_nombre'])),
              field('Pago', _text(sale['metodo_pago'])),
              const Divider(),
              if (details.isEmpty)
                const Text(
                  'Esta venta no tiene detalles disponibles. No se puede verificar su integridad.',
                ),
              if (differs || (!completeAmounts && details.isNotEmpty))
                const Text(
                  'Detalles incompletos o importes distintos del subtotal registrado. Revisa la venta en BD.',
                ),
              if (details.length >= 201)
                const Text(
                  'Solo se muestran los primeros 201 detalles. Consulta BD para revisar el resto.',
                ),
              ...details.map(
                (d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (d['productos'] as Map?)?['nombre']?.toString() ??
                            'Producto sin nombre disponible (ID ${_text(d['producto_id'])})',
                      ),
                      field(
                        'Cantidad: ${_text(d['cantidad'])}',
                        'Precio unitario: ${_money(d['precio_unitario'])}',
                      ),
                      field(
                        'Importe',
                        d['cantidad'] is num && d['precio_unitario'] is num
                            ? _money(
                                (d['cantidad'] as num) *
                                    (d['precio_unitario'] as num),
                              )
                            : 'No disponible',
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              field('Subtotal', _money(sale['subtotal'])),
              field('Descuento', _money(sale['descuento'])),
              field('Código aplicado', _text(sale['codigo_descuento'])),
              field('IVA registrado', _money(sale['iva'])),
              field(
                'Tasa de IVA',
                sale['tasa_iva'] is num
                    ? '${((sale['tasa_iva'] as num) * 100).toStringAsFixed(2)} %'
                    : 'No disponible',
              ),
              field(
                'IVA incluido',
                sale['iva_incluido'] == null
                    ? 'No disponible'
                    : sale['iva_incluido'] == true
                    ? 'Sí'
                    : 'No',
              ),
              field('Total', _money(sale['total'])),
              const SizedBox(height: 12),
              const Text(
                'Información almacenada en Supabase. Los nombres de extras y personalizaciones no se guardan aquí; su precio puede estar incluido en el precio unitario. No se reconstruye el ticket local ni se recalculan impuestos.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
