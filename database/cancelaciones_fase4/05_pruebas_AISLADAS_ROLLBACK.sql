-- NUNCA ejecutar en Supabase compartido. Solo copia/base AISLADA como postgres.
-- Completar IDs de identidades de prueba y una venta transaccional activa con
-- salidas reales de prueba, turno abierto, lotes no caducados y capacidad de retorno.
-- Solo necesita UN admin general real de prueba (p.ej. copia aislada de Daniel)
-- y dos sucursales activas. Simula roles/asignaciones sobre ese perfil SOLO en
-- subtransacciones revertidas. No crea usuarios Auth, recetas ni ventas.
BEGIN;
CREATE TEMP TABLE cancelacion_test_config(venta integer,admin uuid,otra_sucursal text);
INSERT INTO cancelacion_test_config VALUES(NULL,NULL,NULL); -- completar
CREATE FUNCTION pg_temp.sesion_cancelacion(actor uuid) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
END; $f$;
CREATE FUNCTION pg_temp.estado_cancelacion() RETURNS jsonb LANGUAGE sql AS $f$
 SELECT jsonb_build_object(
 'ventas',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.ventas v),
 'detalles',(SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM public.detalle_venta d),
 'lotes',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.inventario_lotes l),
 'movimientos',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.inventario_movimientos m),
 'turnos',(SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM public.caja_turnos t),
 'caja_movimientos',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.caja_movimientos m))
