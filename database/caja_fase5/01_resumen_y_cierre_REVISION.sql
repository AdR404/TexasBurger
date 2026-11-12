-- LOCAL, no ejecutado. Primera instalacion: guardar antes el resultado de 00.
-- Conserva firma antigua; guarda su implementacion con nombre interno sin acceso cliente.
-- Requiere Login, Caja, ventas fase3 y estado de cancelacion fase4 instalados.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $pre$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('public.login_contexto_operativo()') IS NULL
 OR to_regprocedure('public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)') IS NULL THEN
  RAISE EXCEPTION 'Ejecutar como postgres con las dependencias instaladas'; END IF;
 IF NOT EXISTS (SELECT FROM pg_proc WHERE oid='public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)'::regprocedure
   AND proowner='postgres'::regrole AND prosecdef AND prorettype='bigint'::regtype) THEN
  RAISE EXCEPTION 'Cierre original distinto del inspeccionado; revisar antes de renombrar'; END IF;
END; $pre$;

ALTER TABLE public.ventas
 ADD COLUMN efectivo_cancelacion_estado text,
 ADD COLUMN efectivo_conciliado_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 ADD COLUMN efectivo_conciliado_en timestamptz,
 ADD COLUMN efectivo_conciliacion_nota text,
 ADD CONSTRAINT fase5_efectivo_conciliado CHECK (
  (efectivo_cancelacion_estado IS NULL AND efectivo_conciliado_por IS NULL
   AND efectivo_conciliado_en IS NULL AND efectivo_conciliacion_nota IS NULL)
  OR (efectivo_cancelacion_estado IS NOT NULL AND efectivo_cancelacion_estado IN ('no_cobrado','devuelto')
   AND estado IS NOT DISTINCT FROM 'cancelada' AND metodo_pago IS NOT DISTINCT FROM 'Efectivo' AND efectivo_conciliado_por IS NOT NULL
   AND efectivo_conciliado_en IS NOT NULL AND efectivo_conciliacion_nota IS NOT NULL
   AND length(btrim(efectivo_conciliacion_nota))>0));
DO $permisos$
DECLARE rol text; col text;
BEGIN
 FOREACH rol IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOREACH col IN ARRAY ARRAY['efectivo_cancelacion_estado','efectivo_conciliado_por','efectivo_conciliado_en','efectivo_conciliacion_nota'] LOOP
   IF has_column_privilege(rol,'public.ventas',col,'INSERT,UPDATE') THEN
    RAISE EXCEPTION 'Permisos amplios permitirian falsificar conciliacion'; END IF;
  END LOOP;
 END LOOP;
END; $permisos$;
ALTER FUNCTION public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)
 RENAME TO caja_cerrar_turno_base_fase5;
REVOKE ALL ON FUNCTION public.caja_cerrar_turno_base_fase5(bigint,numeric,numeric,numeric,integer,numeric,text) FROM PUBLIC;
DO $privada$
DECLARE r record;
BEGIN
 FOR r IN SELECT DISTINCT roles.rolname FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
 JOIN pg_roles roles ON roles.oid=a.grantee WHERE p.oid='public.caja_cerrar_turno_base_fase5(bigint,numeric,numeric,numeric,integer,numeric,text)'::regprocedure
 AND a.grantee<>p.proowner LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION public.caja_cerrar_turno_base_fase5(bigint,numeric,numeric,numeric,integer,numeric,text) FROM %I',r.rolname);
 END LOOP;
 IF has_function_privilege('anon','public.caja_cerrar_turno_base_fase5(bigint,numeric,numeric,numeric,integer,numeric,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.caja_cerrar_turno_base_fase5(bigint,numeric,numeric,numeric,integer,numeric,text)','EXECUTE') THEN
  RAISE EXCEPTION 'Permisos heredados permiten eludir el cierre protegido'; END IF;
END; $privada$;

