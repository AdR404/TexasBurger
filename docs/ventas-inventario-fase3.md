# Fase 3 — RPC transaccional preparada, sin activar

## Alcance y evidencia

Preparado localmente sobre `main`, conservando todos los cambios pendientes.
No se ejecuta SQL, no se conecta Flutter y no se modifica ninguna RPC existente.
La confirmacion de fase 2 del usuario indica receta numeric(11,3) NOT NULL,
positiva, RLS y 22 productos sin ingredientes. Los tipos de ventas, detalles,
lotes y movimientos se contrastaron con la inspeccion aportada anteriormente;
no se hizo una nueva inspeccion remota. SQL nuevo requiere Login fase4 instalado.

Fuentes locales revisadas: database/login_fase4/02_ventas_historial_catalogos.sql
(login_contexto_operativo y permisos por columna),
database/migrations/004_login_perfil_compatible.sql (login_mi_perfil),
lib/services/db_service.dart, lib/models/venta_item.dart,
lib/models/venta.dart, lib/services/bootstrap_service.dart y docs de fases 1/2.
Este documento sustituye las propuestas amplias de fase2 para esta implementacion:
no hay unidades adicionales, tabla de componentes ni tabla de modificadores.

## Estructura minima

- productos.consumo_modo: pendiente (predeterminado), receta, unidad_completa, exento.
- ventas.operacion_id UUID unico global, operacion_actor UUID y operacion_solicitud JSONB:
  identidad y solicitud exacta para comparar reintentos sin depender de hashes.
- ventas.caja_turno_id bigint nullable: solo nuevas ventas RPC, FK al turno.
- inventario_movimientos.venta_id integer nullable: FK a venta; permite salida o entrada.
  La RPC actual solo produce salidas. Entradas quedan reservadas a futuras devoluciones,
  sin implementarlas. Se conservan los CHECK de saldos y tipos existentes.
- Indices para operacion unica, turno y movimientos por venta. Cero tablas nuevas.

Historicos mantienen NULL en vinculos. No se deducen turnos ni consumos anteriores.
No se retiran los INSERT actuales de ventas/detalle_venta ni se amplian los de cajeros.
01 exige que Login fase4 ya limite INSERT a columnas antiguas, porque un permiso
INSERT a nivel tabla permitiria falsificar la identidad de operaciones nuevas.
Si esa precondicion falla, abortar y revisar permisos reales; NO aplicar un REVOKE improvisado.

## Configurar consumo desde SQL Editor

Configurar solo con cantidades reales aprobadas. Nunca activar automaticamente:

| Modo | Requisito |
|---|---|
| pendiente | Rechaza la venta nueva, aunque existan algunas lineas |
| receta | Al menos una linea; receta COMPLETA de la unidad comercial |
| unidad_completa | Una linea explicita a ingrediente pza/pzas, cantidad exactamente 1 |
| exento | Decision explicita del administrador; cero lineas de receta |

Las unidades admitidas son kg, L, pza, pzas; no se convierte ni normaliza nada.
Lote y ingrediente deben tener exactamente la misma unidad. Piezas en recetas y
saldos utilizables deben ser enteras. g/ml/reb u otras unidades bloquean hasta
confirmar una regla; no inventar equivalencias. Cantidades se multiplican por
unidades vendidas enteras y se agregan por ingrediente con numeric exacto.

Combos/promociones hoy son productos independientes, no componentes enlazados.
Para un combo fijo se puede aprobar UNA receta plana completa, sumando sus
componentes reales una sola vez. No enviar a la RPC tambien los componentes como
lineas vendidas. Combos variables deben permanecer pendientes hasta definir reglas.
El servidor no puede reconocer por el nombre que un combo esta mal configurado.

VentaItem.selectedExtras contiene ProductoExtra con IDs locales ext_*, precios
y nombres, pero no cantidades de inventario. removedIngredients es List<String>;
notes es texto libre. Sin correspondencias comerciales fiables la RPC RECHAZA
cualquier extra, exclusion o nota no vacia. No descontara la receta completa para
una hamburguesa sin queso ni ignorara el extra. La integracion Flutter debe enviar
estas opciones y bloquearlas claramente, nunca ocultarlas para pasar la validacion.
No se puede habilitar el flujo completo del carrito hasta resolver estas reglas.

## Contrato de la RPC

registrar_venta_con_consumo(p_operacion_id uuid, p_solicitud jsonb).
Solicitud exacta (ejemplo de estructura; no es receta ni instruccion de insertar):

```json
{
  "sucursal_id": "ID_AUTORIZADO",
  "items": [{"producto_id": 123, "cantidad": 1, "precio_unitario": 116,
             "extras": [], "exclusiones": [], "notas": ""}],
  "subtotal": 116, "descuento": 0, "total": 116, "iva": 16,
  "metodo_pago": "Efectivo", "codigo_descuento": null
}
```

