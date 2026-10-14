import 'package:flutter/material.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../services/user_role_service.dart';
import '../theme/app_theme.dart';
import '../models/producto.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ProductService _productService = ProductService();
  final SalesService _salesService = SalesService();
  final UserRoleService _roleService = UserRoleService();

  @override
  void initState() {
    super.initState();
    _productService.addListener(_onUpdate);
    _roleService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _productService.removeListener(_onUpdate);
    _roleService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _showEditPriceDialog(Producto p) {
    if (!_roleService.isAdmin) {
      _showRestrictedNotice('Solo los administradores pueden modificar precios.');
      return;
    }

    final controller = TextEditingController(text: p.price.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Modificar Precio: ${p.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Precio (\$ MXN)',
            prefixText: '\$ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final newPrice = double.tryParse(controller.text);
              if (newPrice != null && newPrice > 0) {
                _productService.updatePrice(p.id, newPrice);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showAddProductOrPromoDialog() {
    if (!_roleService.isAdmin) {
      _showRestrictedNotice('Solo los administradores pueden añadir productos o promociones.');
      return;
    }

    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final descController = TextEditingController();
    final promoNoteController = TextEditingController();
    String category = 'Hamburguesas';
    bool isPromo = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                isPromo ? Icons.star_rate_rounded : Icons.add_circle_outline,
                color: AppTheme.primaryRed,
              ),
              const SizedBox(width: 8),
              Text(
                isPromo ? 'Nueva Promoción' : 'Nuevo Producto',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del producto o promo',
                    hintText: 'Ej. Texas Mega Bacon',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Precio (\$ MXN)',
                          prefixText: '\$ ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        items: const [
                          DropdownMenuItem(value: 'Hamburguesas', child: Text('Hamburguesas', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'Complementos', child: Text('Complementos', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'Bebidas', child: Text('Bebidas', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'Promociones', child: Text('Promociones', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              category = val;
                              if (val == 'Promociones') {
                                isPromo = true;
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    hintText: 'Ingredientes o descripción breve',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '¿Es una promoción especial?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  value: isPromo,
                  activeThumbColor: AppTheme.primaryRed,
                  onChanged: (val) {
                    setDialogState(() {
                      isPromo = val;
                      if (isPromo && category != 'Promociones') {
                        category = 'Promociones';
                      }
                    });
                  },
                ),
                if (isPromo) ...[
                  TextField(
                    controller: promoNoteController,
                    decoration: const InputDecoration(
                      labelText: 'Nota de la promoción',
                      hintText: 'Ej. 2x1 los martes o combo especial',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final price = double.tryParse(priceController.text.trim());
                if (name.isEmpty || price == null || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Por favor completa un nombre y precio válido.')),
                  );
                  return;
                }

                final newProd = Producto(
                  id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  description: descController.text.trim(),
                  price: price,
                  category: category,
                  isPromo: isPromo,
                  promoNote: isPromo
                      ? (promoNoteController.text.trim().isNotEmpty
                          ? promoNoteController.text.trim()
                          : 'Promoción')
                      : null,
                  isAvailable: true,
                );

                _productService.addProduct(newProd);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.navyBlue,
                    content: Text('¡${isPromo ? "Promoción" : "Producto"} "$name" creado correctamente!'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRestrictedNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.blueGrey.shade800,
        content: Row(
          children: [
            const Icon(Icons.lock_outline, color: AppTheme.gold, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _productService.products;
    final isAdmin = _roleService.isAdmin;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner de Rol Activo
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isAdmin
                    ? AppTheme.gold.withValues(alpha: 0.15)
                    : Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isAdmin ? AppTheme.gold : Colors.blueGrey.shade200,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isAdmin ? Icons.admin_panel_settings : Icons.lock_outline,
                    color: isAdmin ? AppTheme.navyBlue : AppTheme.navyBlue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAdmin
                              ? 'Modo Administrador Activo'
                              : 'Modo Usuario (Solo Lectura del Menú)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.navyBlue,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAdmin
                              ? 'Tienes permisos para modificar precios, agregar productos y crear promociones.'
                              : 'Solo consulta. Para modificar precios o agregar promociones/productos, ingresa con el botón superior.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isAdmin ? AppTheme.navyBlue : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tarjeta de la marca
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: AppTheme.gold, width: 2),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.lunch_dining,
                          color: AppTheme.primaryRed,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TEXAS BURGER',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.navyBlue,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Deliciosamente asadas al carbón',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.primaryRed,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'EST. 1995 • Sistema Punto de Venta',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Encabezado del catálogo con acción para Admin
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isAdmin
                        ? 'Administración del Menú y Precios'
                        : 'Catálogo del Menú (Precios Vigentes)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.navyBlue,
                    ),
                  ),
                ),
                if (isAdmin)
                  FilledButton.icon(
                    onPressed: _showAddProductOrPromoDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Añadir Item / Promo',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryRed,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Lista de productos
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = products[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: p.isPromo ? AppTheme.lightRed : AppTheme.creamBg,
                      child: Icon(
                        p.isPromo
                            ? Icons.star_rate_rounded
                            : p.category == 'Complementos'
                                ? Icons.fastfood_rounded
                                : p.category == 'Bebidas'
                                    ? Icons.local_drink_rounded
                                    : Icons.lunch_dining_rounded,
                        color: p.isPromo ? AppTheme.primaryRed : AppTheme.navyBlue,
                        size: 20,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        if (p.isPromo)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.lightRed,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'PROMO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryRed,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '\$${p.price.toStringAsFixed(2)} MXN • ${p.category}',
                      style: const TextStyle(
                        color: AppTheme.primaryRed,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    trailing: isAdmin
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.navyBlue),
                                onPressed: () => _showEditPriceDialog(p),
                                tooltip: 'Editar precio',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              ),
                              Switch(
                                value: p.isAvailable,
                                activeThumbColor: AppTheme.primaryRed,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) => _productService.toggleAvailability(p.id),
                              ),
                            ],
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: p.isAvailable ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              p.isAvailable ? 'Disponible' : 'Agotado',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: p.isAvailable ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                          ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Opciones y Datos: Solo visibles para Admin
            if (isAdmin) ...[
              const Text(
                'Opciones y Datos (Solo Administrador)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_graph_rounded, color: AppTheme.gold),
                        title: const Text('Cargar Ventas de Demostración'),
                        subtitle: const Text('Genera ventas de ejemplo para visualizar el Dashboard'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final scaffold = ScaffoldMessenger.of(context);
                            await _salesService.loadSampleSales(_productService.products);
                            scaffold.showSnackBar(
                              const SnackBar(content: Text('¡Ventas de ejemplo cargadas! Revisa el Dashboard.')),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.navyBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          child: const Text('Cargar', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.refresh_rounded, color: AppTheme.infoBlue),
                        title: const Text('Restablecer Menú Original'),
                        subtitle: const Text('Restaura los 10 productos y precios iniciales'),
                        trailing: OutlinedButton(
                          onPressed: () async {
                            final scaffold = ScaffoldMessenger.of(context);
                            await _productService.resetToDefaults();
                            scaffold.showSnackBar(
                              const SnackBar(content: Text('Menú restaurado a los valores predeterminados.')),
                            );
                          },
                          child: const Text('Restaurar', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text('Limpiar Historial de Ventas'),
                        subtitle: const Text('Elimina todas las ventas guardadas localmente'),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () async {
                            final scaffold = ScaffoldMessenger.of(context);
                            await _salesService.clearAllSales();
                            scaffold.showSnackBar(
                              const SnackBar(content: Text('Historial de ventas vaciado.')),
                            );
                          },
                          child: const Text('Vaciar', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}