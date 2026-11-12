# Fase 4 — Cancelacion SQL para revision, no ejecutada

## Evidencia y alcance

Revisados scripts inventario_fase3 (estructura, RPC y pruebas), schema.sql,
Login 004 y login_fase4/01_006_revisado_caja_inventario.sql y 02_ventas_historial_catalogos.sql.
schema.sql es antiguo: tipos finales de lotes, movimientos, turnos y restricciones
se contrastan con la inspeccion de Supabase aportada anteriormente, NO con una
consulta remota nueva. No hay DDL nuevo para esas tablas salvo columnas en ventas.
SalesService.cancelSale actualmente requiere admin en Flutter, elimina solo del
historial local y guarda SharedPreferences; no cancela una venta remota ni devuelve
inventario. Se inspecciono sin modificarlo. Ningun Dart/SQL anterior se modifica.

## Cambios minimos

ventas: estado text default activa, cancelada_en timestamptz, cancelada_por UUID
Auth FK, cancelacion_motivo text, inventario_reintegrado boolean default false.
Un CHECK exige coherencia entre estado y datos obligatorios de cancelacion.
No se borran cabeceras/detalles ni se cambian importes, UUID de venta o fechas anteriores.
Se conserva activo por defecto para los registros previos; no se deducen cancelaciones locales.

Una tabla pequena cancelacion_permisos(usuario_auth_id, sucursal_id, activo), clave
compuesta, administrada SOLO por postgres en SQL Editor. Empieza vacia. RLS sin
politicas cliente y sin permisos de escritura/lectura para anon/authenticated.
Se limpian los grants por defecto exclusivamente del objeto nuevo, no globalmente.
Las columnas nuevas de venta no reciben INSERT/UPDATE cliente. Si se heredan
permisos amplios, la migracion aborta en vez de cambiar los del registro actual.

## Autorizacion

cancelar_venta(p_venta_id integer, p_motivo text, p_reintegrar boolean DEFAULT false).
SECURITY DEFINER postgres, search_path vacio; EXECUTE authenticated, no anon.
Exige auth.uid(), auth.role() authenticated y login_contexto_operativo().admin=true.
Esto reutiliza login_mi_perfil: usuario admin activo, empleado real activo no demo,
y inventario_admins activo. Ademas exige permiso explicito en cancelacion_permisos
para la sucursal de la venta, tanto para admins generales como fijos. No basta ser
admin de inventario. Admin fijo no puede salir de su sucursal aunque se le asigne
por error otro permiso. Admin general tampoco tiene acceso automatico.
La sucursal debe seguir activa y pertenecer a Texas Burger. Perfil y permisos se
bloquean para no revocarlos/cambiarlos a mitad de la operacion.

Antes de usar la RPC el responsable de BD debe decidir a quien habilitar por
sucursal y agregar SOLO esas parejas reales en SQL Editor; no se crean permisos
automaticos. Puede desactivarlos con activo=false. No se entrega una lista de
usuarios predeterminados ni se eleva la cuenta texas@burguer.com sin perfil valido.

## Transaccion, concurrencia y resultado

Lee identidad de venta para autorizar; si tiene turno, bloquea turno y despues
venta. Sin turno bloquea directamente la venta. Relee los vinculos bajo bloqueo
y rechaza si cambiaron mientras esperaba. Si ya esta cancelada con mismo motivo (trim) y opcion de reintegro,
devuelve repetida=true y los datos ORIGINALES. Otro motivo/opcion devuelve error;
no permite convertir una cancelacion sin reintegro en una con reintegro despues.
Otro admin autorizado puede consultar la repeticion sin reemplazar al responsable.
Esta repeticion no modifica datos aunque el turno se haya cerrado posteriormente.

Para una cancelacion nueva, turno cerrado provoca rechazo. Bloquea movimientos
originales y luego los lotes en orden ingrediente/caducidad/entrada/id como ventas.
La fila de venta impide dos cancelaciones efectivas. La fila de turno coordina con
el FOR UPDATE del cierre existente; no cambia calculos ni importes del turno.
Al fallar cualquier INSERT/UPDATE o restriccion, PostgreSQL revierte todo.

Respuesta JSON: estado cancelada, venta_id, repetida, inventario_reintegrado,
cancelada_en (timestamptz), cancelada_por (Auth UUID). Errores 42501 para falta de
autorizacion, 22023 para datos/estado incompatibles. La fecha usa reloj del servidor.

## Reintegro

false por defecto: cambia solo estado y auditoria de venta. No toca stock.
true: exige venta de fase3 con salidas verificables. Suma cantidades originales
POR LOTE, nunca usa recetas actuales. Rechaza entradas previas, sucursal distinta,
consumo con actor/saldos incoherentes, capacidad insuficiente y lotes caducados.
Actualiza saldo e inserta entrada vinculada a venta y lote, con actor de cancelacion
y motivo. Respeta 0 <= disponible <= inicial y los CHECK de signo del movimiento.
No se inventa reposicion para ventas antiguas/exentas sin consumo.