$f$;
CREATE FUNCTION pg_temp.cancelacion_error(v integer,reintegrar boolean,codigo text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE antes jsonb:=pg_temp.estado_cancelacion(); fallo boolean:=false;
BEGIN
 BEGIN
  PERFORM public.cancelar_venta(v,'Prueba aislada',reintegrar);
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE<>codigo THEN RAISE; END IF;
  fallo:=true;
 END;
 IF NOT fallo OR pg_temp.estado_cancelacion() IS DISTINCT FROM antes THEN
  RAISE EXCEPTION 'No hubo rechazo esperado o existen efectos parciales'; END IF;
END; $f$;
DO $pre$
DECLARE c record; v record; p record;
BEGIN
 SELECT * INTO c FROM cancelacion_test_config;
 IF current_user<>'postgres' OR c.venta IS NULL OR c.admin IS NULL
  OR c.otra_sucursal IS NULL THEN RAISE EXCEPTION 'Completar fixture aislada'; END IF;
 SELECT * INTO v FROM public.ventas WHERE id=c.venta;
 IF NOT FOUND OR v.estado<>'activa' OR v.operacion_id IS NULL OR v.caja_turno_id IS NULL OR
  NOT EXISTS (SELECT FROM public.caja_turnos WHERE id=v.caja_turno_id AND fecha_cierre IS NULL) OR
  NOT EXISTS (SELECT FROM public.inventario_movimientos WHERE venta_id=v.id AND tipo='salida') THEN
  RAISE EXCEPTION 'Se requiere venta fase3 con consumo y turno abierto'; END IF;
 PERFORM pg_temp.sesion_cancelacion(c.admin);
 SELECT * INTO p FROM public.login_contexto_operativo();
 IF NOT FOUND OR NOT p.admin OR p.sucursal_id IS NOT NULL THEN
  RAISE EXCEPTION 'Se requiere un administrador general efectivo de prueba'; END IF;
 IF c.otra_sucursal=v.sucursal_id OR NOT EXISTS (SELECT FROM public.sucursales
   WHERE id=c.otra_sucursal AND activo AND empresa_id='texas_burger') THEN
  RAISE EXCEPTION 'Configurar otra sucursal activa distinta de la venta'; END IF;
 -- Solo fixture aislada; no conceder estos permisos en produccion por copiar pruebas.
 INSERT INTO public.cancelacion_permisos(usuario_auth_id,sucursal_id,activo)
 VALUES(c.admin,v.sucursal_id,true)
 ON CONFLICT(usuario_auth_id,sucursal_id) DO UPDATE SET activo=true;
END; $pre$;
DO $casos$
DECLARE c record; v record; nombre text; r jsonb; antes jsonb; stock jsonb; caja jsonb; movimientos bigint;
BEGIN
 SELECT * INTO c FROM cancelacion_test_config; SELECT * INTO v FROM public.ventas WHERE id=c.venta;
 FOREACH nombre IN ARRAY ARRAY['cajero','otra_sucursal','general_sin_permiso','inexistente',
  'sin_turno','sin_turno_reintegro','historica_sin_turno','turno_cerrado','sin_consumo','exceso','caducado','sin_reintegro','con_reintegro'] LOOP
  BEGIN
   PERFORM pg_temp.sesion_cancelacion(c.admin);
   CASE nombre
   WHEN 'cajero' THEN
    UPDATE public.usuarios SET rol='cajero',sucursal_id=v.sucursal_id WHERE auth_uid=c.admin;
    PERFORM pg_temp.cancelacion_error(v.id,false,'42501');
   WHEN 'otra_sucursal' THEN
    UPDATE public.usuarios SET sucursal_id=c.otra_sucursal WHERE auth_uid=c.admin;
    PERFORM pg_temp.cancelacion_error(v.id,false,'42501');
   WHEN 'general_sin_permiso' THEN
    DELETE FROM public.cancelacion_permisos WHERE usuario_auth_id=c.admin;
    PERFORM pg_temp.cancelacion_error(v.id,false,'42501');
   WHEN 'inexistente' THEN
    -- ID negativo valida entrada; usar un positivo inexistente para probar busqueda.
    PERFORM pg_temp.cancelacion_error((SELECT coalesce(max(id),0)+1 FROM public.ventas),false,'22023');
   WHEN 'sin_turno', 'sin_turno_reintegro' THEN
    UPDATE public.ventas SET caja_turno_id=NULL WHERE id=v.id;
    caja:=pg_temp.estado_cancelacion()-ARRAY['ventas','detalles','lotes','movimientos'];
    r:=public.cancelar_venta(v.id,'Prueba aislada',nombre='sin_turno_reintegro');
    IF r->>'estado'<>'cancelada' OR (r->>'inventario_reintegrado')::boolean<>(nombre='sin_turno_reintegro')
     OR caja IS DISTINCT FROM (pg_temp.estado_cancelacion()-ARRAY['ventas','detalles','lotes','movimientos']) THEN
     RAISE EXCEPTION 'Cancelacion sin turno incorrecta o modifico Caja'; END IF;
    antes:=pg_temp.estado_cancelacion();
    r:=public.cancelar_venta(v.id,'Prueba aislada',nombre='sin_turno_reintegro');
    IF r->>'repetida'<>'true' OR antes IS DISTINCT FROM pg_temp.estado_cancelacion() THEN
     RAISE EXCEPTION 'Repeticion sin turno modifico datos'; END IF;
   WHEN 'historica_sin_turno' THEN
    UPDATE public.ventas SET caja_turno_id=NULL,operacion_id=NULL,operacion_actor=NULL,operacion_solicitud=NULL WHERE id=v.id;
    PERFORM pg_temp.cancelacion_error(v.id,false,'22023');
   WHEN 'turno_cerrado' THEN
    -- Completar campos coherentes con CHECK de cierre, sin invocar RPC remota.
    UPDATE public.caja_turnos SET fecha_cierre=greatest(now(),fecha_apertura),
     efectivo_contado=greatest(efectivo_esperado,0),
     diferencia=greatest(efectivo_esperado,0)-efectivo_esperado,cierre_actor_uid=c.admin
    WHERE id=v.caja_turno_id;
    PERFORM pg_temp.cancelacion_error(v.id,false,'22023');
   WHEN 'sin_consumo' THEN
    DELETE FROM public.inventario_movimientos WHERE venta_id=v.id;
    UPDATE public.ventas SET operacion_id=NULL,operacion_actor=NULL,operacion_solicitud=NULL WHERE id=v.id;
    PERFORM pg_temp.cancelacion_error(v.id,true,'22023');
    r:=public.cancelar_venta(v.id,'Prueba aislada',false);
    IF r->>'inventario_reintegrado'<>'false' THEN RAISE EXCEPTION 'Reintegro ficticio'; END IF;
   WHEN 'exceso' THEN
    UPDATE public.inventario_lotes SET cantidad_disponible=cantidad_inicial
    WHERE id IN (SELECT lote_id FROM public.inventario_movimientos WHERE venta_id=v.id);
    PERFORM pg_temp.cancelacion_error(v.id,true,'22023');
   WHEN 'caducado' THEN
    UPDATE public.inventario_lotes SET fecha_entrada=(now() AT TIME ZONE 'America/Monterrey')::date-2,
     fecha_caducidad=(now() AT TIME ZONE 'America/Monterrey')::date-1
    WHERE id IN (SELECT lote_id FROM public.inventario_movimientos WHERE venta_id=v.id);
    PERFORM pg_temp.cancelacion_error(v.id,true,'22023');
   WHEN 'sin_reintegro' THEN
    SELECT jsonb_agg(to_jsonb(l) ORDER BY id) INTO stock FROM public.inventario_lotes l;
    SELECT count(*) INTO movimientos FROM public.inventario_movimientos;
    r:=public.cancelar_venta(v.id,'Prueba aislada'); -- default false
    IF r->>'estado'<>'cancelada' OR r->>'inventario_reintegrado'<>'false' OR
      stock IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.inventario_lotes l) OR
      movimientos<>(SELECT count(*) FROM public.inventario_movimientos) THEN RAISE EXCEPTION 'Sin reintegro modifico stock'; END IF;
   WHEN 'con_reintegro' THEN
    r:=public.cancelar_venta(v.id,'Prueba aislada',true);
    IF r->>'estado'<>'cancelada' OR r->>'inventario_reintegrado'<>'true' THEN RAISE EXCEPTION 'No cancelo'; END IF;
    IF EXISTS (SELECT lote_id FROM public.inventario_movimientos WHERE venta_id=v.id GROUP BY lote_id
      HAVING sum(cantidad) FILTER(WHERE tipo='salida') IS DISTINCT FROM sum(cantidad) FILTER(WHERE tipo='entrada')) THEN
      RAISE EXCEPTION 'Reintegro no corresponde al consumo original'; END IF;
    antes:=pg_temp.estado_cancelacion(); r:=public.cancelar_venta(v.id,'Prueba aislada',true);
    IF r->>'repetida'<>'true' OR antes IS DISTINCT FROM pg_temp.estado_cancelacion() THEN
      RAISE EXCEPTION 'Cancelacion repetida modifico datos'; END IF;
    PERFORM pg_temp.cancelacion_error(v.id,false,'22023');
   END CASE;
   RAISE NOTICE 'OK %',nombre;
   RAISE EXCEPTION 'Revertir caso de prueba' USING ERRCODE='P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
  END;
 END LOOP;
END; $casos$;
-- Error despues del UPDATE de lote: debe revertir TODO.
CREATE FUNCTION pg_temp.fallar_reintegro() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN RAISE EXCEPTION 'Fallo inyectado' USING ERRCODE='P0099'; END; $f$;
CREATE TRIGGER fase4_fallo_test BEFORE INSERT ON public.inventario_movimientos
FOR EACH ROW WHEN (NEW.venta_id IS NOT NULL AND NEW.tipo='entrada') EXECUTE FUNCTION pg_temp.fallar_reintegro();
SELECT pg_temp.sesion_cancelacion(admin) FROM cancelacion_test_config;
SELECT pg_temp.cancelacion_error(venta,true,'P0099') FROM cancelacion_test_config;
DROP TRIGGER fase4_fallo_test ON public.inventario_movimientos;
GRANT SELECT ON cancelacion_test_config TO authenticated;
SET LOCAL ROLE authenticated;
SELECT public.cancelar_venta(venta,'Prueba aislada',true) FROM cancelacion_test_config;
RESET ROLE;
ROLLBACK;
