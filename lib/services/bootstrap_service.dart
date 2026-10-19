import '../models/producto.dart';
import '../models/producto_extra.dart';

class BootstrapService {
  static List<ProductoExtra> getBurgerExtras() {
    return const [
      ProductoExtra(id: 'ext_queso', name: 'Queso amarillo extra', price: 12.0),
      ProductoExtra(id: 'ext_tocino', name: 'Tocino crujiente extra', price: 18.0),
      ProductoExtra(id: 'ext_carne', name: 'Carne de res extra', price: 32.0),
      ProductoExtra(id: 'ext_aguacate', name: 'Aguacate extra', price: 15.0),
      ProductoExtra(id: 'ext_aderezo', name: 'Aderezo ranch / salsa especial', price: 10.0),
    ];
  }

  static List<ProductoExtra> getFriesExtras() {
    return const [
      ProductoExtra(id: 'ext_cheddar_bacon', name: 'Queso cheddar fundido + tocino', price: 25.0),
      ProductoExtra(id: 'ext_buffalo', name: 'Bañadas en salsa Buffalo', price: 15.0),
      ProductoExtra(id: 'ext_ranch_dip', name: 'Dip de aderezo ranch', price: 10.0),
    ];
  }

  static List<Producto> getDefaultProducts() {
    final burgerExtras = getBurgerExtras();
    final friesExtras = getFriesExtras();

    return [
      // PROMOCIONES
      Producto(
        id: 'promo_martes',
        name: 'Martes: 2 hamburguesas clásicas Texas',
        description: 'El día martes te llevas 2 hamburguesas texanas clásicas en promoción.',
        price: 150.0,
        category: 'Promociones',
        isPromo: true,
        promoNote: 'Válido martes o promo especial',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'combo_pollo_especial',
        name: 'Combo de hamburguesa de pollo',
        description: 'Hamburguesa de pollo + papas a la francesa medianas + refresco de 600 ml.',
        price: 139.0,
        category: 'Promociones',
        isPromo: true,
        promoNote: 'Combo con papas y refresco',
        availableExtras: burgerExtras,
      ),

      // HAMBURGUESAS
      Producto(
        id: 'hamb_pollo_clasica',
        name: 'Hamburguesa de pollo clásica',
        description: 'Hamburguesa de pollo, jamón, salami, queso amarillo, aguacate, pepinillos, cebolla, tomate, lechuga, aderezos.',
        price: 94.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'hamb_texana_clasica',
        name: 'Hamburguesa texana clásica',
        description: 'Hamburguesa de res, jamón, salami, queso amarillo, aguacate, pepinillos, cebolla, tomate, lechuga, aderezos.',
        price: 96.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'hamb_super_texana',
        name: 'Hamburguesa súper texana',
        description: 'Hamburguesa de res, tocino, jamón, salami, queso amarillo, aguacate, pepinillos, cebolla, tomate, lechuga, aderezos.',
        price: 106.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'hamb_super_texana_bbq',
        name: 'Hamburguesa súper texana BBQ',
        description: 'Hamburguesa de res, salsa BBQ, tocino, jamón, salami, queso amarillo, aguacate, pepinillos, cebolla, tomate, lechuga.',
        price: 106.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'hamb_doble',
        name: 'Hamburguesa doble',
        description: 'Hamburguesa de res, 2 carnes, jamón, salami, queso amarillo, aguacate, pepinillos, cebolla, tomate, lechuga, aderezos.',
        price: 114.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'hamb_super_doble',
        name: 'Hamburguesa súper doble',
        description: 'Hamburguesa de res, 2 carnes, tocino, jamón, salami, queso amarillo, aguacate, pepinillos, cebolla, tomate, lechuga, aderezos.',
        price: 124.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'hamb_walter_especial',
        name: 'Hamburguesa Walter especial',
        description: 'Hamburguesa de res, 3 carnes, tocino, 2 jamón, 2 salami, 2 queso amarillo, aguacate, pepinillos, cebolla, tomate, lechuga, aderezos.',
        price: 149.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),
      Producto(
        id: 'hamb_papiburger',
        name: 'Hamburguesa Papiburger',
        description: 'Hamburguesa de res, 1 carne, jamón, salami, queso amarillo, papa francesa, papa crisscut, bañada en salsa buffalo y aderezo ranch.',
        price: 96.0,
        category: 'Hamburguesas',
        availableExtras: burgerExtras,
      ),

      // COMPLEMENTOS
      Producto(
        id: 'comp_papas_francesa',
        name: 'Papas a la francesa',
        description: 'Papas fritas corte clásico, crujientes con sal y sazonador de la casa.',
        price: 45.0,
        category: 'Complementos',
        availableExtras: friesExtras,
      ),
      Producto(
        id: 'comp_papas_crisscut',
        name: 'Papas Crisscut (rejilla)',
        description: 'Papas sazonadas en corte rejilla tipo waffle, súper doradas.',
        price: 55.0,
        category: 'Complementos',
        availableExtras: friesExtras,
      ),
      Producto(
        id: 'comp_papas_especiales',
        name: 'Papas especiales Texas',
        description: 'Orden grande de papas francesas bañadas en queso cheddar fundido y trocitos de tocino.',
        price: 75.0,
        category: 'Complementos',
        availableExtras: friesExtras,
      ),
      Producto(
        id: 'comp_aros_cebolla',
        name: 'Aros de cebolla (8 pzas)',
        description: 'Aros de cebolla rebosados y dorados al punto, acompañados con aderezo ranch.',
        price: 50.0,
        category: 'Complementos',
      ),
      Producto(
        id: 'comp_boneless',
        name: 'Orden de boneless',
        description: 'Trocitos de pechuga de pollo empanizados y bañados en salsa Buffalo o BBQ con aderezo.',
        price: 85.0,
        category: 'Complementos',
      ),

      // BEBIDAS
      Producto(
        id: 'beb_refresco_600',
        name: 'Refresco 600 ml',
        description: 'Coca-Cola regular, Coca-Cola sin azúcar, Joya Manzana, Sprite o Fresca.',
        price: 28.0,
        category: 'Bebidas',
      ),
      Producto(
        id: 'beb_refresco_lata',
        name: 'Refresco en lata 355 ml',
        description: 'Lata fría surtida (Coca-Cola, Sprite, Mundet).',
        price: 22.0,
        category: 'Bebidas',
      ),
      Producto(
        id: 'beb_agua_natural',
        name: 'Agua purificada 600 ml',
        description: 'Botella de agua purificada fresca.',
        price: 18.0,
        category: 'Bebidas',
      ),
      Producto(
        id: 'beb_agua_sabor',
        name: 'Agua Fresca / Té Helado',
        description: 'Vaso de medio litro de agua fresca natural del día o té frío.',
        price: 25.0,
        category: 'Bebidas',
      ),
    ];
  }
}