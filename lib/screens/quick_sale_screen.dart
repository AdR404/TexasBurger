import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../models/venta_item.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../services/caja_service.dart';
import '../services/pricing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/promo_badge.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/ticket_dialog.dart';
import '../widgets/product_customizer_dialog.dart';
import '../widgets/staff_context_selector.dart';

class QuickSaleScreen extends StatefulWidget {
  const QuickSaleScreen({super.key});

  @override
  State<QuickSaleScreen> createState() => _QuickSaleScreenState();
}

class _QuickSaleScreenState extends State<QuickSaleScreen> {
  final ProductService _productService = ProductService();
  final SalesService _salesService = SalesService();

  String _selectedCategory = 'Todas';
  String _searchQuery = '';
  final List<VentaItem> _cartItems = [];

  @override
  void initState() {
    super.initState();
    _productService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _productService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _addToCart(Producto product) {
    setState(() {
      final index = _cartItems.indexWhere(
        (item) => item.product.id == product.id && item.selectedExtras.isEmpty && item.removedIngredients.isEmpty && item.notes.isEmpty,
      );
      if (index != -1) {
        _cartItems[index].quantity++;
      } else {
        _cartItems.add(VentaItem(product: product, quantity: 1, unitPrice: product.price));
      }
    });
  }

  Future<void> _openCustomizer(Producto product) async {
    final customItem = await showDialog<VentaItem>(
      context: context,
      builder: (ctx) => ProductCustomizerDialog(product: product),
    );

    if (customItem != null) {
      setState(() {
        _cartItems.add(customItem);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${customItem.quantity}x ${product.name} personalizado agregado a la orden.'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'Ver Orden',
              textColor: AppTheme.gold,
              onPressed: _openCartBottomSheet,
            ),
          ),
        );
      }
    }
  }

  void _incrementCart(String productId) {
    setState(() {
      final index = _cartItems.indexWhere((item) => item.product.id == productId);
      if (index != -1) {
        _cartItems[index].quantity++;
      }
    });
  }

  void _decrementCart(String productId) {
    setState(() {
      final index = _cartItems.indexWhere((item) => item.product.id == productId);
      if (index != -1) {
        if (_cartItems[index].quantity > 1) {
          _cartItems[index].quantity--;
        } else {
          _cartItems.removeAt(index);
        }
      }
    });
  }

  void _removeFromCart(String productId) {
    setState(() {
      _cartItems.removeWhere((item) => item.product.id == productId);
    });
  }

  void _clearCart() {
    setState(() {
      _cartItems.clear();
    });
  }

  int _getCartQuantity(String productId) {
    return _cartItems
        .where((i) => i.product.id == productId)
        .fold<int>(0, (sum, i) => sum + i.quantity);
  }

  Future<void> _openCartBottomSheet() async {
    if (_cartItems.isEmpty) return;
    final caja = CajaService();
    if (caja.saleContext == null) {
      final selected = await selectStaffContext(context, caja);
      if (!selected || !mounted) return;
    }
    final saleContext = caja.saleContext!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CartBottomSheet(
        cartItems: _cartItems,
        onIncrement: (id) {
          _incrementCart(id);
          Navigator.pop(ctx);
          _openCartBottomSheet();
        },
        onDecrement: (id) {
          _decrementCart(id);
          Navigator.pop(ctx);
          if (_cartItems.isNotEmpty) {
            _openCartBottomSheet();
          }
        },
        onRemove: (id) {
          _removeFromCart(id);
          Navigator.pop(ctx);
          if (_cartItems.isNotEmpty) {
            _openCartBottomSheet();
          }
        },
        onClear: () {
          _clearCart();
          Navigator.pop(ctx);
        },
        onConfirmSale: ({
          required paymentMethod,
          required cashGiven,
          required changeReturned,
          required calc,
          required orderType,
          tableNumber,
          customerName,
          customerPhone,
          deliveryAddress,
        }) async {
          Navigator.pop(ctx);
          final sale = await _salesService.registerSale(
            saleContext: saleContext,
            items: _cartItems,
            subtotal: calc.subtotal,
            discount: calc.discount,
            total: calc.total,
            paymentMethod: paymentMethod,
            cashGiven: cashGiven,
            changeReturned: changeReturned,
            orderType: orderType,
            tableNumber: tableNumber,
            customerName: customerName,
            customerPhone: customerPhone,
            deliveryAddress: deliveryAddress,
          );
          _clearCart();

          if (mounted) {
            showDialog(
              context: context,
              builder: (dCtx) => TicketDialog(venta: sale),
            );
          }
        },
      ),
    );
  }

  IconData _getCategoryIcon(String category, bool isPromo) {
    if (isPromo) return Icons.star_rate_rounded;
    switch (category) {
      case 'Hamburguesas':
        return Icons.lunch_dining_rounded;
      case 'Complementos':
        return Icons.fastfood_rounded;
      case 'Bebidas':
        return Icons.local_drink_rounded;
      case 'Promociones':
        return Icons.local_offer_rounded;
      default:
        return Icons.restaurant_menu;
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _productService.availableProducts;
    final filtered = products.where((p) {
      if (_selectedCategory == 'Promociones' && !p.isPromo) return false;
      if (_selectedCategory == 'Hamburguesas' && (p.category != 'Hamburguesas' || p.isPromo)) return false;
      if (_selectedCategory == 'Complementos' && p.category != 'Complementos') return false;
      if (_selectedCategory == 'Bebidas' && p.category != 'Bebidas') return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return p.name.toLowerCase().contains(query) || p.description.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    final calc = PricingService.calculate(items: _cartItems);
    final totalItems = _cartItems.fold<int>(0, (sum, i) => sum + i.quantity);

    return Scaffold(
      backgroundColor: AppTheme.creamBg,
      body: Column(
        children: [
          Container(
            color: AppTheme.creamBg,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                const StaffContextBar(),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Buscar hamburguesa, papas, bebida...',
                    prefixIcon: const Icon(Icons.search, color: AppTheme.navyBlue),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('Todas', Icons.restaurant_menu),
                      const SizedBox(width: 8),
                      _buildCategoryChip('Hamburguesas', Icons.lunch_dining),
                      const SizedBox(width: 8),
                      _buildCategoryChip('Complementos', Icons.fastfood),
                      const SizedBox(width: 8),
                      _buildCategoryChip('Bebidas', Icons.local_drink),
                      const SizedBox(width: 8),
                      _buildCategoryChip('Promociones', Icons.local_offer),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No se encontraron productos',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 15),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = filtered[index];
                      final inCartCount = _getCartQuantity(product.id);
                      final icon = _getCategoryIcon(product.category, product.isPromo);

                      return Card(
                        margin: EdgeInsets.zero,
                        color: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppTheme.infoSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  icon,
                                  color: product.isPromo ? AppTheme.promo : AppTheme.navyBlue,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (product.isPromo) ...[
                                      PromoBadge(text: product.promoNote ?? 'PROMOCIÓN'),
                                      const SizedBox(height: 4),
                                    ],
                                    Text(
                                      product.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      product.description,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '\$${product.price.toStringAsFixed(2)} MXN',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.navyBlue,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (product.availableExtras.isNotEmpty || product.category == 'Hamburguesas') ...[
                                          const SizedBox(width: 4),
                                          InkWell(
                                            onTap: () => _openCustomizer(product),
                                            borderRadius: BorderRadius.circular(6),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.tune, size: 14, color: AppTheme.navyBlue),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Personalizar',
                                                    style: TextStyle(fontSize: 11, color: AppTheme.navyBlue, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (inCartCount == 0)
                                ElevatedButton(
                                  onPressed: () => _addToCart(product),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(36, 36),
                                    fixedSize: const Size(36, 36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Icon(Icons.add, size: 20),
                                )
                              else
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Material(
                                      color: AppTheme.infoSoft,
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        onTap: () => _decrementCart(product.id),
                                        borderRadius: BorderRadius.circular(10),
                                        child: const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: Icon(Icons.remove, size: 18, color: AppTheme.navyBlue),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        '$inCartCount',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                    ),
                                    Material(
                                      color: AppTheme.primary,
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        onTap: () => _incrementCart(product.id),
                                        borderRadius: BorderRadius.circular(10),
                                        child: const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: Icon(Icons.add, size: 18, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomSheet: totalItems > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.navyBlue,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$totalItems',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total de la Orden',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            '\$${calc.total.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _openCartBottomSheet,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('Ver Orden'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildCategoryChip(String label, IconData icon) {
    final isSelected = _selectedCategory == label;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : AppTheme.navyBlue,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textDark,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 13,
        ),
      ),
      selectedColor: AppTheme.navyBlue,
      backgroundColor: Colors.white,
      elevation: isSelected ? 2 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(
          color: isSelected ? AppTheme.navyBlue : Colors.white,
        ),
      ),
      onSelected: (val) {
        setState(() {
          _selectedCategory = label;
        });
      },
    );
  }
}