Los numeros del ejemplo solo ilustran el contrato. ID 123 no es correspondencia real.
Acepta Efectivo/Tarjeta/Transferencia; IVA siempre incluido, tasa 0.16.
Valida subtotal = suma de cantidades por precios, descuento entre cero y subtotal,
total = subtotal-descuento, base = round(total/1.16,2), IVA = round(total-base,2).
Se normalizan importes a centavos solo si el residuo no excede 0.000001; esto
tolera double (por ejemplo 0.20000000000000004), no diferencias de un centavo
ni precios con milésimas reales. Detalles y cabecera usan los mismos centavos.
Conserva los importes comerciales enviados, NO vuelve a cobrar con precio de catalogo.
LIMITACION: comprobar aritmetica no autoriza descuentos, cupones ni precios.
Las reglas comerciales viven en Flutter y no hay catalogo remoto para verificarlas;
un cliente alterado puede enviar precios/descuentos coherentes pero no autorizados.
Debe decidirse esa autorizacion antes de considerar seguros los importes en servidor.
Esta fase no incorpora ni simula un sistema nuevo de permisos comerciales.

Respuesta: estado complete, venta_id, repetida boolean y caja_turno_id o null.
Campos desconocidos, requeridos ausentes y personalizaciones se rechazan.
Los IDs de usuario/empleado, nombres y fecha NO se reciben del cliente.

## Identidad, atomicidad y bloqueos

Exige auth.uid() y auth.role() authenticated; reutiliza login_contexto_operativo(),
que filtra perfil activo, empleado real activo y admin efectivo cuando corresponde.
Bloquea las filas de perfil/empleado/autorizacion durante la operacion. El cajero
y admin con sucursal fija solo pueden seleccionar esa sucursal. Admin general
requiere admin efectivo y puede seleccionar una sucursal activa Texas Burger.

SECURITY DEFINER de postgres, search_path vacio, objetos calificados, EXECUTE solo
authenticated; no se concede ejecucion de bajas administrativas a cajeros.
La RPC valida todo internamente aunque postgres no este sujeto a RLS.

Bloqueo advisory transaccional por UUID; despues, por sucursal. UNIQUE(operacion_id)
es el respaldo final. Un UUID repetido con mismo actor/sucursal/JSON devuelve la
venta anterior sin consumir. Otro contenido/actor se rechaza. Se revalida acceso
antes de devolver la venta previa; revocar un perfil puede impedir consultarla.
JSONB ignora orden de claves; el orden de lineas y omitir un campo opcional frente
a enviarlo null SI cambia la solicitud. Flutter debera conservar UUID y JSON exactos.
No hay reintentos automaticos. READ COMMITTED es el aislamiento esperado; errores
de serializacion/deadlock en otros escenarios deben devolverse, no ocultarse.

Bloquea catalogo/recetas en SHARE durante la venta y lotes con FOR UPDATE en orden
ingrediente, caducidad, entrada, id. No usa SKIP LOCKED. Las bajas manuales bloquean
esos mismos lotes. Se releen los saldos despues de esperar. El bloqueo por sucursal
serializa ventas nuevas de esa sucursal; para el proyecto escolar es deliberado.
SQL Editor puede esperar a que termine una venta antes de cambiar recetas.

Fecha de servidor con clock_timestamp AT TIME ZONE America/Monterrey, calculada
despues de bloquear. Lote que vence hoy es valido, ayer no. Se usan ambos lugares
(Almacen/Refrigerador) de la sucursal sin prioridad adicional, FEFO primero.
Se comprueba suficiencia de TODOS los ingredientes antes del INSERT. Despues se
inserta venta/detalles, se distribuye consumo FEFO y se registran salidas con
venta_id/lote_id/cantidad/antes/despues/actor. Cualquier error revierte todo.
Los huecos de secuencia tras errores son normales, no son ventas parciales.

## Caja y reversibilidad

Si existe turno abierto de empresa/sucursal se bloquea y asocia; sin turno se
permite venta con caja_turno_id NULL. No se inventa ni abre un turno.
Un turno que se abre simultaneamente puede no ser visible: venta queda sin turno.
El cierre existente bloquea la misma fila, pero recibe totales calculados antes
por Flutter: asociar el turno NO resuelve la carrera entre lectura de ventas y
cierre. Mantener esta limitacion documentada para la fase de Caja, sin cambiarla aqui.
No modificar fechas anteriores ni asociar ventas antiguas por rango de fechas.

03 elimina solamente la RPC nueva y conserva datos/columnas/indices. Es una
reversion operativa segura, no destructiva; no devuelve stock ni borra trazabilidad.
Restaurar stock/cancelar ventas queda para otra fase. Para reactivar, solo 02.

