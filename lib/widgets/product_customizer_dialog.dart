import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../models/producto_extra.dart';
import '../models/venta_item.dart';
import '../theme/app_theme.dart';

class ProductCustomizerDialog extends StatefulWidget {
  final Producto product;
  final VentaItem? initialItem;

  const ProductCustomizerDialog({
    super.key,
    required this.product,
    this.initialItem,
  });

  @override
  State<ProductCustomizerDialog> createState() => _ProductCustomizerDialogState();
}

class _ProductCustomizerDialogState extends State<ProductCustomizerDialog> {
  late int _quantity;
  final List<ProductoExtra> _selectedExtras = [];
  final List<String> _removedIngredients = [];
  final TextEditingController _notesController = TextEditingController();

  final List<String> _commonExclusions = [
    'Sin cebolla',
    'Sin pepinillos',
    'Sin tomate',
    'Sin mayonesa',
    'Sin mostaza',
    'Sin aguacate',
    'Salsas aparte',
  ];

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialItem?.quantity ?? 1;
    if (widget.initialItem != null) {
      _selectedExtras.addAll(widget.initialItem!.selectedExtras);
      _removedIngredients.addAll(widget.initialItem!.removedIngredients);
      _notesController.text = widget.initialItem!.notes;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double get _extrasTotal =>
      _selectedExtras.fold(0.0, (sum, extra) => sum + extra.price);

  double get _unitPrice => widget.product.price + _extrasTotal;

  double get _totalPrice => _unitPrice * _quantity;

  @override
  Widget build(BuildContext context) {
    final availableExtras = widget.product.availableExtras;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navyBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Precio base: \$${widget.product.price.toStringAsFixed(2)} MXN',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 20),

            // Scrollable Options
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Extras Section
                    if (availableExtras.isNotEmpty) ...[
                      const Row(
                        children: [
                          Icon(Icons.add_circle_outline, size: 18, color: AppTheme.navyBlue),
                          SizedBox(width: 6),
                          Text(
                            'Ingredientes extras (opcional):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.navyBlue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...availableExtras.map((extra) {
                        final isSelected = _selectedExtras.any((e) => e.id == extra.id);
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(extra.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('+ \$${extra.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                          value: isSelected,
                          activeColor: AppTheme.primary,
                          onChanged: (bool? checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedExtras.add(extra);
                              } else {
                                _selectedExtras.removeWhere((e) => e.id == extra.id);
                              }
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 12),
                    ],

                    // Exclusions Section (Hamburguesas)
                    if (widget.product.category == 'Hamburguesas' || widget.product.isPromo) ...[
                      const Row(
                        children: [
                          Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.primary),
                          SizedBox(width: 6),
                          Text(
                            'Quitar ingredientes / preparación:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.navyBlue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _commonExclusions.map((exclusion) {
                          final isRemoved = _removedIngredients.contains(exclusion);
                          return FilterChip(
                            label: Text(exclusion, style: TextStyle(fontSize: 12, color: isRemoved ? Colors.white : AppTheme.textDark)),
                            selected: isRemoved,
                            selectedColor: AppTheme.primary,
                            checkmarkColor: Colors.white,
                            backgroundColor: AppTheme.creamBg,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _removedIngredients.add(exclusion);
                                } else {
                                  _removedIngredients.remove(exclusion);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Custom Note
                    const Text(
                      'Instrucciones o nota adicional:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.navyBlue),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        hintText: 'Ej. Término bien cocido, sin salsa, etc.',
                        hintStyle: const TextStyle(fontSize: 12),
                        filled: true,
                        fillColor: AppTheme.creamBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quantity Control
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Cantidad:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.navyBlue),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                              icon: const Icon(Icons.remove_circle_outline),
                              color: AppTheme.primary,
                            ),
                            Text(
                              '$_quantity',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _quantity++),
                              icon: const Icon(Icons.add_circle_outline),
                              color: AppTheme.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 20),

            // Footer Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final item = VentaItem(
                    product: widget.product,
                    quantity: _quantity,
                    unitPrice: _unitPrice,
                    selectedExtras: List.from(_selectedExtras),
                    removedIngredients: List.from(_removedIngredients),
                    notes: _notesController.text.trim(),
                  );
                  Navigator.of(context).pop(item);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Agregar • \$${_totalPrice.toStringAsFixed(2)} MXN',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
