-- GUIA EJECUTABLE POR BLOQUES. SOLO BASE DE PRUEBAS AISLADA, como postgres.
-- Requiere dos conexiones SQL independientes (psql/cliente local), no una sola
-- transaccion en SQL Editor. NO ejecutar este archivo completo de una vez.
-- Preparar fixture: cajero real de prueba, producto/receta reales, dos lotes FEFO,
-- stock total exactamente suficiente para UNA solicitud, sucursal sin otras ventas.
-- Guardar conteos de ventas/detalles/movimientos y saldos ANTES de ambas sesiones.
-- Copiar un UUID actor y JSON valido de 05; no contiene contrasenas ni tokens.

-- SESION A: sustituir ACTOR_UUID, OPERACION_A_UUID y SOLICITUD_JSON.
BEGIN;
SET LOCAL request.jwt.claim.role = 'authenticated';
SELECT set_config('request.jwt.claim.sub','ACTOR_UUID',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','ACTOR_UUID','role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
SELECT public.registrar_venta_con_consumo('OPERACION_A_UUID'::uuid,'SOLICITUD_JSON'::jsonb);
-- Mientras espera, ejecutar B en otra conexion.
SELECT pg_sleep(15);
COMMIT; -- SOLO fixture aislada. Necesario para que B vea el saldo confirmado.

-- SESION B: mismo actor/sucursal/JSON; otro UUID. Iniciar durante la espera A.
BEGIN;
SET LOCAL statement_timeout = '60s';
SET LOCAL request.jwt.claim.role = 'authenticated';
SELECT set_config('request.jwt.claim.sub','ACTOR_UUID',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','ACTOR_UUID','role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
SELECT public.registrar_venta_con_consumo('OPERACION_B_UUID'::uuid,'SOLICITUD_JSON'::jsonb);
-- Esperado: espera A, despues error 22023 stock insuficiente; ninguna venta B.
ROLLBACK;

-- REPETIR escenario en fixture restablecida con OPERACION_A_UUID en AMBAS
-- conexiones: B espera y devuelve MISMO venta_id con repetida=true, sin consumo extra.
-- Misma clave con JSON diferente: 22023, tampoco crea otra venta.
-- Conectar como postgres para estas comprobaciones de SOLO LECTURA:
SELECT operacion_id,count(*) FROM public.ventas
WHERE operacion_id IN ('OPERACION_A_UUID'::uuid,'OPERACION_B_UUID'::uuid) GROUP BY operacion_id;
SELECT v.operacion_id,m.lote_id,m.cantidad,m.cantidad_antes,m.cantidad_despues
FROM public.ventas v JOIN public.inventario_movimientos m ON m.venta_id=v.id
WHERE v.operacion_id IN ('OPERACION_A_UUID'::uuid,'OPERACION_B_UUID'::uuid) ORDER BY m.id;
SELECT id FROM public.inventario_lotes WHERE cantidad_disponible<0;
-- Comparar con snapshot inicial: exactamente UNA cabecera, sus detalles y consumo
-- de UNA solicitud, sin negativos. Restaurar/eliminar la BASE AISLADA al terminar,
-- nunca aplicar limpieza de fixtures en Supabase compartido.
