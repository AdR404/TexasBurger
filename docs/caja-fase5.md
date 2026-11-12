# Fase 5 revisada: transicion de cierres y conciliacion de efectivo

## Alcance

Este documento describe la preparación SQL. La integración Flutter posterior se
documenta en `cancelaciones-caja-flutter-fase5.md`.

Solo archivos SQL/documentacion locales. No se ejecuto SQL, no se modifico Flutter,
ni recetas, permisos de cancelacion, datos reales o cortes cerrados.
La version anterior de Fase5 era un borrador: 01 revisado es de PRIMERA instalacion.
Si ya se instalo una version anterior, detenerse y preparar una actualizacion desde
su DDL real; no ejecutar este CREATE/ADD COLUMN como si estuviera vacio.

## Problemas y transicion

CajaRepository._sales suma por empresa, sucursal y fechas locales Monterrey,
sin estado ni caja_turno_id, y close envia importes calculados en Flutter.
El cierre original acepta esos importes. Eso permite cifras viejas y, sin control
adicional, utilizar la firma antigua para eludir las cancelaciones.

01 conserva el cuerpo original con nombre caja_cerrar_turno_base_fase5 y revoca
EXECUTE a todos salvo postgres. La firma publica caja_cerrar_turno se conserva
con un adaptador que autoriza, bloquea, recalcula y compara importes/ordenes.
No se elimina la funcionalidad anterior ni se reconstruye su UPDATE de cierre.
Se comprueba que la implementacion interna no pueda ejecutarse por anon/authenticated.

Reglas de uso:
- Flutter anterior: caja_cerrar_turno, misma firma y resultado bigint. Puede cerrar
  turnos SIN cancelaciones si sus importes coinciden con los calculados en servidor.
- Turnos con cancelaciones: obligatoriamente caja_cerrar_turno_verificado. La via
  antigua los rechaza aunque se le envien importes netos correctos.
- Cliente actualizado: consultar caja_resumen_turno, revisar resumen y conservar
  huella; enviar huella, efectivo contado y notas al cierre verificado.
- Ambas vias rechazan doble cierre. Diferencias de totales/huella producen 40001:
  volver a consultar y revisar, no reintentar ciegamente.

El resumen suma exactamente una vez cada venta vinculada al turno, mas ventas
ANTIGUAS sin operacion_id y sin caja_turno_id de la misma empresa/sucursal en
el periodo vigente, conservando el criterio temporal que ya usa Flutter.
Las filas antiguas se muestran en legado_sin_vinculo: no se escribe su caja_turno_id
ni se inventa una relacion historica persistente. Esto permite turnos mixtos.
Las nuevas de fase3 sin turno (operacion_id presente), activas o canceladas, quedan
fuera. El Flutter viejo que las sumase recibira rechazo por cifras diferentes;
no se permite cerrar incorrectamente por compatibilidad.

Bruto registrado = suma ventas.total (ya incluye descuentos/IVA); cancelado =
suma canceladas; neto y ordenes validas excluyen canceladas. Desglose por metodo.
No sumar detalle_venta ni aplicar descuentos nuevamente. Cortes cerrados se muestran
con corte_guardado como dato historico autoritativo, nunca se recalculan/escriben.
El diagnostico por fechas no puede corregir relojes historicos mal configurados.

## Efectivo: confirmacion explicita, sin movimientos automaticos

Cuatro columnas nullable en ventas, sin tabla nueva:
- efectivo_cancelacion_estado: NULL = pendiente, no_cobrado o devuelto.
- efectivo_conciliado_por: UUID del administrador autenticado.
- efectivo_conciliado_en: hora del servidor.
- efectivo_conciliacion_nota: explicacion obligatoria.
CHECK exige venta cancelada en efectivo y auditoria completa. INSERT/UPDATE cliente
sobre estas columnas no se permite. Datos anteriores quedan NULL, sin inventar hechos.

Nueva RPC caja_conciliar_efectivo_cancelado(venta_id, estado, nota,
p_confirmo_sin_salida DEFAULT false). Requiere administrador efectivo y sucursal
compatible, igual que Caja, y permiso activo en cancelacion_permisos para esa sucursal.
No cancela tickets ni concede permisos para cancelarlos.
Bloquea turno (si existe) y venta; rechaza turno cerrado. Registra confirmacion solo
si se declara expresamente que NO hay otra salida de Caja por la misma devolucion.
Repetir estado/nota es idempotente, no reemplaza auditoria; cambios posteriores
requieren revision, no una confirmacion silenciosa distinta.

no_cobrado: no entro efectivo; devuelto: entro pero ya fue entregado al cliente.
En ambos casos el flujo neto de esa venta es cero. El cierre puede excluirla del
neto sin registrar una salida adicional. Una cancelacion pendiente de importe
positivo impide cerrar; una vez conciliada se puede completar el cierre.
La huella incluye auditoria de conciliacion, por lo que se debe refrescar el resumen.
No hace falta cambiar cancelar_venta ni su firma: cancelar, confirmar efectivo y
cerrar son operaciones separadas. Tampoco se realizan reembolsos bancarios.

