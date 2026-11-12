# Fase 5: Flutter, cancelaciones e historial

Implementación local. No se ejecutó SQL, no se cancelaron ventas, no se crearon
permisos, no se desplegó ni se generó APK. Fase 4 debe estar instalada; Fase 5
debe instalarse y verificarse antes de activar su opción.

## Activación posterior

Ambas opciones son falsas por defecto:

- `--dart-define=TEXAS_ENABLE_SALE_CANCELLATIONS=true`
- `--dart-define=TEXAS_ENABLE_VERIFIED_CASH_CLOSE=true`

Requieren el modo remoto existente (`TEXAS_ENABLE_SIMPLE_SALES=true`, conexión
habilitada y sesión válida). No activan `TEXAS_ENABLE_INVENTORY_SALES`.
Sin opciones nuevas, Caja conserva su ruta anterior para turnos sin cancelaciones.
Si detecta canceladas, bloquea ese cierre y pide instalar/habilitar el verificado;
no suma esas ventas como ingreso válido con el backend anterior. No hay fallback del cierre
verificado al antiguo. No activar cancelaciones operativas mientras los clientes
de Caja sigan usando un cierre que no las contemple.

## Flujo

En Historial remoto, abrir una venta y pulsar Cancelar venta. Solo aparece para
administrador efectivo y sucursal compatible. Pide motivo, confirmación y reintegro
opcional (desmarcado). `cancelar_venta` conserva el ticket y decide la autorización.
No se usa el borrado local como cancelación. No hay reintentos automáticos.
Tras enviar, el detalle impide otra solicitud hasta salir y consultar nuevamente.
Los errores de permiso, turno cerrado y reintegro se muestran con el mensaje de la
RPC. Ante pérdida de conexión, consultar antes de repetir una operación incierta.

`cancelacion_permisos` NO tiene SELECT para clientes ni RPC de consulta de permisos.
Por eso Flutter comprueba perfil/sucursal, pero no puede garantizar de antemano el
permiso explícito: la RPC lo comprueba. No se amplió acceso a esa tabla.

El historial muestra estado, motivo, fecha, UUID del administrador y reintegro.
Los productos e importes originales se conservan. La suma de la página excluye
canceladas; es una página de hasta 50 ventas, no un reporte global.
El historial remoto y el local permanecen separados: no se suman ni duplican entre sí.
Las lecturas remotas actualizan el estado local solo por ID remoto u operación UUID,
nunca mediante coincidencias por nombres, importes o fechas. Los tickets antiguos
sin esos identificadores se conservan y no se vinculan por suposición.

Los CSV locales conservan Total original y agregan Estado, Ingreso_Valido (cero para
canceladas) y Motivo_Cancelacion. El resumen WhatsApp y los cálculos del Dashboard
excluyen canceladas conocidas. Los reportes locales son una instantánea del dispositivo,
no una consulta global actualizada: pueden faltar cancelaciones hechas en otro equipo
que aún no se hayan consultado. La interfaz lo advierte. Dashboard continúa con su
bloqueo existente de “en desarrollo”; no se habilitó ni se convirtió en reporte remoto.

## Caja

Con cierre verificado activo, la carga del turno consulta `caja_resumen_turno` y
muestra bruto, cancelado, neto, métodos, órdenes, fondo, entradas, salidas y efectivo.
Al abrir el diálogo se consulta nuevamente; se revisa ese resumen y se ingresa el
efectivo contado. Se envía su huella a `caja_cerrar_turno_verificado`. Si cambia,
se muestra el rechazo, se consulta otra vez y se exige nueva confirmación. Nunca
se reenvía el cierre automáticamente. Se bloquea la doble pulsación en curso.
Los cortes cerrados continúan leyéndose de sus valores guardados.

