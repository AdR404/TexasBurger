-- SOLO BASE DESECHABLE, dos conexiones. BLOQUES independientes, no ejecutar todo.
-- Fixture de turno abierto y admin efectivo, venta fase3 vinculada Tarjeta o
-- Este archivo SI llama RPC de negocio (cierre/cancelacion). El 04 crea ventas
-- y cancelaciones con INSERT/UPDATE sinteticos: no prueba cancelar_venta completa.
-- Transferencia; si se prueba cancelar, permiso explicito YA configurado en fixture.
-- No habilitar permisos en Supabase principal. UUID, TURNO_ID, VENTA_ID y HUELLA
-- son marcadores que deben sustituirse. HUELLA se obtiene antes de iniciar A.
-- Para venta real de prueba en B, receta y stock previamente configurados en aislado.

-- A: cierre que gana el bloqueo.
BEGIN;
SELECT set_config('request.jwt.claim.sub','UUID',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','UUID','role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
SELECT public.caja_cerrar_turno_verificado('TURNO_ID'::bigint,'HUELLA',100,'Prueba concurrencia');
SELECT pg_sleep(15); -- iniciar B durante espera
COMMIT; -- SOLO aislado

-- B1: cancelacion intenta entrar despues de A; espera y rechaza turno cerrado.
BEGIN;
SET LOCAL statement_timeout='60s';
SELECT set_config('request.jwt.claim.sub','UUID',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','UUID','role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
SELECT public.cancelar_venta('VENTA_ID'::integer,'Prueba',false);
ROLLBACK;

-- B2 (otro escenario, fixture restablecida): iniciar durante la espera A.
-- Mismos BEGIN/claims/SET ROLE de B1; ejecutar esta llamada en vez de cancelar:
-- SELECT public.registrar_venta_con_consumo('OPERACION_UUID'::uuid,'SOLICITUD_JSON'::jsonb);
-- COMMIT; -- SOLO aislado
-- Esperado: espera al turno, despues venta sin turno (o nuevo turno si fue abierto
-- entretanto), nunca altera totales del turno cerrado. Revisar caja_turno_id.

-- Orden inverso (restablecer fixture y tomar HUELLA anterior): A llama primero
-- cancelar_venta con Tarjeta, o registrar_venta_con_consumo; mantiene transaccion
-- abierta con pg_sleep y confirma. B llama cierre verificado con HUELLA vieja:
-- debe esperar y devolver 40001. Actualizar resumen y revisar conteo antes de cerrar.
-- Para cada escenario comparar snapshots de turno/ventas/movimientos: no cortes
-- parciales, no doble cierre y no escrituras en turnos cerrados.
-- Probar tambien dos cierres simultaneos: primero confirma, segundo 22023.
-- Repetir con conciliacion de Efectivo en A y cierre con huella ANTERIOR en B:
-- A: caja_conciliar_efectivo_cancelado(VENTA_ID,'devuelto','Confirmacion aislada',true),
-- mantener transaccion abierta y confirmar. B espera y rechaza huella vieja.
-- Repetir escritor antiguo INSERT de cabecera mientras cierre retiene SHARE:
-- INSERT espera al COMMIT. NO se promete capturar escrituras retroactivas despues
-- del cierre; detener cobros antiguos al contar/cerrar es requisito transitorio.
-- Comparar tambien cierre de dos sucursales simultaneas: los SHARE son compatibles,
-- ambos cierres deben terminar sin interbloqueo con las RPC previstas.

-- Comprobaciones de SOLO LECTURA como postgres tras cada escenario:
SELECT id,fecha_cierre,total_ventas,numero_ordenes,efectivo_esperado
FROM public.caja_turnos WHERE id='TURNO_ID'::bigint;
SELECT id,estado,caja_turno_id,total FROM public.ventas
WHERE id='VENTA_ID'::integer OR operacion_id='OPERACION_UUID'::uuid;
SELECT * FROM public.caja_movimientos WHERE turno_id='TURNO_ID'::bigint ORDER BY id;