Caducidad: fecha comercial America/Monterrey; hoy utilizable, ayer no. Si algun
lote no acepta retorno, falla TODA la solicitud; no repone parcialmente ni deriva
automaticamente a otro lote. El administrador puede decidir una NUEVA solicitud
sin reintegro tras el rechazo confirmado. No guardar producto caducado como stock
utilizable ni crear lotes sustitutos. La devolucion fisica/disposicion requiere revision.

## Caja y limitaciones pendientes

Las ventas nuevas de fase3 con operacion_id pueden cancelarse sin caja_turno_id,
con o sin reintegro sujeto a sus validaciones, mediante bloqueo de la venta. No
se consulta ni modifica Caja ni se inventa un turno por fechas. Dos llamadas
concurrentes sin turno se serializan por la misma fila de venta y solo una reintegra.
Las historicas sin caja_turno_id Y sin operacion_id siguen bloqueadas inicialmente.
Una
venta antigua CON vinculo explicito a turno abierto puede cancelarse sin reintegro;
no tiene derecho a reposicion ficticia. No se implementa un ajuste extraordinario.

No habilitar cancelaciones de uso normal hasta Fase5: los totales/reportes actuales
no filtran estado='activa'. El bloqueo de turno no corrige totales calculados en
Flutter antes del cierre; aun podria incluir una venta cancelada. No tocar la
RPC caja_cerrar_turno ni los cortes cerrados en esta fase, segun alcance solicitado.

registrar_venta_con_consumo conserva su comportamiento idempotente: puede devolver
complete de la venta original aun si fue cancelada despues. No se cambia aqui:
antes de integrar cancelaciones, Flutter/historial deben consultar estado vigente
y mostrar cancelada, sin confundir confirmacion de registro con vigencia del ticket.
La cancelacion local actual tampoco representa la nueva operacion auditada. Este
desfase es un bloqueo de ACTIVACION conjunta, no del DDL preparado.

La cancelacion no reembolsa tarjeta, transferencia ni efectivo automaticamente.
No valida una devolucion fisica con sensores; el admin es responsable de elegir
reintegro solamente si los ingredientes realmente pueden regresar.

## Archivos, orden y pruebas

1. Revisar dependencias fase3 revisada y Login; respaldo habitual antes de instalar.
2. Ejecutar 01_estructura_REVISION.sql como postgres (solo primera instalacion).
3. Ejecutar 02_rpc_REVISION.sql; ningun otro permiso/funcion existente se reemplaza.
4. Ejecutar 04_verificacion_solo_lectura.sql. Comprobar que no hay permisos asignados
   automaticamente y que no hay UPDATE/INSERT cliente sobre estado.
5. Para habilitar cuentas expresamente, usar 07_configurar_permisos_MANUAL.sql:
   A identifica UUID Auth y sucursales (solo lectura); B se completa y ejecuta
   una vez por cuenta decidida; C verifica (solo lectura). Sin completar B aborta.
   Daniel puede recibir Norte y Perimetral Sur; Rigoberto solo Norte, siempre
   verificando usuarios.auth_uid -> auth.users.id y la asignacion actual.
   No se resuelven cuentas por nombre ni se insertan permisos predeterminados.
   B agrega/reactiva parejas, no revoca permisos anteriores: revisar todos en C.
6. En base AISLADA, completar 05 con un UNICO admin general de prueba, una venta
   fase3 con consumo/turno abierto y otra sucursal activa. Puede ser la copia de
   Daniel. Cada caso simula temporalmente rol/asignacion/permisos sobre ese perfil
   en una subtransaccion que se revierte: no requiere tres administradores ni
   otra cuenta de cajero. No usar este archivo en Supabase principal.
7. Ejecutar 06_concurrencia_AISLADA.sql por bloques en dos conexiones independientes.
   Su COMMIT es exclusivamente para base desechable, nunca para pruebas compartidas.
   Pueden usarse copias de Daniel y Rigoberto, ambos habilitados para Norte y venta
   de Norte; no hace falta un tercer administrador. Repetir tambien sin turno.
8. Repetir verificaciones 04, revisar resultados y preparar fase5 antes de activar.

05 cubre admin habilitado, cajero, admin fijo ajeno incluso con permiso, admin
general sin permiso, inexistente, nueva sin turno con/sin reintegro (incluida
repeticion y comparacion exacta de turnos Y movimientos de Caja), historica sin
turno bloqueada, cerrado, sin consumo, capacidad,
caducidad, con/sin reintegro, repeticion y fallo inyectado DESPUES de actualizar
saldo, con comparacion de tablas para detectar efectos parciales. 06 cubre dos
administradores concurrentes y describe ensayo con cierre. Identidades y consumos
deben existir en fixture aislada. Las secuencias pueden avanzar aunque haya rollback.

03_reversion_OPERATIVA.sql elimina solamente la RPC; conserva estado, auditoria,
autorizaciones y movimientos. No reactiva ventas ni vuelve a descontar ingredientes.
Reinstalacion: solo 02 tras revisar estructura existente. No es rollback destructivo.

Validacion local: los siete scripts pasan parse_sql/parse_plpgsql de pglast.
No se ejecutaron contra PostgreSQL; por tanto bloqueos, privilegios efectivos y
restricciones instaladas requieren la validacion aislada indicada. No se ejecuta
Flutter analyze/test porque este trabajo no modifica Dart. Sin SQL remoto ni APK.