Para efectivo cancelado, abrir la venta en el historial: Conciliar efectivo permite
`no_cobrado` o `devuelto`, nota obligatoria y declaración explícita de que NO existe
otra salida por esa devolución. Se llama a `caja_conciliar_efectivo_cancelado`;
no se generan movimientos ni reembolsos. Se actualiza Caja después. Si ya existe
una salida genérica, requiere revisión administrativa; una nota no puede detectar
ni corregir esa doble contabilización. Una cancelación positiva pendiente bloquea
el cierre. Las columnas de conciliación solo se consultan con el flag de Caja activo,
por lo que no se solicitan antes de instalar la migración.

## SQL pendiente y permisos

En `database/caja_fase5/01_resumen_y_cierre_REVISION.sql`, conciliación exige permiso
activo en `cancelacion_permisos` para auth.uid() y sucursal, manteniendo el bloqueo
FOR SHARE de la autorización durante la operación.
Las RPC nuevas admiten EXECUTE solo para authenticated y validan perfil dentro.
anon y service_role no tienen EXECUTE, coherente con cancelar_venta de Fase 4;
no se usa service_role desde Flutter. La implementación interna del cierre tampoco
admite ejecución directa. La consulta 02 comprueba los tres roles. La fixture 04
requiere permiso explícito de cancelación en la base aislada; no lo concede.

Instalación: seguir 00 (guardar respaldo), 01, 02 de Caja Fase 5, primero en aislado;
04/05 solo en aislado. 03 es reversión operativa y no debe ejecutarse como instalación.
No habilitar permisos ni flags antes de revisar esta integración.

## Validación manual pendiente

- Administrador autorizado/no autorizado, cajero y otra sucursal.
- Cancelar sin reintegro; reintegro válido, caducado y repetido.
- Confirmar historial, detalle y cantidades originales después de reiniciar.
- Conciliar efectivo no cobrado/devuelto; bloquear el pendiente y turno cerrado.
- Resumen mixto de legado y ventas vinculadas; ventas nuevas sin turno excluidas.
- Cierre con cambio concurrente, huella obsoleta, doble pulsación y corte cerrado.
- Pérdida de conexión tras enviar: actualizar antes de repetir.
- Ambas opciones desactivadas y ambas activadas tras instalar el SQL.

Los tests Flutter usan callbacks simulados y preferencias en memoria. No sustituyen
las pruebas de permisos, bloqueo, RLS y transacciones en PostgreSQL ni Android.

## Archivos de esta integración

- lib/models/venta.dart
- lib/services/sale_actions.dart (nuevo)
- lib/services/db_service.dart
- lib/services/sales_service.dart
- lib/services/caja_repository.dart
- lib/services/caja_service.dart
- lib/services/dashboard_service.dart
- lib/services/export_service.dart
- lib/screens/history_screen.dart
- lib/screens/caja_screen.dart
- lib/widgets/remote_sale_history.dart
- lib/widgets/sale_history_list.dart
- lib/widgets/ticket_dialog.dart
- lib/widgets/sale_actions_panel.dart (nuevo)
- lib/widgets/verified_cash_dialog.dart (nuevo)
- test/cancellations_cash_test.dart (nuevo)
- test/discount_integration_test.dart (nuevas columnas CSV)
- database/caja_fase5/01_resumen_y_cierre_REVISION.sql
- database/caja_fase5/02_verificacion_solo_lectura.sql
- database/caja_fase5/04_pruebas_AISLADAS_ROLLBACK.sql (requisito de fixture)
- docs/caja-fase5.md
- docs/cancelaciones-caja-flutter-fase5.md (este archivo)

Los cambios anteriores de otras fases permanecen en el árbol de trabajo.

## Resultado local

- `flutter analyze --no-pub`: sin incidencias.
- `flutter test --no-pub`: 103 pruebas aprobadas, incluidas 15 nuevas de esta fase.
- Los seis SQL de Caja pasan análisis sintáctico SQL/PLpgSQL con pglast.
- `git diff --check`: sin errores.
- No se ejecutaron los SQL ni pruebas contra Supabase. No se generó APK.
