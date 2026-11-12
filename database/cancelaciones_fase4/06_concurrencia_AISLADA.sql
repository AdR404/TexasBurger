-- SOLO base desechable, DOS conexiones, ejecutar bloques por separado.
-- Fixture: venta activa con turno abierto y salidas fase3, stock reintegrable,
-- dos admins efectivos expresamente habilitados para la sucursal.
-- Puede usar las copias aisladas de Daniel y Rigoberto con una venta de Norte
-- y permiso explicito para ambos en Norte: no requiere un tercer administrador.
-- Sustituir UUID_A, UUID_B y VENTA_ID. Snapshot previo de lotes/movimientos/venta.
-- A:
BEGIN;
SELECT set_config('request.jwt.claim.sub','UUID_A',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','UUID_A','role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
SELECT public.cancelar_venta('VENTA_ID'::integer,'Prueba concurrente',true);
SELECT pg_sleep(15); -- iniciar B durante esta espera
COMMIT; -- Solo base aislada: permite que B observe la cancelacion confirmada.
-- B:
BEGIN;
SET LOCAL statement_timeout='60s';
SELECT set_config('request.jwt.claim.sub','UUID_B',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','UUID_B','role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
SELECT public.cancelar_venta('VENTA_ID'::integer,'Prueba concurrente',true);
-- Esperado: espera, devuelve repetida=true, preserva actor/fecha de A.
ROLLBACK;
-- Verificacion como postgres:
SELECT estado,cancelada_por,cancelada_en,inventario_reintegrado FROM public.ventas WHERE id='VENTA_ID'::integer;
SELECT lote_id,sum(cantidad) FILTER(WHERE tipo='salida') salidas,
 sum(cantidad) FILTER(WHERE tipo='entrada') entradas FROM public.inventario_movimientos
WHERE venta_id='VENTA_ID'::integer GROUP BY lote_id;
-- entradas=salidas, nunca dos reintegros. Actor de entradas debe ser UUID_A.
-- Repetir con distinto motivo o reintegrar=false en B: error 22023, sin cambios.
-- Repetir tambien con una venta fase3 activa cuyo caja_turno_id sea NULL:
-- mismo resultado de repeticion y un solo reintegro, coordinado por lock de venta.
-- Comparar snapshot de caja_turnos Y caja_movimientos antes/despues: sin cambios.
-- Carrera con cierre: si cierre obtiene lock de turno y confirma primero,
-- cancelar_venta debe esperar y rechazar con 22023. Si cancelacion obtiene lock
-- primero, cierre espera; los totales externos de Caja aun se ajustaran en fase5.
-- No ejecutar limpieza ni COMMIT de estas fixtures en el proyecto compartido.
