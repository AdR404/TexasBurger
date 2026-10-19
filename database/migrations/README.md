# Contexto de ventas: preparación para Supabase

Estos scripts están preparados, **no ejecutados**. `database/schema.sql` sigue
siendo la referencia original; no se debe volver a ejecutar sobre una BD existente.
El esquema remoto no se ha inspeccionado ni se asume idéntico al local.

## Estado de la aplicación

- Cada venta nueva guarda un `saleContext` local con IDs y nombres de empresa,
  sucursal y empleado. `timestamp` conserva el momento de completar el cobro,
  tomado del reloj del dispositivo; no se agregó otra fecha/hora.
- Empresa fija: `texas_burger` / Texas Burger. Las ventas antiguas se muestran
  bajo esta empresa conocida; sucursal y empleado ausentes dicen “No registrado”.
  No se les asigna la selección actual ni se elimina/reinicia el historial.
- Catálogo local: `lib/data/staff_catalog.dart`. IDs de sucursal: `perimetral_sur`
  y `norte`. Los tres IDs `demo_*` corresponden exclusivamente a personas ficticias.
- La selección se guarda en `texas_staff_context`. Al abrir caja se conserva una
  copia en `CorteCaja.openingContext`. La sucursal se bloquea durante el turno y el
  empleado activo puede cambiar desde Venta o Caja. Cerrar caja limpia la selección
  activa, pero conserva los datos de ventas y del corte.
- Se permite el flujo existente de venta sin apertura de caja. El personal debe
  seleccionar sucursal y empleado una vez; se recuerda incluso tras reiniciar.
  Fuera de un turno abierto se puede cambiar la sucursal. Si se recupera un turno
  antiguo sin contexto, se solicita la selección para las nuevas ventas, sin
  inventar quién abrió ese turno histórico.
- CSV agrega columnas al final, sin cambiar las columnas/importes anteriores.
  Los reportes de ventas incluyen la atribución por ticket; el reporte de corte
  etiqueta al empleado de apertura como “Abrió caja”, no como autor de todas las
  ventas del turno.

## Compatibilidad remota actual

`DbService.guardarVenta` sigue enviando exclusivamente `usuario_id`, `fecha_hora`,
`total` y `metodo_pago` a `ventas`, además de los productos y sus detalles actuales.
**Empresa, sucursal y empleado seleccionados todavía NO se envían a Supabase.**
La fecha/hora sí se envía mediante el campo existente `fecha_hora`.

El `usuario_id = 2` preexistente se conserva únicamente por compatibilidad con el
escritor antiguo; **no identifica al empleado seleccionado ni se ha verificado su
identidad**. No hay ninguna conversión entre IDs `demo_*` y IDs de `usuarios`.
Su eliminación o reemplazo exige revisar el esquema, permisos y datos reales.

El guardado remoto sigue siendo parcial y asíncrono; no se añadió sincronización,
reintento persistente ni lectura remota. Aplicar la migración por sí solo **no activa**
el envío de los nuevos campos. No se habilitó ningún interruptor automático.

## Diseño propuesto

`sucursales` usa las claves estables del catálogo local. Al existir una única
empresa fija, se guarda su ID y nombre sin crear un CRUD de empresas.

`empleados_pos` separa al personal operativo de las credenciales. Reutilizar
directamente `usuarios` obligaría a inventar usuarios/contraseñas o a asumir
correspondencias que no se han comprobado. Se permite una relación opcional y
única `empleados_pos.usuario_id -> usuarios.id`, inicialmente NULL. Solo deberá
completarse después de verificar cada empleado real. Los IDs demo no deben
reutilizarse para personas reales: sus tickets históricos deben seguir siendo demo.

Mapeo para una futura versión del escritor remoto:

| Local | Columna propuesta en ventas |
|---|---|
| saleContext.companyId | empresa_id |
| saleContext.companyName | empresa_nombre |
| saleContext.branchId | sucursal_id |
| saleContext.branchName | sucursal_nombre |
| saleContext.employeeId | empleado_pos_id |
| saleContext.employeeName | empleado_nombre |
| timestamp | fecha_hora (existente) |

Las columnas nuevas aceptan NULL, sin valores predeterminados ni relleno histórico,
para preservar ventas antiguas y la compatibilidad con esta versión de la app.
No se modifican importes, precios, compras, inventario ni cortes remotos.

## Aplicación posterior, supervisada

1. Obtener respaldo y una copia de prueba del esquema real. Ejecutar primero
   `000_inspect_ticket_schema.sql` (solo lectura) y revisar también triggers,
   permisos/grants y restricciones de las tablas existentes. Verificar que
   `usuarios.id` es integer y que las tablas/columnas propuestas no colisionan.
   Si hay diferencias, adaptar la propuesta antes de ejecutarla.
2. Revisar políticas RLS de `ventas` y diseñar las de las nuevas tablas según el
   acceso aprobado. La propuesta activa RLS en tablas nuevas y no crea políticas
   permisivas. No publicar credenciales privilegiadas en la app.
3. Aplicar `001_sale_staff_context.sql` una sola vez en la copia de prueba, con
   un rol autorizado. La transacción debe completarse íntegra; ante un error,
   ejecutar ROLLBACK si la herramienta deja la sesión en transacción abortada.
4. Comprobar filas antiguas, catálogos, claves foráneas y que el escritor antiguo
   sigue insertando ventas. Registrar la aplicación de la migración en el control
   de cambios del despliegue. Después, repetir el procedimiento aprobado en el
   entorno correspondiente.
5. Preparar otra entrega que envíe explícitamente los nuevos campos. Resolver el
   significado de `ventas.usuario_id` y sus correspondencias antes de cambiarlo.
   Validar con registros de prueba autorizados y comprobar RLS para el cliente real.
6. No intentar rellenar ventas históricas automáticamente: actualmente no se
   persiste un vínculo entre el ID local/folio y el ID remoto devuelto. Se necesita
   una estrategia de conciliación e idempotencia antes de sincronizar históricos.

Reversión: esta app puede seguir usando el esquema ampliado. Ante un problema,
revertir primero el cliente y conservar las columnas/datos nuevos; no borrar tablas
ni columnas como parte de una reversión automática.

## Validación local

Ejecutar `flutter analyze --no-pub`, `flutter test --no-pub` y, con el SDK Android
disponible, `flutter build apk --debug --no-pub`. Las pruebas nuevas usan preferencias
simuladas y un escritor remoto falso, sin inicializar Supabase ni escribir datos remotos.

Comprobación manual: abrir caja en Perimetral Sur con Ana, vender, cambiar a Luis,
volver a vender y revisar ambos tickets/historial/CSV. Reiniciar y comprobar que se
conservan Norte/Perimetral y el último empleado elegido, según el turno. La sucursal
no debe cambiar hasta cerrar caja. Revisar también ventas/cortes antiguos y ventas
sin caja abierta. La exportación a Escritorio mantiene su limitación previa en Android.
