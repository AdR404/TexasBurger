import 'package:flutter/material.dart';
import '../models/venta_item.dart';
import '../services/discount_code_service.dart';
import '../services/pricing_service.dart';
import '../theme/app_theme.dart';
import 'payment_selector.dart';

class CartBottomSheet extends StatefulWidget {
  final List<VentaItem> cartItems;
  final Function(String productId) onIncrement;
  final Function(String productId) onDecrement;
  final Function(String productId) onRemove;
  final VoidCallback onClear;
  final String? initialCouponCode;
  final ValueChanged<String?>? onCouponChanged;
  final Function({
    required String paymentMethod,
    required double cashGiven,
    required double changeReturned,
    required PricingCalculation calc,
    required String orderType,
    String? tableNumber,
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
  }) onConfirmSale;

  const CartBottomSheet({
    super.key,
    required this.cartItems,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onClear,
    required this.onConfirmSale,
    this.initialCouponCode,
    this.onCouponChanged,
  });

  @override
  State<CartBottomSheet> createState() => _CartBottomSheetState();
}

class _CartBottomSheetState extends State<CartBottomSheet> {
  String _paymentMethod = 'Efectivo';
  double _cashGiven = 0.0;
  double _changeReturned = 0.0;

  String _orderType = 'Comer aquí'; // 'Comer aquí', 'Para llevar', 'A domicilio'
  final TextEditingController _tableController = TextEditingController(text: 'Mesa 1');
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _discountCodeController = TextEditingController();
  final DiscountCodeService _discounts = DiscountCodeService();
  String? _appliedCode;

  @override
  void initState() {
    super.initState();
    _appliedCode = widget.initialCouponCode;
    _discountCodeController.text = _appliedCode ?? '';
    _discounts.addListener(_onDiscountChanged);
  }

  void _onDiscountChanged() {
    if (mounted) setState(() {});
  }

  void _setCoupon(String? code) {
    setState(() => _appliedCode = code);
    widget.onCouponChanged?.call(code);
  }

  PricingCalculation _calculate() => PricingService.calculate(
    items: widget.cartItems,
    coupon: _appliedCode == null ? null : _discounts.findActive(_appliedCode!),
  );

