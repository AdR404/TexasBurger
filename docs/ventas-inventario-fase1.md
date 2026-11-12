# Fase 1: identificación de productos

La correspondencia se almacena localmente en SharedPreferences bajo
`texas_product_remote_ids_v1_<projectId>`: ID local estable -> ID entero remoto.
No modifica `texas_products`, los snapshots de tickets, precios, promociones ni
los datos históricos. Los catálogos anteriores no necesitan reescritura.

Antes de insertar una venta online, cada producto sin vínculo se consulta por
nombre exacto. Debe haber una sola fila, activa y con ID positivo. Se conserva
el vínculo antes de enviar la cabecera. Dos IDs locales no pueden apropiarse
silenciosamente del mismo ID remoto. Los alias requieren revisión comercial.
Las siguientes ventas consultan por ID, aunque cambie el nombre local o remoto.
Un ID desaparecido/inactivo no se reasigna por nombre. El fallo bloquea la venta
con un mensaje de revisión. No se crean productos remotos.

La vinculación es gradual, durante la preparación del primer cobro remoto de
cada producto. Esta fase no establece que los 22 productos estén ya vinculados.
Los nombres modificados antes del primer vínculo pueden requerir vinculación
manual futura. Si se borran los datos de la aplicación también se pierden los
vínculos. No se reutilizan entre proyectos Supabase. Cambiar el ID local supone
una nueva identidad; cambiar solo su nombre conserva la correspondencia.

Se mantienen INSERT separados de ventas y detalle_venta y su verificación.
La bandera TEXAS_ENABLE_SIMPLE_SALES y la preferencia local siguen aplicando.
No hay consumo de inventario, cancelación, nuevos permisos ni RPC en esta fase.

## Información para recetas (pendiente de reglas y datos reales)

| Dato actual | Preparación necesaria en servidor |
|---|---|
| Producto.id y vínculo remoto | Enviar producto_id remoto, validarlo activo y conservar ID del detalle |
| VentaItem.quantity | Cantidad de unidades vendidas, positiva |
| selectedExtras: ID local, nombre, precio | Vincular cada extra a un modificador/receta autorizado y definir cantidad por unidad |
| removedIngredients: textos | IDs de exclusión estructurados y relación explícita con ingredientes de la receta |
| notes: texto libre | Conservar como nota; no deducir automáticamente consumo a partir del texto |
| Combos como productos independientes | Definir componentes, cantidades y elecciones; hoy no existe esa estructura |
| producto_ingrediente sin filas | Configurar recetas y unidades; ausencia de receta no equivale a consumo cero |

No asumir que «Salsas aparte» elimina ingredientes ni que un extra siempre
representa un único ingrediente. Confirmar conversiones de unidades, porciones,
redondeo, sustituciones, combos, recetas de bebidas y productos sin consumo.
La promoción cambia el importe, no permite deducir cantidades de ingredientes.

## Próxima fase

Confirmar recetas, modificadores y reglas de precios/descuentos. Preparar una
RPC con validación de perfil/sucursal, idempotencia, transacción de cabecera y
detalles, bloqueos de lotes y trazabilidad del consumo. Conservar una clave de
solicitud ante respuestas inciertas. No descontar retrospectivamente ventas.
Los empleados demo y sus referencias históricas permanecen intactos.
