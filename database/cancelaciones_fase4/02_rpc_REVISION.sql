-- LOCAL, como postgres despues de 01. No modifica las RPC existentes.
BEGIN;
DO $pre$ BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
END; $pre$;
CREATE FUNCTION public.cancelar_venta(p_venta_id integer, p_motivo text, p_reintegrar boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $rpc$
DECLARE
 actor uuid:=auth.uid(); ctx record; v record; inicial record; turno record;
 consumo record; lote record; lote_id_bloqueado bigint;
 fecha_comercial date; instante timestamptz;
BEGIN
 IF actor IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
  RAISE EXCEPTION 'Se requiere sesion autenticada' USING ERRCODE='42501'; END IF;
 IF p_venta_id IS NULL OR p_venta_id<=0 OR nullif(btrim(p_motivo),'') IS NULL OR p_reintegrar IS NULL THEN
  RAISE EXCEPTION 'Venta, motivo o reintegro invalido' USING ERRCODE='22023'; END IF;
 -- Mantener perfil y habilitaciones estables hasta finalizar.
 PERFORM id FROM public.usuarios WHERE auth_uid=actor FOR SHARE;
 PERFORM e.id FROM public.empleados_pos e JOIN public.usuarios u ON u.id=e.usuario_id
  WHERE u.auth_uid=actor FOR SHARE OF e;
 PERFORM user_id FROM public.inventario_admins WHERE user_id=actor FOR SHARE;
 SELECT * INTO ctx FROM public.login_contexto_operativo();
 IF NOT FOUND OR ctx.admin IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Solo un administrador efectivo con empleado real activo puede cancelar' USING ERRCODE='42501'; END IF;
 SELECT id,sucursal_id,empresa_id,caja_turno_id INTO inicial FROM public.ventas WHERE id=p_venta_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Venta inexistente' USING ERRCODE='22023'; END IF;
 IF inicial.empresa_id IS DISTINCT FROM 'texas_burger' OR inicial.sucursal_id IS NULL OR
   (ctx.sucursal_id IS NOT NULL AND ctx.sucursal_id<>inicial.sucursal_id) THEN
  RAISE EXCEPTION 'Sucursal no autorizada' USING ERRCODE='42501'; END IF;
 PERFORM id FROM public.sucursales WHERE id=inicial.sucursal_id AND empresa_id='texas_burger'
  AND activo IS TRUE FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sucursal inactiva o inexistente' USING ERRCODE='42501'; END IF;
 PERFORM usuario_auth_id FROM public.cancelacion_permisos WHERE usuario_auth_id=actor
  AND sucursal_id=inicial.sucursal_id AND activo IS TRUE FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Falta permiso explicito de cancelacion para esta sucursal' USING ERRCODE='42501'; END IF;
 -- Si existe turno, conservar el orden turno -> venta -> lotes. Sin turno,
 -- bloquear directamente la venta; nunca buscar Caja por fechas o sucursal.
 IF inicial.caja_turno_id IS NOT NULL THEN
  SELECT * INTO turno FROM public.caja_turnos WHERE id=inicial.caja_turno_id FOR UPDATE;
  IF NOT FOUND OR turno.sucursal_id IS DISTINCT FROM inicial.sucursal_id OR turno.empresa_id IS DISTINCT FROM inicial.empresa_id THEN
   RAISE EXCEPTION 'Turno incompatible con la venta' USING ERRCODE='22023'; END IF;
 END IF;
 SELECT * INTO v FROM public.ventas WHERE id=p_venta_id FOR UPDATE;
 IF NOT FOUND OR v.sucursal_id IS DISTINCT FROM inicial.sucursal_id OR
   v.empresa_id IS DISTINCT FROM inicial.empresa_id OR v.caja_turno_id IS DISTINCT FROM inicial.caja_turno_id THEN
  RAISE EXCEPTION 'La venta cambio durante la operacion; revisar' USING ERRCODE='22023'; END IF;
 IF v.caja_turno_id IS NULL AND v.operacion_id IS NULL THEN
  RAISE EXCEPTION 'Venta historica sin turno ni identificacion transaccional: requiere revision de Caja' USING ERRCODE='22023'; END IF;
 IF v.estado='cancelada' THEN
  IF v.cancelacion_motivo IS DISTINCT FROM btrim(p_motivo) OR v.inventario_reintegrado IS DISTINCT FROM p_reintegrar THEN
   RAISE EXCEPTION 'Venta ya cancelada con otros parametros; no se cambia ni se reintegra de nuevo' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('estado','cancelada','venta_id',v.id,'repetida',true,
   'inventario_reintegrado',v.inventario_reintegrado,'cancelada_en',v.cancelada_en,'cancelada_por',v.cancelada_por);
 END IF;
 IF v.caja_turno_id IS NOT NULL THEN
  IF turno.fecha_cierre IS NOT NULL THEN
   RAISE EXCEPTION 'Turno cerrado: cancelacion ordinaria no permitida' USING ERRCODE='22023'; END IF;
 END IF;

 -- Nadie desde Flutter puede escribir estos movimientos. Bloquear los existentes
 -- para fijar la evidencia original; nunca recalcular usando producto_ingrediente.
 PERFORM id FROM public.inventario_movimientos WHERE venta_id=v.id ORDER BY id FOR UPDATE;
 IF EXISTS (SELECT FROM public.inventario_movimientos WHERE venta_id=v.id AND tipo<>'salida') THEN
  RAISE EXCEPTION 'La venta ya tiene entradas u otros movimientos: revisar antes de cancelar' USING ERRCODE='22023'; END IF;
 IF p_reintegrar THEN
  IF v.operacion_id IS NULL OR NOT EXISTS (SELECT FROM public.inventario_movimientos WHERE venta_id=v.id AND tipo='salida') THEN
   RAISE EXCEPTION 'No hay consumo transaccional verificable; no se inventan existencias' USING ERRCODE='22023'; END IF;
  -- Orden global identico al escritor de ventas para los lotes compartidos.
  FOR lote_id_bloqueado IN SELECT l.id FROM public.inventario_lotes l
   WHERE EXISTS (SELECT FROM public.inventario_movimientos m WHERE m.venta_id=v.id AND m.lote_id=l.id)
   ORDER BY l.ingrediente_id,l.fecha_caducidad,l.fecha_entrada,l.id FOR UPDATE LOOP
   NULL;
  END LOOP;
  instante:=clock_timestamp(); fecha_comercial:=(instante AT TIME ZONE 'America/Monterrey')::date;
  FOR consumo IN SELECT lote_id,sum(cantidad) cantidad FROM public.inventario_movimientos
   WHERE venta_id=v.id AND tipo='salida' GROUP BY lote_id ORDER BY lote_id LOOP
   SELECT * INTO lote FROM public.inventario_lotes WHERE id=consumo.lote_id;
   IF NOT FOUND OR lote.sucursal_id IS DISTINCT FROM v.sucursal_id OR consumo.cantidad<=0 OR
     lote.cantidad_disponible+consumo.cantidad>lote.cantidad_inicial THEN
    RAISE EXCEPTION 'Lote no admite reintegro o pertenece a otra sucursal' USING ERRCODE='22023'; END IF;
   IF lote.fecha_caducidad IS NULL OR lote.fecha_caducidad<fecha_comercial THEN
    RAISE EXCEPTION 'Lote caducado: no se reintegra. Revisar cancelacion sin reintegro' USING ERRCODE='22023'; END IF;
   IF EXISTS (SELECT FROM public.inventario_movimientos m WHERE m.venta_id=v.id AND m.lote_id=lote.id
     AND (m.actor_uid IS DISTINCT FROM v.operacion_actor OR m.cantidad_antes-m.cantidad_despues<>m.cantidad)) THEN
    RAISE EXCEPTION 'Consumo original inconsistente' USING ERRCODE='22023'; END IF;
   UPDATE public.inventario_lotes SET cantidad_disponible=cantidad_disponible+consumo.cantidad WHERE id=lote.id;
   INSERT INTO public.inventario_movimientos(lote_id,tipo,cantidad,cantidad_antes,cantidad_despues,motivo,actor_uid,venta_id)
   VALUES(lote.id,'entrada',consumo.cantidad,lote.cantidad_disponible,lote.cantidad_disponible+consumo.cantidad,
    'Cancelacion venta '||v.id||': '||btrim(p_motivo),actor,v.id);
  END LOOP;
 END IF;
 instante:=coalesce(instante,clock_timestamp());
 UPDATE public.ventas SET estado='cancelada',cancelada_en=instante,cancelada_por=actor,
  cancelacion_motivo=btrim(p_motivo),inventario_reintegrado=p_reintegrar WHERE id=v.id;
 RETURN jsonb_build_object('estado','cancelada','venta_id',v.id,'repetida',false,
  'inventario_reintegrado',p_reintegrar,'cancelada_en',instante,'cancelada_por',actor);
 -- No EXCEPTION que oculte fallos: todo se revierte junto si falla cualquier paso.
END;
$rpc$;
ALTER FUNCTION public.cancelar_venta(integer,text,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.cancelar_venta(integer,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
DO $acl$
DECLARE r record;
BEGIN
 FOR r IN SELECT DISTINCT roles.rolname FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
 JOIN pg_roles roles ON roles.oid=a.grantee WHERE p.oid='public.cancelar_venta(integer,text,boolean)'::regprocedure
 AND a.grantee<>p.proowner LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION public.cancelar_venta(integer,text,boolean) FROM %I',r.rolname);
 END LOOP;
END;
$acl$;
GRANT EXECUTE ON FUNCTION public.cancelar_venta(integer,text,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
