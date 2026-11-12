-- Requiere 01. RPC nueva, no reemplaza funciones existentes ni activa Flutter.
BEGIN;
DO $pre$
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
END;
$pre$;
CREATE FUNCTION public.registrar_venta_con_consumo(p_operacion_id uuid, p_solicitud jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $rpc$
DECLARE
  actor uuid := auth.uid();
  ctx record; suc record; previo record; pr record; req record; lote record;
  item jsonb; linea record; venta integer; turno bigint;
  sub numeric := 0; descuento numeric; total numeric; impuesto numeric;
  epsilon CONSTANT numeric := 0.000001; -- Solo residuo double, nunca tolerancia de un centavo.
  cantidad numeric; precio numeric; falta numeric; tomar numeric;
  necesidades jsonb := '{}'::jsonb;
  lotes_bloqueados bigint[] := ARRAY[]::bigint[];
  instante timestamp; dia date;
BEGIN
  IF actor IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'Se requiere una sesion autenticada' USING ERRCODE='42501'; END IF;
  PERFORM id FROM public.usuarios WHERE auth_uid=actor FOR SHARE;
  PERFORM e.id FROM public.empleados_pos e JOIN public.usuarios u ON u.id=e.usuario_id
    WHERE u.auth_uid=actor FOR SHARE OF e;
  PERFORM user_id FROM public.inventario_admins WHERE user_id=actor FOR SHARE;
  SELECT * INTO ctx FROM public.login_contexto_operativo();
  IF NOT FOUND OR ctx.usuario_id IS NULL OR ctx.empleado_id IS NULL OR
    (ctx.sucursal_id IS NULL AND ctx.admin IS DISTINCT FROM true) THEN
    RAISE EXCEPTION 'Perfil operativo invalido' USING ERRCODE='42501'; END IF;
  IF p_operacion_id IS NULL OR jsonb_typeof(p_solicitud) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Operacion o solicitud invalida' USING ERRCODE='22023'; END IF;
  IF p_solicitud - ARRAY['sucursal_id','items','subtotal','descuento','total','iva','metodo_pago','codigo_descuento'] <> '{}'::jsonb
    OR NOT (p_solicitud ?& ARRAY['sucursal_id','items','subtotal','descuento','total','iva','metodo_pago']) THEN
    RAISE EXCEPTION 'Contrato de solicitud no reconocido' USING ERRCODE='22023'; END IF;
  SELECT * INTO suc FROM public.sucursales WHERE id=p_solicitud->>'sucursal_id'
    AND empresa_id='texas_burger' AND activo IS TRUE FOR SHARE;
  IF NOT FOUND OR (ctx.sucursal_id IS NOT NULL AND ctx.sucursal_id<>suc.id) THEN
    RAISE EXCEPTION 'Sucursal no autorizada' USING ERRCODE='42501'; END IF;

  -- Serializa el mismo UUID incluso entre sucursales. Colisiones del hash solo
  -- agregan espera; la unicidad real sigue siendo UUID y se comprueba debajo.
  PERFORM pg_advisory_xact_lock(hashtextextended('texas_operacion:'||p_operacion_id::text,0));
  SELECT * INTO previo FROM public.ventas WHERE operacion_id=p_operacion_id;
  IF FOUND THEN
    IF previo.operacion_actor IS DISTINCT FROM actor OR previo.sucursal_id IS DISTINCT FROM suc.id
      OR previo.operacion_solicitud IS DISTINCT FROM p_solicitud THEN
      RAISE EXCEPTION 'Identificador reutilizado con otra identidad o datos' USING ERRCODE='22023'; END IF;
    RETURN jsonb_build_object('estado','complete','venta_id',previo.id,'repetida',true,'caja_turno_id',previo.caja_turno_id);
  END IF;
  -- Bloqueo sencillo por sucursal para RPC nuevas. Bajas administrativas siguen
  -- coordinandose por FOR UPDATE sobre los mismos lotes, sin cambiar sus RPC.
  PERFORM pg_advisory_xact_lock(hashtextextended('texas_consumo:'||suc.id,0));
  -- Recetas e identidades de ingredientes no cambian a mitad de la operacion.
  LOCK TABLE public.productos, public.producto_ingrediente, public.ingredientes IN SHARE MODE;
  IF jsonb_typeof(p_solicitud->'items') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Items debe ser un arreglo' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(p_solicitud->'items') NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Cantidad de lineas invalida' USING ERRCODE='22023'; END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(p_solicitud->'items') LOOP
    IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR
      NOT (item ?& ARRAY['producto_id','cantidad','precio_unitario','extras','exclusiones','notas']) OR
      item - ARRAY['producto_id','cantidad','precio_unitario','extras','exclusiones','notas'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'Linea incompleta o campos desconocidos' USING ERRCODE='22023'; END IF;
    IF item->'extras' IS DISTINCT FROM '[]'::jsonb OR item->'exclusiones' IS DISTINCT FROM '[]'::jsonb
      OR item->'notas' IS DISTINCT FROM '""'::jsonb THEN
      RAISE EXCEPTION 'Personalizacion sin reglas de consumo: no se registra la venta' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(item->'producto_id') IS DISTINCT FROM 'number'
      OR jsonb_typeof(item->'cantidad') IS DISTINCT FROM 'number'
      OR jsonb_typeof(item->'precio_unitario') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'Tipos numericos invalidos' USING ERRCODE='22023'; END IF;
    cantidad := (item->>'cantidad')::numeric; precio := (item->>'precio_unitario')::numeric;
    IF cantidad NOT BETWEEN 1 AND 1000000 OR cantidad<>trunc(cantidad)
      OR precio NOT BETWEEN 0 AND 99999999.99 OR abs(precio-round(precio,2))>epsilon
      OR (item->>'producto_id')::numeric<>trunc((item->>'producto_id')::numeric) THEN
      RAISE EXCEPTION 'Cantidad, producto o precio invalido' USING ERRCODE='22023'; END IF;
    SELECT * INTO pr FROM public.productos WHERE id=(item->>'producto_id')::integer AND activo IS TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Producto inexistente o inactivo' USING ERRCODE='22023'; END IF;
    IF pr.consumo_modo='pendiente' THEN
      RAISE EXCEPTION 'Producto % pendiente de configurar consumo',pr.id USING ERRCODE='22023'; END IF;
    IF pr.consumo_modo='exento' THEN
      IF EXISTS (SELECT FROM public.producto_ingrediente WHERE producto_id=pr.id) THEN
        RAISE EXCEPTION 'Producto exento con receta contradictoria' USING ERRCODE='22023'; END IF;
    ELSE
      IF NOT EXISTS (SELECT FROM public.producto_ingrediente WHERE producto_id=pr.id) THEN
        RAISE EXCEPTION 'Producto % sin receta',pr.id USING ERRCODE='22023'; END IF;
      IF pr.consumo_modo='unidad_completa' AND
        (SELECT count(*) FROM public.producto_ingrediente WHERE producto_id=pr.id)<>1 THEN
        RAISE EXCEPTION 'Unidad completa requiere una correspondencia explicita' USING ERRCODE='22023'; END IF;
      FOR linea IN SELECT r.ingrediente_id,r.cantidad_requerida,i.unidad_medida
        FROM public.producto_ingrediente r JOIN public.ingredientes i ON i.id=r.ingrediente_id
        WHERE r.producto_id=pr.id ORDER BY r.ingrediente_id LOOP
        IF linea.cantidad_requerida IS NULL OR NOT (linea.cantidad_requerida>0 AND linea.cantidad_requerida<100000000)
          OR linea.unidad_medida IS NULL OR linea.unidad_medida NOT IN ('kg','L','pza','pzas') THEN
          RAISE EXCEPTION 'Receta o unidad no soportada' USING ERRCODE='22023'; END IF;
        IF linea.unidad_medida IN ('pza','pzas') AND linea.cantidad_requerida<>trunc(linea.cantidad_requerida) THEN
          RAISE EXCEPTION 'Las piezas deben ser enteras' USING ERRCODE='22023'; END IF;
        IF pr.consumo_modo='unidad_completa' AND
          (linea.unidad_medida NOT IN ('pza','pzas') OR linea.cantidad_requerida<>1) THEN
          RAISE EXCEPTION 'Unidad completa requiere una pieza por producto' USING ERRCODE='22023'; END IF;
        necesidades := jsonb_set(necesidades,ARRAY[linea.ingrediente_id::text],to_jsonb(
          coalesce((necesidades->>linea.ingrediente_id::text)::numeric,0)+linea.cantidad_requerida*cantidad));
      END LOOP;
    END IF;
    sub := sub + round(precio,2)*cantidad;
  END LOOP;

  IF EXISTS (SELECT FROM jsonb_each(p_solicitud) x WHERE x.key IN ('subtotal','descuento','total','iva')
    AND jsonb_typeof(x.value) IS DISTINCT FROM 'number') THEN
    RAISE EXCEPTION 'Importes deben ser numeros' USING ERRCODE='22023'; END IF;
  descuento := (p_solicitud->>'descuento')::numeric;
  total := (p_solicitud->>'total')::numeric;
  impuesto := (p_solicitud->>'iva')::numeric;
  IF sub>99999999.99 OR abs((p_solicitud->>'subtotal')::numeric-sub)>epsilon
    OR descuento<0 OR descuento>sub+epsilon OR abs(descuento-round(descuento,2))>epsilon
    OR total<0 OR abs(total-round(total,2))>epsilon
    OR impuesto<0 OR abs(impuesto-round(impuesto,2))>epsilon
    OR abs(total-(sub-round(descuento,2)))>epsilon
    -- PricingService redondea primero la base y despues la diferencia.
    OR round(impuesto,2)<>round(round(total,2)-round(round(total,2)/1.16,2),2)
    OR p_solicitud->>'metodo_pago' NOT IN ('Efectivo','Tarjeta','Transferencia')
    OR jsonb_typeof(p_solicitud->'metodo_pago') IS DISTINCT FROM 'string'
    OR (p_solicitud ? 'codigo_descuento' AND jsonb_typeof(p_solicitud->'codigo_descuento') NOT IN ('string','null')) THEN
    RAISE EXCEPTION 'Desglose comercial invalido: IVA incluido del 16 por ciento' USING ERRCODE='22023'; END IF;
  descuento := round(descuento,2); total := round(total,2); impuesto := round(impuesto,2);

  -- El cierre existente bloquea esta misma fila. Si ya cerro tras esperar,
  -- READ COMMITTED reevalua fecha_cierre y la venta queda sin turno.
  SELECT id INTO turno FROM public.caja_turnos WHERE empresa_id='texas_burger'
    AND sucursal_id=suc.id AND fecha_cierre IS NULL FOR UPDATE;
  -- Bloquear todos los lotes de los ingredientes necesarios, incluso agotados o
  -- caducados, y releer saldos despues. Sin SKIP LOCKED ni stock_actual.
  FOR lote IN SELECT l.id FROM public.inventario_lotes l WHERE l.sucursal_id=suc.id
    AND necesidades ? l.ingrediente_id::text
    ORDER BY l.ingrediente_id,l.fecha_caducidad,l.fecha_entrada,l.id FOR UPDATE LOOP
    lotes_bloqueados := array_append(lotes_bloqueados,lote.id);
  END LOOP;
  -- Lotes creados despues de esta seleccion se utilizaran en otra operacion.
  instante := clock_timestamp() AT TIME ZONE 'America/Monterrey'; dia := instante::date;
  FOR req IN SELECT key::integer ingrediente_id,value::numeric cantidad FROM jsonb_each_text(necesidades) ORDER BY key::integer LOOP
    IF EXISTS (SELECT FROM public.inventario_lotes l JOIN public.ingredientes i ON i.id=l.ingrediente_id
      WHERE l.id=ANY(lotes_bloqueados) AND l.sucursal_id=suc.id AND l.ingrediente_id=req.ingrediente_id AND l.cantidad_disponible>0
        AND l.fecha_caducidad>=dia AND (l.unidad_medida IS DISTINCT FROM i.unidad_medida
          OR (i.unidad_medida IN ('pza','pzas') AND l.cantidad_disponible<>trunc(l.cantidad_disponible)))) THEN
      RAISE EXCEPTION 'Unidad o saldo de piezas incompatible en lotes' USING ERRCODE='22023'; END IF;
    IF coalesce((SELECT sum(cantidad_disponible) FROM public.inventario_lotes WHERE id=ANY(lotes_bloqueados) AND sucursal_id=suc.id
      AND ingrediente_id=req.ingrediente_id AND fecha_caducidad>=dia),0)<req.cantidad THEN
      RAISE EXCEPTION 'Ingredientes insuficientes: %',req.ingrediente_id USING ERRCODE='22023'; END IF;
  END LOOP;
  INSERT INTO public.ventas(usuario_id,fecha_hora,total,metodo_pago,empresa_id,empresa_nombre,
    sucursal_id,sucursal_nombre,empleado_pos_id,empleado_nombre,subtotal,descuento,codigo_descuento,
    iva,tasa_iva,iva_incluido,operacion_id,operacion_actor,operacion_solicitud,caja_turno_id)
  VALUES(ctx.usuario_id,instante,total,p_solicitud->>'metodo_pago','texas_burger','Texas Burger',
    suc.id,suc.nombre,ctx.empleado_id,ctx.empleado_nombre,sub,descuento,p_solicitud->>'codigo_descuento',
    impuesto,0.16,true,p_operacion_id,actor,p_solicitud,turno) RETURNING id INTO venta;
  INSERT INTO public.detalle_venta(venta_id,producto_id,cantidad,precio_unitario)
    SELECT venta,(v->>'producto_id')::integer,(v->>'cantidad')::integer,round((v->>'precio_unitario')::numeric,2)
    FROM jsonb_array_elements(p_solicitud->'items') v;
  FOR req IN SELECT key::integer ingrediente_id,value::numeric cantidad FROM jsonb_each_text(necesidades) ORDER BY key::integer LOOP
    falta := req.cantidad;
    FOR lote IN SELECT * FROM public.inventario_lotes WHERE id=ANY(lotes_bloqueados) AND sucursal_id=suc.id AND ingrediente_id=req.ingrediente_id
      AND fecha_caducidad>=dia AND cantidad_disponible>0 ORDER BY fecha_caducidad,fecha_entrada,id LOOP
      tomar := least(falta,lote.cantidad_disponible);
      UPDATE public.inventario_lotes SET cantidad_disponible=cantidad_disponible-tomar WHERE id=lote.id;
      INSERT INTO public.inventario_movimientos(lote_id,tipo,cantidad,cantidad_antes,cantidad_despues,motivo,actor_uid,venta_id)
      VALUES(lote.id,'salida',tomar,lote.cantidad_disponible,lote.cantidad_disponible-tomar,'Consumo venta '||venta,actor,venta);
      falta := falta-tomar; EXIT WHEN falta=0;
    END LOOP;
    IF falta<>0 THEN RAISE EXCEPTION 'No se pudo completar el consumo'; END IF;
  END LOOP;
  RETURN jsonb_build_object('estado','complete','venta_id',venta,'repetida',false,'caja_turno_id',turno);
  -- Sin captura de errores: PostgreSQL revierte cabecera, detalles y consumos juntos.
END;
$rpc$;
ALTER FUNCTION public.registrar_venta_con_consumo(uuid,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.registrar_venta_con_consumo(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
-- Cubrir tambien receptores adicionales de DEFAULT PRIVILEGES, sin alterarlos.
DO $acl$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT roles.rolname FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(p.proacl) a JOIN pg_roles roles ON roles.oid=a.grantee
    WHERE p.oid='public.registrar_venta_con_consumo(uuid,jsonb)'::regprocedure AND a.grantee<>p.proowner LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.registrar_venta_con_consumo(uuid,jsonb) FROM %I',r.rolname);
  END LOOP;
END;
$acl$;
GRANT EXECUTE ON FUNCTION public.registrar_venta_con_consumo(uuid,jsonb) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