CREATE FUNCTION public.caja_resumen_turno(p_turno_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE actor uuid:=auth.uid(); perfil record; turno record; ventas jsonb; movimientos jsonb;
 legado jsonb; metodos jsonb; bruto numeric; cancelado numeric; neto numeric;
 ordenes integer; anuladas integer; entradas numeric; salidas numeric; invalidas bigint;
 resumen jsonb;
BEGIN
 IF actor IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
  RAISE EXCEPTION 'Sesion autenticada requerida' USING ERRCODE='42501'; END IF;
 PERFORM id FROM public.usuarios WHERE auth_uid=actor FOR SHARE;
 PERFORM e.id FROM public.empleados_pos e JOIN public.usuarios u ON u.id=e.usuario_id
  WHERE u.auth_uid=actor FOR SHARE OF e;
 PERFORM user_id FROM public.inventario_admins WHERE user_id=actor FOR SHARE;
 SELECT * INTO perfil FROM public.login_contexto_operativo();
 IF NOT FOUND OR perfil.admin IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Administrador efectivo requerido para Caja' USING ERRCODE='42501'; END IF;
 -- SHARE coordina con ventas/cancelaciones/movimientos/cierre (FOR UPDATE).
 SELECT * INTO turno FROM public.caja_turnos WHERE id=p_turno_id FOR SHARE;
 IF NOT FOUND OR turno.empresa_id IS DISTINCT FROM 'texas_burger' OR
  (perfil.sucursal_id IS NOT NULL AND perfil.sucursal_id<>turno.sucursal_id) THEN
  RAISE EXCEPTION 'Turno inexistente o fuera de la sucursal autorizada' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.id,'total',v.total,'estado',v.estado,
  'metodo_pago',v.metodo_pago,'cancelada_en',v.cancelada_en,
  'efectivo_estado',v.efectivo_cancelacion_estado,'conciliado_por',v.efectivo_conciliado_por,
  'conciliado_en',v.efectivo_conciliado_en,'conciliacion_nota',v.efectivo_conciliacion_nota) ORDER BY v.id),'[]'::jsonb),
  count(*) FILTER(WHERE v.total IS NULL OR NOT(v.total>=0 AND v.total<100000000)
    OR v.metodo_pago IS NULL OR v.metodo_pago NOT IN ('Efectivo','Tarjeta','Transferencia')
    OR v.estado IS NULL OR v.estado NOT IN ('activa','cancelada')
    OR v.sucursal_id IS DISTINCT FROM turno.sucursal_id OR v.empresa_id IS DISTINCT FROM turno.empresa_id)
 INTO ventas,invalidas FROM public.ventas v WHERE v.caja_turno_id=turno.id OR
  (v.caja_turno_id IS NULL AND v.operacion_id IS NULL AND v.empresa_id=turno.empresa_id
   AND v.sucursal_id=turno.sucursal_id
   AND v.fecha_hora >= (turno.fecha_apertura AT TIME ZONE 'America/Monterrey')
   AND v.fecha_hora < (coalesce(turno.fecha_cierre,clock_timestamp()) AT TIME ZONE 'America/Monterrey'));
 IF invalidas>0 THEN RAISE EXCEPTION 'Ventas vinculadas con datos incompatibles; revisar' USING ERRCODE='22023'; END IF;
 SELECT coalesce(sum((x->>'total')::numeric),0),
  coalesce(sum((x->>'total')::numeric) FILTER(WHERE x->>'estado'='cancelada'),0),
  coalesce(sum((x->>'total')::numeric) FILTER(WHERE x->>'estado'='activa'),0),
  count(*) FILTER(WHERE x->>'estado'='activa'),count(*) FILTER(WHERE x->>'estado'='cancelada')
 INTO bruto,cancelado,neto,ordenes,anuladas FROM jsonb_array_elements(ventas) x;
 SELECT jsonb_object_agg(m.nombre,jsonb_build_object(
   'bruto',coalesce((SELECT sum((x->>'total')::numeric) FROM jsonb_array_elements(ventas) x WHERE x->>'metodo_pago'=m.nombre),0),
   'cancelado',coalesce((SELECT sum((x->>'total')::numeric) FROM jsonb_array_elements(ventas) x WHERE x->>'metodo_pago'=m.nombre AND x->>'estado'='cancelada'),0),
   'neto',coalesce((SELECT sum((x->>'total')::numeric) FROM jsonb_array_elements(ventas) x WHERE x->>'metodo_pago'=m.nombre AND x->>'estado'='activa'),0)))
 INTO metodos FROM unnest(ARRAY['Efectivo','Tarjeta','Transferencia']) AS m(nombre);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'tipo',tipo,'importe',importe) ORDER BY id),'[]'::jsonb),
  coalesce(sum(importe) FILTER(WHERE tipo='entrada'),0),coalesce(sum(importe) FILTER(WHERE tipo='salida'),0)
 INTO movimientos,entradas,salidas FROM public.caja_movimientos WHERE turno_id=turno.id;
 IF entradas IS DISTINCT FROM turno.entradas_total OR salidas IS DISTINCT FROM turno.salidas_total THEN
  RAISE EXCEPTION 'Acumulados de movimientos de Caja no coinciden; revisar' USING ERRCODE='22023'; END IF;
 -- Transicion: incluye legado con el filtro temporal YA usado por Flutter,
 -- sin escribir caja_turno_id. Se informa explicitamente. Fase3 sin turno FUERA.
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'total',total,'estado',estado,'metodo_pago',metodo_pago)
  ORDER BY id),'[]'::jsonb) INTO legado FROM public.ventas
 WHERE empresa_id=turno.empresa_id AND sucursal_id=turno.sucursal_id
  AND caja_turno_id IS NULL AND operacion_id IS NULL
  AND fecha_hora >= (turno.fecha_apertura AT TIME ZONE 'America/Monterrey')
  AND fecha_hora < (coalesce(turno.fecha_cierre,clock_timestamp()) AT TIME ZONE 'America/Monterrey');
 resumen:=jsonb_build_object('turno_id',turno.id,'cerrado',turno.fecha_cierre IS NOT NULL,
  'total_bruto',bruto,'total_cancelado',cancelado,'total_neto',neto,
  'ordenes_validas',ordenes,'ordenes_canceladas',anuladas,'por_metodo',metodos,
  'fondo_inicial',turno.fondo_inicial,'entradas',entradas,'salidas',salidas,
  'efectivo_cancelado_sin_conciliar',coalesce((SELECT sum((x->>'total')::numeric)
    FROM jsonb_array_elements(ventas) x WHERE x->>'estado'='cancelada' AND x->>'metodo_pago'='Efectivo'
      AND x->>'efectivo_estado' IS NULL),0),
  'legado_sin_vinculo',legado,
  'efectivo_base_neta',turno.fondo_inicial+entradas-salidas+(metodos->'Efectivo'->>'neto')::numeric,
  'corte_guardado',CASE WHEN turno.fecha_cierre IS NOT NULL THEN jsonb_build_object(
    'total_ventas',turno.total_ventas,'efectivo_esperado',turno.efectivo_esperado,
    'numero_ordenes',turno.numero_ordenes,'fecha_cierre',turno.fecha_cierre) ELSE NULL END);
 -- Huella de contenido, no token de autorizacion. Incluye identidades, no solo sumas.
 RETURN resumen || jsonb_build_object('huella',md5(jsonb_build_object(
  'resumen',resumen,'ventas',ventas,'movimientos',movimientos)::text));