IMPORTANTE: p_confirmo_sin_salida es una DECLARACION AUDITADA del administrador,
no una comprobacion bancaria ni deteccion automatica de conceptos de movimientos.
Los movimientos genericos actuales no tienen vinculo con ventas. Si ya se registro
una salida por esa devolucion, no confirmar falsamente: conciliar/corregir esa
contabilizacion por un procedimiento administrativo aprobado antes de cerrar.
No se borra, compensa ni reclasifica dinero automaticamente en este prompt.
La UI futura debe explicar esta regla y pedir confirmacion consciente. Un admin
puede mentir o equivocarse; el esquema no puede deducirlo de una nota libre.
Esto evita doble descuento en el flujo soportado, sin prometer detectar salidas
anteriores no identificadas. No registrar devoluciones conciliadas otra vez como
salidas manuales despues de confirmarlas.

## Bloqueos revisados

Ventas fase3: identidad, sucursal, advisory, catalogo SHARE, turno UPDATE, lotes,
INSERT ventas/movimientos. Cancelacion: identidad/sucursal/permisos, turno UPDATE
si existe, venta UPDATE, movimientos/lotes, UPDATE venta. Movimiento de Caja:
turno UPDATE antes de insertar movimiento/actualizar acumulados. Conciliacion:
identidad, turno UPDATE si existe, venta UPDATE. Cierres: identidad, turno UPDATE,
ventas SHARE, resumen/recalculo y cierre base. Resumen aislado toma SHARE de turno.

Se mantiene LOCK TABLE ventas IN SHARE MODE porque INSERT antiguo no coopera con
el lock de turno. Tomarlo despues de turno respeta que los escritores nuevos
bloquean turno ANTES de modificar ventas. Los cierres no actualizan ventas ni
convierten SHARE en ROW EXCLUSIVE. Dos SHARE de cierres son compatibles.
No se detecto ciclo entre estas rutas previstas; SQL manual con otro orden o
clientes que prolonguen transacciones pueden causar esperas/interbloqueos.
Es global y puede retrasar otras sucursales: aceptable solo como transicion de
bajo volumen, operaciones breves y pruebas aisladas antes de instalar.

Si venta/cancelacion gana, cierre recalcula y rechaza huella vieja. Si cierre gana,
cancelacion de ese turno rechaza y nueva venta fase3 puede quedar sin turno segun
su regla vigente. La via antigua no usa huella: exige igualdad exacta de importes
actuales y no admite cancelaciones. La via verificada valida contenido/IDs ademas
de sumas. No hay reintentos automaticos.

Limite heredado: un INSERT antiguo puede esperar y entrar DESPUES del cierre con
fecha de celular anterior. Sin modificar ese escritor no se puede impedirlo ni
asignarlo con certeza. Mientras siga activo, detener cobros al contar/cerrar;
no reescribir cortes cerrados. La futura transicion debe retirar o coordinarlo.
Las escrituras visibles al cierre no se omiten; no se promete capturar escrituras
futuras/retroactivas. Tampoco se corrigen encabezados incompletos del escritor antiguo.

## Pruebas y validacion

04 usa INSERT/UPDATE de datos SINTETICOS para preparar ventas/cancelaciones, dentro
de ROLLBACK aislado. SI ejecuta RPC de resumen, ambos cierres, movimientos de Caja
 y conciliacion. NO prueba cancelar_venta ni consumo completo al actualizar estado.
Cubre cierre normal, tarjeta cancelada, efectivo pendiente/no cobrado/devuelto,
confirmacion obligatoria, legado incluido, mixto, nueva sin turno excluida,
importes cliente incorrectos, bloqueo del cierre antiguo con canceladas,
huella obsoleta, doble cierre y conservacion de movimientos.

05 prepara pruebas de RPC de negocio en dos conexiones, con fixtures ya autorizadas
SOLO en aislado: ventas/cancelacion/cierre, ambos ordenes, conciliacion concurrente,
doble cierre y esperas del escritor antiguo. No habilita permisos de cancelacion.
No se ejecutaron pruebas SQL funcionales. Los seis scripts se validan sintacticamente
con parse_sql/parse_plpgsql de pglast; esto no prueba objetos, ACL ni locks reales.
No se ejecutan pruebas Flutter porque no se modifica Dart.

## Orden manual y reversion

1. 00_respaldo_cierre_solo_lectura: guardar DDL y comandos ACL originales ANTES de 01.
2. Revisar columnas nuevas, regla de confirmacion y transicion; instalar primero en aislado.
3. 01_resumen_y_cierre_REVISION como postgres, primera instalacion completa.
4. 02_verificacion_solo_lectura: comprobar especialmente que base interna NO permite
   EXECUTE a clientes y que columnas de conciliacion no admiten escritura directa.
5. 04 y 05 EXCLUSIVAMENTE en aislado; revisar resultados antes de instalacion compartida.
6. Flutter futuro: mostrar neto/cancelado/legado, confirmar efectivo por RPC, refrescar
   huella y usar cierre verificado. Conservar valores historicos de cortes guardados.

03 es reversion OPERATIVA: elimina adaptador/RPC nuevas, renombra implementacion
original y exige pegar las ACL respaldadas por 00. Guard false impide ejecutarla
sin revisar. Conserva columnas/conciliaciones; no altera dinero ni cortes.
Advertencia: restaura el cierre SIN los controles nuevos; detener cancelaciones
antes de revertir. Para reinstalar hay que respetar las columnas ya conservadas,
no repetir sus ADD COLUMN/CHECK como si no existieran.
