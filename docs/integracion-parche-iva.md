# Integración de cupones y desglose de IVA

Parche original: `0001-feat-add-subtotal-tax-and-discount-breakdown.patch`.
Rama autorizada: `back/DANR/parche-iva`.

## Regla confirmada el 26 de octubre de 2026

El responsable del proyecto confirmó: **los precios ya incluyen IVA del 16%**.
Se descarta el recargo automático del parche. El subtotal sigue siendo la suma
de precios publicados por cantidades, incluidos extras. Primero se aplica la
promoción existente del martes; después, un único cupón sobre el importe restante.
Los cupones admiten porcentaje o cantidad fija y nunca descuentan más del saldo.
Se mantiene la acumulación de promoción y cupón propuesta por el parche.

- Total = subtotal menos descuentos; no se vuelve a sumar el IVA.
- Base sin IVA = total / 1.16, redondeada a centavos.
- IVA incluido = total menos base, redondeado a centavos.
- Ejemplo: $116 menos un cupón del 10% = $104.40; base $90, IVA $14.40.
- La promoción de dos clásicas conserva $192 - $42 = $150; base $129.31,
  IVA $20.69. No se cambian los precios del catálogo.

No quedan pruebas bloqueadas por la definición de IVA. No se implementa la
variante de sumar IVA al precio porque contradice la regla confirmada.

## Compatibilidad e integración

- Se preservan empleados, sucursales, roles, navegación, imágenes y caja.
- El subtotal ya existía en tickets; se reutiliza sin duplicarlo.
- `Venta` conserva `iva`, `ivaRate`, `ivaIncluded` y `discountCode` cuando existen.
  Los campos ausentes siguen siendo nulos y no se inventa desglose histórico.
  `taxableSubtotal` se obtiene del total y del IVA guardados, nunca de la tasa actual.
- Los tickets anteriores muestran IVA no registrado, manteniendo sus importes.
- CSV conserva las 17 columnas existentes y añade `Codigo_Descuento`, `IVA`,
  `Tasa_IVA`, `IVA_Incluido` y `Base_Sin_IVA`. Se escapan comillas de los códigos.
- Los cupones se guardan únicamente en `texas_discount_codes`. El servicio no
  borra otras preferencias; ante errores de lectura conserva el contenido original
  y bloquea su modificación. La carga fallida de cupones no bloquea el arranque.
- Crear, reemplazar, activar, desactivar y eliminar cupones requiere administrador
  local. El carrito permite usarlos, quitarlos y recalcularlos al cambiar cantidades;
  verifica disponibilidad nuevamente al cobrar. No son permisos de autenticación remota.
- Se conserva `shared_preferences_android 2.5.3`, sin cambios de dependencias,
  Gradle 8.14.3, AGP 8.11.1 o Kotlin 2.2.20.

## Diferencias frente al parche original

El parche no aplica directamente sobre siete archivos evolucionados de esta rama.
Se adaptaron los cambios en lugar de reemplazar esos archivos. Se recuperaron sus
tres archivos nuevos, agregando validaciones, protección por rol y manejo de errores.
Se mantiene la paleta azul y `displayName`. Se rechazan las eliminaciones de
`DbService.init()` y del envío remoto; tampoco se incrementan los datos de ejemplo
por 1.16 ni se asigna una tasa por defecto a ventas antiguas.

## Supabase pendiente

`main.dart` sigue llamando `DbService.init()`. `SalesService` conserva el escritor
por defecto `DbService.guardarVenta` y lo invoca al registrar la venta local.
Las pruebas usan un escritor simulado: no insertan ventas en Supabase.

El escritor remoto existente aún envía solo sus columnas anteriores: usuario,
fecha/hora, total, método de pago y detalles. Los nuevos campos fiscales/cupones
y el contexto local de personal no se incorporan al payload en esta integración.
La conexión activa no demuestra que ya existan columnas, permisos o políticas.

Antes de conectarlos: revisar el esquema real y sus permisos, acordar nombres y
tipos para subtotal, descuento, IVA incluido, tasa, base y código, definir si los
cupones serán compartidos entre dispositivos, verificar usuario/empleado/sucursal
y adaptar el escritor remoto con pruebas de integración autorizadas. Cualquier
cambio de BD requiere revisión posterior; aquí no se ejecuta ni modifica SQL.

## Validación

`flutter analyze --no-pub`: sin incidencias. `flutter test --no-pub --reporter expanded`:
36 pruebas aprobadas (24 existentes y 12 nuevas). `git diff --check`: correcto.
Las pruebas cubren
IVA incluido y redondeo, descuentos, promoción más cupón, permisos, persistencia,
compatibilidad histórica, CSV, tickets, carrito y conservación del envío remoto.
La suite existente comprueba navegación por roles, imágenes, personal y caja.
No se generó APK ni se probaron dispositivos físicos en esta integración.
No se ejecutaron ventas reales, SQL, commits, push ni merge.

## Archivos de esta integración

| Archivo | Cambio |
| --- | --- |
| `lib/main.dart` | Inicializa cupones y conserva inicialización de BD. |
| `lib/models/discount_code.dart` (nuevo) | Modelo y validación de cupones. |
| `lib/models/venta.dart` | Campos fiscales opcionales compatibles con ventas antiguas. |
| `lib/services/discount_code_service.dart` (nuevo) | Persistencia local y permisos administrativos. |
| `lib/services/pricing_service.dart` | Descuentos y desglose del IVA incluido. |
| `lib/services/sales_service.dart` | Guarda los nuevos campos sin retirar el escritor remoto. |
| `lib/services/export_service.dart` | Cinco columnas adicionales en CSV. |
| `lib/screens/quick_sale_screen.dart` | Conserva cupón en el carrito y registra campos fiscales. |
| `lib/screens/settings_screen.dart` | Acceso administrativo a cupones. |
| `lib/widgets/discount_codes_dialog.dart` (nuevo) | Administración protegida de cupones. |
| `lib/widgets/cart_bottom_sheet.dart` | Aplicar/quitar cupón y desglose del cobro. |
| `lib/widgets/payment_selector.dart` | Presenta efectivo con centavos y libera el controlador. |
| `lib/widgets/ticket_dialog.dart` | Desglose fiscal visible y copiable. |
| `test/discount_integration_test.dart` (nuevo) | Ocho pruebas de cálculo, persistencia y compatibilidad. |
| `test/discount_widgets_test.dart` (nuevo) | Cuatro pruebas de administración, carrito y tickets. |
| `test/staff_widgets_test.dart` | Ajusta expectativa del ticket histórico: IVA no registrado. |
| `docs/integracion-parche-iva.md` (nuevo) | Decisiones, alcance, validación y pendientes. |

El parche original ya estaba como archivo no rastreado y se conservó intacto.
No se modificaron `pubspec.yaml`, `pubspec.lock`, `android/` ni `db_service.dart`.
