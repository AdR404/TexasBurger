# Guía de Cupones de Descuento y Desglose de IVA

Documentación de referencia sobre el cálculo de impuestos, promociones y códigos de descuento en el punto de venta.

## Reglas de cálculo (Precios con IVA incluido del 16%)

Los precios del menú ya incluyen el 16% de IVA:

1. **Subtotal:** Suma de los precios de los productos por su cantidad (incluyendo extras seleccionados).
2. **Descuentos:**
   - Primero se calcula la promoción aplicable (por ejemplo, martes 2x$150 en clásicas).
   - Después, si hay un cupón activo en el carrito, se aplica sobre el saldo restante (en porcentaje o monto fijo, sin exceder el total).
3. **Total a cobrar:** `subtotal - descuento`.
4. **Desglose de IVA:**
   - `Base sin IVA = total / 1.16` (redondeado a 2 decimales).
   - `IVA incluido = total - Base sin IVA` (redondeado a 2 decimales).
   - Ejemplo: Una cuenta de `$116.00` con cupón del 10% queda en `$104.40` (`Base sin IVA: $90.00`, `IVA: $14.40`).

## Estructura en el código

| Archivo | Función principal |
| --- | --- |
| `lib/models/discount_code.dart` | Modelo de datos para cupones (porcentaje o monto fijo). |
| `lib/models/venta.dart` | Campos `iva`, `ivaRate`, `ivaIncluded`, `discountCode` y `taxableSubtotal`. |
| `lib/services/discount_code_service.dart` | Guardado local de cupones en `SharedPreferences` (`texas_discount_codes`). |
| `lib/services/pricing_service.dart` | Cálculo de promociones, cupones y desglose de IVA. |
| `lib/services/db_service.dart` | Sincronización de ventas, detalles y desglose hacia Supabase (con opción de pausa local). |
| `lib/widgets/discount_codes_dialog.dart` | Modal de administración de cupones (solo para rol Administrador). |
| `lib/widgets/cart_bottom_sheet.dart` | Aplicación de cupones y resumen de cobro en el carrito. |
| `lib/widgets/ticket_dialog.dart` | Visualización del desglose fiscal en el ticket y copia para WhatsApp. |
| `lib/services/export_service.dart` | Exportación CSV incluyendo columnas de cupón, base sin IVA e IVA. |