  @override
  void dispose() {
    _discounts.removeListener(_onDiscountChanged);
    _discountCodeController.dispose();
    _tableController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calc = _calculate();

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Orden (${widget.cartItems.fold<int>(0, (sum, i) => sum + i.quantity)})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navyBlue,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: widget.onClear,
                  child: const Text('Vaciar', style: TextStyle(color: AppTheme.danger)),
                ),
              ],
            ),
            const Divider(),

            // Modalidad de Pedido
            const Text(
              'Modalidad de pedido:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.navyBlue),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.restaurant, size: 16),
                    label: const Text('Comer aquí'),
                    selected: _orderType == 'Comer aquí',
                    selectedColor: AppTheme.navyBlue,
                    labelStyle: TextStyle(
                      color: _orderType == 'Comer aquí' ? Colors.white : AppTheme.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (val) => setState(() => _orderType = 'Comer aquí'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.shopping_bag, size: 16),
                    label: const Text('Para llevar'),
                    selected: _orderType == 'Para llevar',
                    selectedColor: AppTheme.navyBlue,
                    labelStyle: TextStyle(
                      color: _orderType == 'Para llevar' ? Colors.white : AppTheme.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (val) => setState(() => _orderType = 'Para llevar'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.delivery_dining, size: 16),
                    label: const Text('A domicilio'),
                    selected: _orderType == 'A domicilio',
                    selectedColor: AppTheme.navyBlue,
                    labelStyle: TextStyle(
                      color: _orderType == 'A domicilio' ? Colors.white : AppTheme.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (val) => setState(() => _orderType = 'A domicilio'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Order Mode specific inputs
            if (_orderType == 'Comer aquí') ...[
              TextField(
                controller: _tableController,
                decoration: InputDecoration(
                  labelText: 'Número o nombre de mesa',
                  prefixIcon: const Icon(Icons.table_restaurant_outlined, size: 20),
                  filled: true,
                  fillColor: AppTheme.creamBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ] else if (_orderType == 'Para llevar') ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nombre del cliente',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  filled: true,
                  fillColor: AppTheme.creamBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ] else if (_orderType == 'A domicilio') ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nombre del cliente',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  filled: true,
                  fillColor: AppTheme.creamBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Teléfono',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        filled: true,
                        fillColor: AppTheme.creamBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _addressController,
                      decoration: InputDecoration(
                        labelText: 'Dirección / Colonia',
                        prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                        filled: true,
                        fillColor: AppTheme.creamBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),
            const Divider(),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _discountCodeController,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) { if (_appliedCode != null) _setCoupon(null); },
                    decoration: const InputDecoration(
                      labelText: 'Código de descuento', isDense: true,
                      prefixIcon: Icon(Icons.local_offer_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    final code = _discounts.findActive(_discountCodeController.text);
                    _setCoupon(code?.code);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(code == null ? 'Código inválido o inactivo.' : 'Código ${code.code} aplicado.'),
                    ));
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            ),
            if (_appliedCode != null)
              TextButton(
                onPressed: () { _discountCodeController.clear(); _setCoupon(null); },
                child: const Text('Quitar código'),
              ),
            if (_appliedCode != null && calc.discountCode == null)
              const Text('El código ya no está disponible. Revisa el total.', style: TextStyle(color: AppTheme.danger)),
            const SizedBox(height: 10),

            // Items List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.cartItems.length,
              separatorBuilder: (context, index) => const Divider(height: 10),
              itemBuilder: (context, index) {
                final item = widget.cartItems[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (item.customizationSummary.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.customizationSummary,
                              style: const TextStyle(color: AppTheme.infoBlue, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                          Text(
                            '\$${item.unitPrice.toStringAsFixed(2)} c/u',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primary, size: 20),
                          onPressed: () => widget.onDecrement(item.product.id),
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${item.quantity}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 20),
                          onPressed: () => widget.onIncrement(item.product.id),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 56),
                      child: Text(
                        '\$${item.subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 10),
            const Divider(),

            PaymentSelector(
              totalAmount: calc.total,
              onMethodChanged: (method) => setState(() => _paymentMethod = method),
              onCashTenderedChanged: (val) => _cashGiven = val,
              onChangeChanged: (val) => _changeReturned = val,
            ),

            const SizedBox(height: 12),

            _summaryRow('Subtotal:', calc.subtotal),
            const SizedBox(height: 5),
            if (calc.discount > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(calc.discountReason ?? 'Descuento aplicado:', style: const TextStyle(color: AppTheme.promo, fontWeight: FontWeight.w600))),
                  Text('-\$${calc.discount.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.promo, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
            ],
            _summaryRow('Base sin IVA:', calc.taxableSubtotal),
            _summaryRow('IVA incluido (${(calc.ivaRate * 100).toStringAsFixed(0)}%):', calc.iva),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total a cobrar:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
                ),
                Text(
                  '\$${calc.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.primary),
                ),
              ],
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  final current = _calculate();
                  if (current.total != calc.total || current.discountCode != calc.discountCode) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El descuento cambió. Revisa el total antes de cobrar.')));
                    return;
                  }
                  widget.onConfirmSale(
                    paymentMethod: _paymentMethod,
                    cashGiven: _cashGiven,
                    changeReturned: _changeReturned,
                    calc: current,
                    orderType: _orderType,
                    tableNumber: _orderType == 'Comer aquí' ? _tableController.text.trim() : null,
                    customerName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : null,
                    customerPhone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
                    deliveryAddress: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
                  );
                },
                icon: const Icon(Icons.check_circle_rounded, size: 22),
                label: Text(
                  'Cobrar \$${calc.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  elevation: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double amount) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textMuted))),
      Text('\$${amount.toStringAsFixed(2)}'),
    ],
  );
}