## Orden y validacion

1. Revisar permisos reales/dependencias; respaldar el proyecto antes de aplicar.
2. 01_estructura_REVISION.sql, luego 02_rpc_REVISION.sql (SQL Editor postgres).
3. 04_verificacion_solo_lectura.sql. Los 22 productos deben seguir pendientes.
4. Configurar recetas reales aprobadas, sin usar los ejemplos como recetas.
5. En base AISLADA con identidades de prueba, completar y ejecutar
   05_pruebas_aisladas_ROLLBACK.sql. No inventa recetas: reutiliza una real.
6. 06_concurrencia_AISLADO.sql por bloques en dos conexiones. Ese ensayo necesita
   COMMIT en la base desechable para observar stock confirmado; nunca en compartida.
7. Revisar resultados antes de conectar Flutter en el siguiente prompt.

05 verifica venta valida, stock insuficiente, receta ausente/pendiente, producto
inactivo, sucursal ajena, usuario inactivo, caducados, multilote/FEFO/hoy valido,
idempotencia y cambio de payload; inyecta fallo al insertar movimiento DESPUES de
insertar venta/detalles y actualizar lote, comparando el estado exacto anterior.
06 cubre competencia por stock y mismo UUID desde dos conexiones.
Las pruebas con datos NO se ejecutaron. No hay PostgreSQL/psql/Docker disponible
en PATH; el analisis de sintaxis local no valida objetos ni comportamiento real.
Los seis archivos SQL pasaron parse_sql y parse_plpgsql de pglast localmente.
No se ejecuta Flutter analyze/test porque no hay cambios Dart.

Verificaciones adicionales en aislado antes de habilitar: admin con sucursal fija
no puede elegir otra; admin general efectivo si puede; retirar inventario_admins
bloquea al admin; empleado inactivo bloquea; sesion anon bloquea. Comprobar venta
con turno abierto y sin turno, y que todas las RPC antiguas siguen disponibles.
Estas verificaciones dependen de disponer de esas identidades/turnos de prueba;
05 no crea cuentas Auth ni altera turnos. Las cancelaciones siguen pendientes.

Antes de integrar: resolver recetas reales y personalizaciones, probar RPC en
aislado, mantener UUID/payload tras respuesta incierta, adaptar mensajes y confirmar
venta solo con complete, conservar precios/IVA actuales. El escritor antiguo
todavia permite ventas sin consumo; retirar su acceso se hara despues, no ahora.

## Revision final 1B

Se revisaron PricingService, SalesService, DbService, Venta/VentaItem, DiscountCode,
cart_bottom_sheet, quick_sale_screen, product_customizer_dialog y payment_selector.
Precio unitario = precio de producto + extras; subtotal = suma precio*cantidad.
PricingService aplica 42 por cada par de hamb_texana_clasica los martes o con
promocion forzada, limitado al subtotal. Despues aplica cupon fijo/porcentual
sobre el remanente, redondeado a centavos. SalesService conserva esos importes;
DbService los envia sin normalizar double. La comparacion SQL estricta podia
rechazar residuos binarios. Ahora admite solo esa diferencia insignificante y
reproduce el orden de redondeo de base/IVA, manteniendo controles monetarios.
Efectivo, Tarjeta y Transferencia coinciden exactamente con el selector Flutter.
Precios reales de mas de dos decimales siguen bloqueados: no hay regla comercial
confirmada que permita redondearlos silenciosamente para cobrar.

El personalizador ofrece extras ext_*, exclusiones y notas de producto: ventas
habituales personalizadas seran rechazadas hasta configurar sus consumos. Tambien
existen notas generales de Venta y datos de entrega/mesa, aun fuera del contrato
remoto actual; la siguiente integracion debera distinguirlos de instrucciones que
afecten ingredientes, nunca descartarlas para evadir validacion ni usar el escritor
antiguo como fallback cuando la RPC rechace una venta.

04 valida el signo del saldo segun entrada/salida y no exige que quien reintegre
sea el vendedor original. La futura cancelacion debera validar su propio actor,
evitar reintegros duplicados/excesivos y respetar cantidad_disponible<=cantidad_inicial.
Permitir entrada en el CHECK no resuelve esas reglas ni habilita cancelaciones.
03 sigue siendo reversion OPERATIVA, no restaura estructura ni stock.
05 incorpora importes double, promocion, cupon y rechazo de discrepancias de
centavos/precios de tres decimales. 06 conserva el ensayo en dos conexiones aisladas.
No se encontraron otros bloqueos concretos en la revision estatica del SQL;
el parser no sustituye ejecutar 05/06 contra PostgreSQL en una base aislada.