END; $f$;

CREATE FUNCTION public.caja_cerrar_turno_verificado(p_turno_id bigint,p_huella text,
 p_efectivo_contado numeric,p_notas text DEFAULT '')
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE r jsonb; turno record; actor uuid:=auth.uid(); perfil record; resultado bigint;
BEGIN
 IF actor IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
  RAISE EXCEPTION 'Sesion autenticada requerida' USING ERRCODE='42501'; END IF;
 -- Igual orden de identidad que resumen, ventas y cancelacion.
 PERFORM id FROM public.usuarios WHERE auth_uid=actor FOR SHARE;
 PERFORM e.id FROM public.empleados_pos e JOIN public.usuarios u ON u.id=e.usuario_id
  WHERE u.auth_uid=actor FOR SHARE OF e;
 PERFORM user_id FROM public.inventario_admins WHERE user_id=actor FOR SHARE;
 SELECT * INTO perfil FROM public.login_contexto_operativo();
 IF NOT FOUND OR perfil.admin IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Administrador efectivo requerido' USING ERRCODE='42501'; END IF;
 IF p_efectivo_contado IS NULL OR NOT(p_efectivo_contado>=0 AND p_efectivo_contado<10000000000)
  OR p_efectivo_contado<>round(p_efectivo_contado,2) OR nullif(p_huella,'') IS NULL THEN
  RAISE EXCEPTION 'Conteo o resumen invalido' USING ERRCODE='22023'; END IF;
 SELECT * INTO turno FROM public.caja_turnos WHERE id=p_turno_id FOR UPDATE;
 IF NOT FOUND OR turno.empresa_id IS DISTINCT FROM 'texas_burger' OR
  (perfil.sucursal_id IS NOT NULL AND perfil.sucursal_id<>turno.sucursal_id) THEN
  RAISE EXCEPTION 'Turno no autorizado' USING ERRCODE='42501'; END IF;
 IF turno.fecha_cierre IS NOT NULL THEN RAISE EXCEPTION 'Turno ya cerrado' USING ERRCODE='22023'; END IF;
 -- El escritor antiguo no bloquea turno: detener INSERT mientras se comprueba
 -- legado y se cierra. No asigna filas ni retira sus permisos. Lock corto global.
 LOCK TABLE public.ventas IN SHARE MODE;
 r:=public.caja_resumen_turno(p_turno_id);
 IF (r->>'efectivo_cancelado_sin_conciliar')::numeric>0 THEN
  RAISE EXCEPTION 'Cancelaciones en efectivo pendientes de confirmacion administrativa' USING ERRCODE='22023'; END IF;
 IF p_huella IS DISTINCT FROM r->>'huella' THEN
  RAISE EXCEPTION 'Caja cambio: actualizar resumen y revisar conteo antes de cerrar' USING ERRCODE='40001'; END IF;
 -- Reutiliza exactamente el cierre existente, con importes calculados en servidor.
 resultado:=public.caja_cerrar_turno_base_fase5(p_turno_id,
  (r->'por_metodo'->'Efectivo'->>'neto')::numeric,
  (r->'por_metodo'->'Tarjeta'->>'neto')::numeric,
  (r->'por_metodo'->'Transferencia'->>'neto')::numeric,
  (r->>'ordenes_validas')::integer,p_efectivo_contado,p_notas);
 RETURN resultado;
