import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PaymentSelector extends StatefulWidget {
  final double totalAmount;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<double> onCashTenderedChanged;
  final ValueChanged<double> onChangeChanged;

  const PaymentSelector({
    super.key,
    required this.totalAmount,
    required this.onMethodChanged,
    required this.onCashTenderedChanged,
    required this.onChangeChanged,
  });

  @override
  State<PaymentSelector> createState() => _PaymentSelectorState();
}

class _PaymentSelectorState extends State<PaymentSelector> {
  String _selectedMethod = 'Efectivo';
  final TextEditingController _cashController = TextEditingController();
  double _cashTendered = 0.0;
  double _change = 0.0;

  @override
  void initState() {
    super.initState();
    _cashTendered = widget.totalAmount;
    _cashController.text = widget.totalAmount.toStringAsFixed(0);
    _calculateChange();
  }

  @override
  void didUpdateWidget(covariant PaymentSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalAmount != widget.totalAmount) {
      if (_cashTendered < widget.totalAmount) {
        _cashTendered = widget.totalAmount;
        _cashController.text = widget.totalAmount.toStringAsFixed(0);
      }
      _calculateChange();
    }
  }

  void _calculateChange() {
    _change = (_cashTendered - widget.totalAmount).clamp(0.0, double.infinity);
    widget.onCashTenderedChanged(_cashTendered);
    widget.onChangeChanged(_change);
  }

  void _selectMethod(String method) {
    setState(() {
      _selectedMethod = method;
    });
    widget.onMethodChanged(method);
  }

  void _setCash(double amount) {
    setState(() {
      _cashTendered = amount;
      _cashController.text = amount.toStringAsFixed(0);
      _calculateChange();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Método de Pago',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.navyBlue,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildMethodOption('Efectivo', Icons.money_rounded),
            const SizedBox(width: 8),
            _buildMethodOption('Tarjeta', Icons.credit_card_rounded),
            const SizedBox(width: 8),
            _buildMethodOption('Transferencia', Icons.account_balance_rounded),
          ],
        ),
        if (_selectedMethod == 'Efectivo') ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _cashController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Paga con (\$)',
                    prefixText: '\$ ',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryRed, width: 2),
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val) ?? 0.0;
                    setState(() {
                      _cashTendered = parsed;
                      _calculateChange();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _change > 0 ? const Color(0xFFECFDF5) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _change > 0 ? AppTheme.successGreen : AppTheme.borderLight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cambio',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        '\$ ${_change.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _change > 0 ? AppTheme.successGreen : AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _buildQuickCashChip('Exacto', widget.totalAmount),
              if (widget.totalAmount < 100) _buildQuickCashChip('\$100', 100),
              if (widget.totalAmount < 200) _buildQuickCashChip('\$200', 200),
              if (widget.totalAmount < 500) _buildQuickCashChip('\$500', 500),
              if (widget.totalAmount < 1000) _buildQuickCashChip('\$1000', 1000),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMethodOption(String title, IconData icon) {
    final isSelected = _selectedMethod == title;
    return Expanded(
      child: InkWell(
        onTap: () => _selectMethod(title),
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryRed : Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? AppTheme.primaryRed : Colors.white,
              width: 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryRed.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : AppTheme.navyBlue,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.navyBlue,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickCashChip(String label, double amount) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.navyBlue),
      ),
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppTheme.gold, width: 1.2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onPressed: () => _setCash(amount),
    );
  }
}