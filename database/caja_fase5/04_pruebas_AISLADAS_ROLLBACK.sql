-- SOLO BASE DESECHABLE. Como postgres. Sin Supabase principal.
-- Fixture: permiso activo en cancelacion_permisos para la sucursal del turno.
-- Fixture: admin efectivo y turno ABIERTO de su sucursal sin ventas vinculadas
-- ni legado en periodo. Puede tener movimientos de entrada/salida existentes.
-- Se insertan ventas sinteticas SOLO financieras en transaccion revertida;
-- no simulan recetas ni consumos y no deben confundirse con ventas reales.
BEGIN;
CREATE TEMP TABLE caja_test_config(actor uuid,turno bigint);
INSERT INTO caja_test_config VALUES(NULL,NULL); -- completar fixture aislada
CREATE FUNCTION pg_temp.estado_caja_test() RETURNS jsonb LANGUAGE sql AS $f$
 SELECT jsonb_build_object('turnos',(SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM public.caja_turnos t),
 'movimientos',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.caja_movimientos m),
 'ventas',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.ventas v))
$f$;
CREATE FUNCTION pg_temp.cierre_error(t bigint,h text,codigo text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE antes jsonb:=pg_temp.estado_caja_test(); fallo boolean:=false;
BEGIN
 BEGIN
  PERFORM public.caja_cerrar_turno_verificado(t,h,0,'Prueba');
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE<>codigo THEN RAISE; END IF; fallo:=true;
 END;
 IF NOT fallo OR antes IS DISTINCT FROM pg_temp.estado_caja_test() THEN
  RAISE EXCEPTION 'Error esperado ausente o cambios parciales'; END IF;
END; $f$;
DO $pre$
DECLARE c record; r jsonb;
BEGIN
 SELECT * INTO c FROM caja_test_config;
 IF current_user<>'postgres' OR c.actor IS NULL OR c.turno IS NULL THEN RAISE EXCEPTION 'Completar fixture aislada'; END IF;
 PERFORM set_config('request.jwt.claim.sub',c.actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',c.actor,'role','authenticated')::text,true);
 r:=public.caja_resumen_turno(c.turno);
 IF (r->>'cerrado')::boolean OR (r->>'ordenes_validas')::integer<>0 OR (r->>'ordenes_canceladas')::integer<>0
  OR jsonb_array_length(r->'legado_sin_vinculo')<>0 THEN RAISE EXCEPTION 'Turno de fixture debe estar abierto y sin ventas'; END IF;
END; $pre$;
CREATE TEMP TABLE caja_test_ventas(id integer,metodo text);
WITH nuevas AS (
 INSERT INTO public.ventas(usuario_id,fecha_hora,total,metodo_pago,empresa_id,empresa_nombre,sucursal_id,sucursal_nombre,
 empleado_pos_id,empleado_nombre,operacion_id,operacion_actor,operacion_solicitud,caja_turno_id)
 SELECT p.usuario_id,clock_timestamp() AT TIME ZONE 'America/Monterrey',x.importe,x.metodo,
 t.empresa_id,'Texas Burger',t.sucursal_id,t.sucursal_nombre,p.empleado_id,p.empleado_nombre,
 gen_random_uuid(),c.actor,'{}'::jsonb,t.id
 FROM caja_test_config c JOIN public.caja_turnos t ON t.id=c.turno
 CROSS JOIN public.login_contexto_operativo() p
 CROSS JOIN (VALUES('Efectivo',100::numeric),('Tarjeta',200::numeric),('Transferencia',300::numeric)) x(metodo,importe)
 RETURNING id,metodo_pago
) INSERT INTO caja_test_ventas SELECT id,metodo_pago FROM nuevas;
DO $casos$
DECLARE c record; caso text; r jsonb; antes jsonb; n bigint; t record; cash_id integer; card_id integer;
BEGIN
 SELECT * INTO c FROM caja_test_config;
 SELECT id INTO cash_id FROM caja_test_ventas WHERE metodo='Efectivo';
 SELECT id INTO card_id FROM caja_test_ventas WHERE metodo='Tarjeta';
 FOREACH caso IN ARRAY ARRAY['normal','cancelada_tarjeta','cancelada_efectivo','efectivo_no_cobrado','efectivo_devuelto','sin_turno','legado','antiguo','antiguo_cancelada','obsoleto','movimiento_obsoleto'] LOOP
  BEGIN
   r:=public.caja_resumen_turno(c.turno);
   CASE caso
    WHEN 'normal' THEN NULL;
    WHEN 'cancelada_tarjeta' THEN
     UPDATE public.ventas SET estado='cancelada',cancelada_en=now(),cancelada_por=c.actor,cancelacion_motivo='Prueba' WHERE id=card_id;
     r:=public.caja_resumen_turno(c.turno);
     IF (r->>'total_bruto')::numeric<>600 OR (r->>'total_cancelado')::numeric<>200
      OR (r->>'total_neto')::numeric<>400 OR (r->>'ordenes_validas')::integer<>2 THEN RAISE EXCEPTION 'Neto incorrecto'; END IF;
    WHEN 'cancelada_efectivo' THEN
     UPDATE public.ventas SET estado='cancelada',cancelada_en=now(),cancelada_por=c.actor,cancelacion_motivo='Prueba' WHERE id=cash_id;
     r:=public.caja_resumen_turno(c.turno); PERFORM pg_temp.cierre_error(c.turno,r->>'huella','22023');
    WHEN 'efectivo_no_cobrado','efectivo_devuelto' THEN
     -- UPDATE sintetico de cancelacion; NO prueba la RPC cancelar_venta.
     UPDATE public.ventas SET estado='cancelada',cancelada_en=now(),cancelada_por=c.actor,cancelacion_motivo='Prueba' WHERE id=cash_id;
     antes:=pg_temp.estado_caja_test()->'movimientos';
     BEGIN
      PERFORM public.caja_conciliar_efectivo_cancelado(cash_id,'devuelto','Falta declaracion',false);
      RAISE EXCEPTION 'Acepto conciliacion sin confirmacion explicita';
     EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
     END;
     IF (SELECT efectivo_cancelacion_estado FROM public.ventas WHERE id=cash_id) IS NOT NULL THEN
      RAISE EXCEPTION 'Persistio confirmacion rechazada'; END IF;
     PERFORM public.caja_conciliar_efectivo_cancelado(cash_id,
       CASE WHEN caso='efectivo_no_cobrado' THEN 'no_cobrado' ELSE 'devuelto' END,'Declaracion aislada sin salida adicional',true);
     IF antes IS DISTINCT FROM pg_temp.estado_caja_test()->'movimientos' THEN RAISE EXCEPTION 'Conciliacion genero dinero'; END IF;
     r:=public.caja_resumen_turno(c.turno);
     IF (r->>'efectivo_cancelado_sin_conciliar')::numeric<>0 OR (r->>'total_neto')::numeric<>500 THEN RAISE EXCEPTION 'Conciliacion o neto incorrectos'; END IF;
    WHEN 'sin_turno' THEN
     UPDATE public.ventas SET caja_turno_id=NULL,estado='cancelada',cancelada_en=now(),cancelada_por=c.actor,cancelacion_motivo='Prueba' WHERE id=card_id;
     r:=public.caja_resumen_turno(c.turno);
     IF (r->>'total_bruto')::numeric<>400 OR (r->>'total_cancelado')::numeric<>0 THEN RAISE EXCEPTION 'Incorporo venta sin turno'; END IF;
    WHEN 'legado' THEN
     UPDATE public.ventas SET caja_turno_id=NULL,operacion_id=NULL,operacion_actor=NULL,operacion_solicitud=NULL WHERE id=card_id;
     r:=public.caja_resumen_turno(c.turno);
     IF jsonb_array_length(r->'legado_sin_vinculo')<>1 THEN RAISE EXCEPTION 'Legado no advertido'; END IF;
     IF (r->>'total_neto')::numeric<>600 THEN RAISE EXCEPTION 'Perdio venta antigua'; END IF;
    WHEN 'antiguo' THEN
     UPDATE public.ventas SET caja_turno_id=NULL,operacion_id=NULL,operacion_actor=NULL,operacion_solicitud=NULL WHERE id IN (SELECT id FROM caja_test_ventas);
     BEGIN
      PERFORM public.caja_cerrar_turno(c.turno,99,200,300,3,100,'Total incorrecto');
      RAISE EXCEPTION 'Acepto total cliente incorrecto';
     EXCEPTION WHEN SQLSTATE '40001' THEN NULL;
     END;
     n:=public.caja_cerrar_turno(c.turno,100,200,300,3,100,'Cliente antiguo');
     IF (SELECT total_ventas FROM public.caja_turnos WHERE id=n)<>600 THEN RAISE EXCEPTION 'Cierre antiguo perdio ventas'; END IF;
    WHEN 'antiguo_cancelada' THEN
     UPDATE public.ventas SET estado='cancelada',cancelada_en=now(),cancelada_por=c.actor,cancelacion_motivo='Prueba' WHERE id=card_id;
     BEGIN
      PERFORM public.caja_cerrar_turno(c.turno,100,200,300,3,100,'Intento de bypass');
      RAISE EXCEPTION 'El cierre antiguo permitio eludir cancelacion';
     EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
     END;
     IF (SELECT fecha_cierre FROM public.caja_turnos WHERE id=c.turno) IS NOT NULL THEN RAISE EXCEPTION 'Cerro por via antigua'; END IF;
    WHEN 'obsoleto' THEN
     UPDATE public.ventas SET estado='cancelada',cancelada_en=now(),cancelada_por=c.actor,cancelacion_motivo='Prueba' WHERE id=card_id;
     PERFORM pg_temp.cierre_error(c.turno,r->>'huella','40001');
    WHEN 'movimiento_obsoleto' THEN
     PERFORM public.caja_registrar_movimiento(c.turno,'entrada',10,'Prueba aislada');
     PERFORM public.caja_registrar_movimiento(c.turno,'salida',3,'Prueba aislada');
     PERFORM pg_temp.cierre_error(c.turno,r->>'huella','40001');
     r:=public.caja_resumen_turno(c.turno);
   END CASE;
   IF caso IN ('normal','cancelada_tarjeta','efectivo_no_cobrado','efectivo_devuelto','sin_turno','legado','movimiento_obsoleto') THEN
    antes:=pg_temp.estado_caja_test()->'movimientos';
    n:=public.caja_cerrar_turno_verificado(c.turno,r->>'huella',100,'Prueba');
    SELECT * INTO t FROM public.caja_turnos WHERE id=n;
    IF t.total_ventas<>(r->>'total_neto')::numeric OR t.numero_ordenes<>(r->>'ordenes_validas')::integer
      OR t.efectivo_esperado<>(r->>'efectivo_base_neta')::numeric
      OR antes IS DISTINCT FROM pg_temp.estado_caja_test()->'movimientos' THEN RAISE EXCEPTION 'Cierre o movimientos incorrectos'; END IF;
    PERFORM pg_temp.cierre_error(c.turno,r->>'huella','22023');
   END IF;
   RAISE NOTICE 'OK %',caso;
   RAISE EXCEPTION 'Revertir escenario' USING ERRCODE='P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
  END;
 END LOOP;
END; $casos$;
ROLLBACK;