END; $f$;

-- Firma intacta para Flutter anterior; con cancelaciones exige la via verificada.
CREATE FUNCTION public.caja_cerrar_turno(p_turno_id bigint,p_ventas_efectivo numeric,
 p_ventas_tarjeta numeric,p_ventas_transferencia numeric,p_numero_ordenes integer,
 p_efectivo_contado numeric,p_notas text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE r jsonb; actor uuid:=auth.uid(); perfil record; turno record;
BEGIN
 IF actor IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
  RAISE EXCEPTION 'Sesion autenticada requerida' USING ERRCODE='42501'; END IF;
 PERFORM id FROM public.usuarios WHERE auth_uid=actor FOR SHARE;
 PERFORM e.id FROM public.empleados_pos e JOIN public.usuarios u ON u.id=e.usuario_id WHERE u.auth_uid=actor FOR SHARE OF e;
 PERFORM user_id FROM public.inventario_admins WHERE user_id=actor FOR SHARE;
 SELECT * INTO perfil FROM public.login_contexto_operativo();
 IF NOT FOUND OR perfil.admin IS DISTINCT FROM true THEN RAISE EXCEPTION 'Admin requerido' USING ERRCODE='42501'; END IF;
 SELECT * INTO turno FROM public.caja_turnos WHERE id=p_turno_id FOR UPDATE;
 IF NOT FOUND OR turno.empresa_id IS DISTINCT FROM 'texas_burger' OR
  (perfil.sucursal_id IS NOT NULL AND perfil.sucursal_id<>turno.sucursal_id) THEN
  RAISE EXCEPTION 'Turno no autorizado' USING ERRCODE='42501'; END IF;
 IF turno.fecha_cierre IS NOT NULL THEN RAISE EXCEPTION 'Turno ya cerrado' USING ERRCODE='22023'; END IF;
 LOCK TABLE public.ventas IN SHARE MODE;
 r:=public.caja_resumen_turno(p_turno_id);
 IF (r->>'ordenes_canceladas')::integer>0 THEN
  RAISE EXCEPTION 'Este turno tiene cancelaciones: usar cierre verificado, no cierre anterior' USING ERRCODE='22023'; END IF;
 IF p_ventas_efectivo IS DISTINCT FROM (r->'por_metodo'->'Efectivo'->>'neto')::numeric OR
  p_ventas_tarjeta IS DISTINCT FROM (r->'por_metodo'->'Tarjeta'->>'neto')::numeric OR
  p_ventas_transferencia IS DISTINCT FROM (r->'por_metodo'->'Transferencia'->>'neto')::numeric OR
  p_numero_ordenes IS DISTINCT FROM (r->>'ordenes_validas')::integer THEN
  RAISE EXCEPTION 'Totales desactualizados o ventas fuera del turno: actualizar Caja' USING ERRCODE='40001'; END IF;
 RETURN public.caja_cerrar_turno_verificado(p_turno_id,r->>'huella',p_efectivo_contado,p_notas);
END; $f$;

CREATE FUNCTION public.caja_conciliar_efectivo_cancelado(p_venta_id integer,p_estado text,
 p_nota text,p_confirmo_sin_salida boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE actor uuid:=auth.uid(); perfil record; inicial record; v record; turno record;
BEGIN
 IF actor IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
  RAISE EXCEPTION 'Sesion autenticada requerida' USING ERRCODE='42501'; END IF;
 IF p_estado IS NULL OR p_estado NOT IN ('no_cobrado','devuelto') OR nullif(btrim(p_nota),'') IS NULL
  OR p_confirmo_sin_salida IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Confirmar estado, motivo y que NO existe salida de Caja adicional por esta devolucion' USING ERRCODE='22023'; END IF;
 PERFORM id FROM public.usuarios WHERE auth_uid=actor FOR SHARE;
 PERFORM e.id FROM public.empleados_pos e JOIN public.usuarios u ON u.id=e.usuario_id WHERE u.auth_uid=actor FOR SHARE OF e;
 PERFORM user_id FROM public.inventario_admins WHERE user_id=actor FOR SHARE;
 SELECT * INTO perfil FROM public.login_contexto_operativo();
 IF NOT FOUND OR perfil.admin IS DISTINCT FROM true THEN RAISE EXCEPTION 'Admin requerido' USING ERRCODE='42501'; END IF;
 SELECT id,sucursal_id,caja_turno_id,empresa_id INTO inicial FROM public.ventas WHERE id=p_venta_id;
 IF NOT FOUND OR inicial.empresa_id IS DISTINCT FROM 'texas_burger' OR inicial.sucursal_id IS NULL OR
  (perfil.sucursal_id IS NOT NULL AND perfil.sucursal_id<>inicial.sucursal_id) THEN
  RAISE EXCEPTION 'Venta no autorizada' USING ERRCODE='42501'; END IF;
 PERFORM usuario_auth_id FROM public.cancelacion_permisos
  WHERE usuario_auth_id=actor AND sucursal_id=inicial.sucursal_id AND activo IS TRUE FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Falta permiso explicito de cancelacion para esta sucursal' USING ERRCODE='42501'; END IF;
 IF inicial.caja_turno_id IS NOT NULL THEN
  SELECT * INTO turno FROM public.caja_turnos WHERE id=inicial.caja_turno_id FOR UPDATE;
  IF NOT FOUND OR turno.fecha_cierre IS NOT NULL OR turno.sucursal_id IS DISTINCT FROM inicial.sucursal_id THEN
   RAISE EXCEPTION 'Turno cerrado o incompatible: no se modifica conciliacion' USING ERRCODE='22023'; END IF;
 END IF;
 SELECT * INTO v FROM public.ventas WHERE id=p_venta_id FOR UPDATE;
 IF NOT FOUND OR v.sucursal_id IS DISTINCT FROM inicial.sucursal_id OR v.empresa_id IS DISTINCT FROM inicial.empresa_id
  OR v.caja_turno_id IS DISTINCT FROM inicial.caja_turno_id OR v.estado<>'cancelada' OR v.metodo_pago IS DISTINCT FROM 'Efectivo' THEN
  RAISE EXCEPTION 'Se requiere venta cancelada en efectivo sin cambios de contexto' USING ERRCODE='22023'; END IF;
 IF v.efectivo_cancelacion_estado IS NOT NULL THEN
  IF v.efectivo_cancelacion_estado<>p_estado OR v.efectivo_conciliacion_nota IS DISTINCT FROM btrim(p_nota) THEN
   RAISE EXCEPTION 'Conciliacion ya registrada: revisar, no sobrescribir auditoria' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('venta_id',v.id,'estado',v.efectivo_cancelacion_estado,'repetida',true);
 END IF;
 UPDATE public.ventas SET efectivo_cancelacion_estado=p_estado,efectivo_conciliado_por=actor,
  efectivo_conciliado_en=clock_timestamp(),efectivo_conciliacion_nota=btrim(p_nota) WHERE id=v.id;
 RETURN jsonb_build_object('venta_id',v.id,'estado',p_estado,'repetida',false);
END; $f$;

DO $acl$
DECLARE firma text; r record;
BEGIN
 FOREACH firma IN ARRAY ARRAY['public.caja_resumen_turno(bigint)',
  'public.caja_cerrar_turno_verificado(bigint,text,numeric,text)',
  'public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)',
  'public.caja_conciliar_efectivo_cancelado(integer,text,text,boolean)'] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',firma);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',firma);
  FOR r IN SELECT DISTINCT roles.rolname FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
   JOIN pg_roles roles ON roles.oid=a.grantee WHERE p.oid=firma::regprocedure AND a.grantee<>p.proowner LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',firma,r.rolname);
  END LOOP;
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',firma);
 END LOOP;
END; $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
