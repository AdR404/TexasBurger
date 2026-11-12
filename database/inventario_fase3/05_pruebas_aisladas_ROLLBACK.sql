-- SOLO BASE DE PRUEBAS AISLADA, nunca proyecto compartido. Ejecutar como postgres.
-- Requiere 01/02 y un cajero REAL de prueba activo con empleado no demo, sucursal,
-- y un producto activo con receta REAL aprobada (modo receta). No inventa recetas.
-- Completar configuracion. Todo termina en ROLLBACK; secuencias SI pueden avanzar.
-- No hay PostgreSQL local disponible: estas pruebas se preparan, no se ejecutaron.
BEGIN;
CREATE TEMP TABLE fase3_test_config(actor uuid, producto integer, sucursal text, otra_sucursal text);
INSERT INTO fase3_test_config VALUES (NULL,NULL,NULL,NULL); -- completar con fixture aislada
DO $pre$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM fase3_test_config;
  IF current_user<>'postgres' OR c.actor IS NULL OR c.producto IS NULL OR c.sucursal IS NULL
    OR c.otra_sucursal IS NULL OR c.sucursal=c.otra_sucursal THEN
    RAISE EXCEPTION 'Configurar una fixture exclusivamente aislada'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',c.actor,'role','authenticated')::text,true);
  PERFORM set_config('request.jwt.claim.sub',c.actor::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  IF NOT EXISTS (SELECT FROM public.login_contexto_operativo() WHERE NOT admin AND sucursal_id=c.sucursal)
    OR NOT EXISTS (SELECT FROM public.productos WHERE id=c.producto AND activo AND consumo_modo='receta')
    OR NOT EXISTS (SELECT FROM public.producto_ingrediente WHERE producto_id=c.producto) THEN
    RAISE EXCEPTION 'Fixture incompleta: cajero activo y receta real requerida'; END IF;
END;
$pre$;
-- Estado exacto de negocio, excluyendo secuencias (nextval no es transaccional).
CREATE FUNCTION pg_temp.estado_fase3() RETURNS jsonb LANGUAGE sql AS $f$
 SELECT jsonb_build_object(
 'ventas',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.ventas v),
 'detalles',(SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM public.detalle_venta d),
 'lotes',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.inventario_lotes l),
 'movimientos',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.inventario_movimientos m))
$f$;
CREATE FUNCTION pg_temp.esperar_error(op uuid,sol jsonb,codigo text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE antes jsonb:=pg_temp.estado_fase3(); fallo boolean:=false;
BEGIN
  BEGIN
    PERFORM public.registrar_venta_con_consumo(op,sol);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>codigo THEN RAISE; END IF;
    fallo:=true;
  END;
  IF NOT fallo THEN RAISE EXCEPTION 'Se esperaba error %',codigo; END IF;
  IF pg_temp.estado_fase3() IS DISTINCT FROM antes THEN RAISE EXCEPTION 'Hay cambios parciales'; END IF;
END;
$f$;
CREATE TEMP TABLE fase3_solicitud AS SELECT jsonb_build_object(
 'sucursal_id',sucursal,'items',jsonb_build_array(jsonb_build_object(
 'producto_id',producto,'cantidad',2,'precio_unitario',100,'extras','[]'::jsonb,'exclusiones','[]'::jsonb,'notas','')),
 'subtotal',200,'descuento',0,'total',200,'iva',27.59,'metodo_pago','Efectivo') solicitud FROM fase3_test_config;

-- Crear lotes SOLO DE PRUEBA a partir de cantidades reales, sin alterar recetas.
-- Dos lotes por ingrediente: el primero vence HOY y el segundo manana.
UPDATE public.inventario_lotes SET cantidad_disponible=0
WHERE sucursal_id=(SELECT sucursal FROM fase3_test_config);
CREATE TEMP TABLE fase3_lotes_creados(id bigint);
WITH nuevos AS (
 INSERT INTO public.inventario_lotes(ingrediente_id,sucursal_id,ubicacion,unidad_medida,
 cantidad_inicial,cantidad_disponible,costo_unitario,fecha_entrada,fecha_caducidad,caducidad_estimada)
 SELECT r.ingrediente_id,c.sucursal,'Almacén',i.unidad_medida,r.cantidad_requerida,r.cantidad_requerida,0,
 (clock_timestamp() AT TIME ZONE 'America/Monterrey')::date,
 (clock_timestamp() AT TIME ZONE 'America/Monterrey')::date+n,false
 FROM fase3_test_config c JOIN public.producto_ingrediente r ON r.producto_id=c.producto
 JOIN public.ingredientes i ON i.id=r.ingrediente_id CROSS JOIN generate_series(0,1) n
 RETURNING id
) INSERT INTO fase3_lotes_creados SELECT id FROM nuevos;

DO $casos$
DECLARE c record; s jsonb; variante jsonb; op uuid:=gen_random_uuid(); res jsonb; repetida jsonb; antes jsonb; n integer;
BEGIN
 SELECT * INTO c FROM fase3_test_config; SELECT solicitud INTO s FROM fase3_solicitud;
 -- Cajero intenta otra sucursal.
 PERFORM pg_temp.esperar_error(gen_random_uuid(),jsonb_set(s,'{sucursal_id}',to_jsonb(c.otra_sucursal)),'42501');
 UPDATE public.usuarios SET activo=false WHERE auth_uid=c.actor;
 PERFORM pg_temp.esperar_error(gen_random_uuid(),s,'42501');
 UPDATE public.usuarios SET activo=true WHERE auth_uid=c.actor;
 UPDATE public.empleados_pos SET es_demo=true WHERE usuario_id=(SELECT id FROM public.usuarios WHERE auth_uid=c.actor);
 PERFORM pg_temp.esperar_error(gen_random_uuid(),s,'42501');
 UPDATE public.empleados_pos SET es_demo=false WHERE usuario_id=(SELECT id FROM public.usuarios WHERE auth_uid=c.actor);
 UPDATE public.productos SET activo=false WHERE id=c.producto;
 PERFORM pg_temp.esperar_error(gen_random_uuid(),s,'22023');
 UPDATE public.productos SET activo=true,consumo_modo='pendiente' WHERE id=c.producto;
 PERFORM pg_temp.esperar_error(gen_random_uuid(),s,'22023');
 UPDATE public.productos SET consumo_modo='receta' WHERE id=c.producto;
 -- Sin receta: guardar/restaurar temporalmente las filas REALES, no inventarlas.
 CREATE TEMP TABLE fase3_receta_guardada AS SELECT * FROM public.producto_ingrediente WHERE producto_id=c.producto;
 DELETE FROM public.producto_ingrediente WHERE producto_id=c.producto;
 PERFORM pg_temp.esperar_error(gen_random_uuid(),s,'22023');
 INSERT INTO public.producto_ingrediente SELECT * FROM fase3_receta_guardada;
 -- Extras, exclusiones y notas no se ignoran.
 PERFORM pg_temp.esperar_error(gen_random_uuid(),jsonb_set(s,'{items,0,extras}','["ext_queso"]'),'22023');
 PERFORM pg_temp.esperar_error(gen_random_uuid(),jsonb_set(s,'{items,0,exclusiones}','["sin queso"]'),'22023');
 PERFORM pg_temp.esperar_error(gen_random_uuid(),jsonb_set(s,'{items,0,notas}','"sin salsa"'),'22023');
 -- Caducados ayer: no utilizables. fecha_entrada tambien se ajusta por CHECK.
 UPDATE public.inventario_lotes SET fecha_entrada=fecha_entrada-2,fecha_caducidad=
   (clock_timestamp() AT TIME ZONE 'America/Monterrey')::date-1 WHERE id IN (SELECT id FROM fase3_lotes_creados);
 PERFORM pg_temp.esperar_error(gen_random_uuid(),s,'22023');
 -- Restaurar orden FEFO de dos lotes por ingrediente usando id ascendente.
 WITH fechas AS (SELECT id,row_number() OVER(PARTITION BY ingrediente_id ORDER BY id)-1 n
   FROM public.inventario_lotes WHERE id IN (SELECT id FROM fase3_lotes_creados))
 UPDATE public.inventario_lotes l SET fecha_caducidad=(clock_timestamp() AT TIME ZONE 'America/Monterrey')::date+f.n::integer
 FROM fechas f WHERE l.id=f.id;
 -- Importes: residuo double, promocion de 42 y cupon posterior del 10%.
 -- Cada venta exitosa de este bloque se revierte antes del ensayo FEFO siguiente.
 FOR variante IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
   jsonb_set(s,'{items,0,precio_unitario}','0.10000000000000002') ||
     '{"subtotal":0.20000000000000004,"total":0.20000000000000004,"iva":0.03}'::jsonb,
   s || '{"descuento":42,"total":158,"iva":21.79,"metodo_pago":"Tarjeta"}'::jsonb,
   s || '{"descuento":57.8,"total":142.2,"iva":19.61,"codigo_descuento":"TEST","metodo_pago":"Transferencia"}'::jsonb
 )) LOOP
   antes:=pg_temp.estado_fase3();
   BEGIN
     res:=public.registrar_venta_con_consumo(gen_random_uuid(),variante);
     IF NOT EXISTS (SELECT FROM public.ventas WHERE id=(res->>'venta_id')::integer
       AND total=round((variante->>'total')::numeric,2) AND iva=round((variante->>'iva')::numeric,2)) THEN
       RAISE EXCEPTION 'Importes normalizados incorrectos'; END IF;
     IF EXISTS (SELECT FROM public.detalle_venta WHERE venta_id=(res->>'venta_id')::integer
       AND precio_unitario<>round((variante->'items'->0->>'precio_unitario')::numeric,2)) THEN
       RAISE EXCEPTION 'Precio normalizado incorrecto'; END IF;
     RAISE EXCEPTION 'Revertir exclusivamente caso monetario exitoso' USING ERRCODE='P0098';
   EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
   END;
   IF pg_temp.estado_fase3() IS DISTINCT FROM antes THEN RAISE EXCEPTION 'Caso monetario no revertido'; END IF;
 END LOOP;
 PERFORM pg_temp.esperar_error(gen_random_uuid(),jsonb_set(s,'{iva}','27.60'),'22023');
 PERFORM pg_temp.esperar_error(gen_random_uuid(),jsonb_set(s,'{items,0,precio_unitario}','100.001'),'22023');
 PERFORM pg_temp.esperar_error(gen_random_uuid(),jsonb_set(s,'{total}','199.99'),'22023');
 res:=public.registrar_venta_con_consumo(op,s);
 IF res->>'estado'<>'complete' THEN RAISE EXCEPTION 'Venta no completada'; END IF;
 SELECT count(*) INTO n FROM public.inventario_movimientos WHERE venta_id=(res->>'venta_id')::integer;
 IF n<>(SELECT count(*) FROM fase3_lotes_creados) OR EXISTS
   (SELECT FROM public.inventario_lotes WHERE id IN (SELECT id FROM fase3_lotes_creados) AND cantidad_disponible<>0) THEN
   RAISE EXCEPTION 'Consumo multilote incorrecto'; END IF;
 IF EXISTS (SELECT FROM public.inventario_movimientos m JOIN public.inventario_lotes l ON l.id=m.lote_id
   WHERE m.venta_id=(res->>'venta_id')::integer AND EXISTS
     (SELECT FROM public.inventario_movimientos m2 JOIN public.inventario_lotes l2 ON l2.id=m2.lote_id
      WHERE m2.venta_id=m.venta_id AND l2.ingrediente_id=l.ingrediente_id AND l2.fecha_caducidad<l.fecha_caducidad AND m2.id>m.id)) THEN
   RAISE EXCEPTION 'Orden FEFO incorrecto'; END IF;
 antes:=pg_temp.estado_fase3(); repetida:=public.registrar_venta_con_consumo(op,s);
 IF repetida->>'venta_id' IS DISTINCT FROM res->>'venta_id' OR repetida->>'repetida'<>'true'
   OR pg_temp.estado_fase3() IS DISTINCT FROM antes THEN RAISE EXCEPTION 'Idempotencia incorrecta'; END IF;
 PERFORM pg_temp.esperar_error(op,jsonb_set(s,'{metodo_pago}','"Tarjeta"'),'22023');
 -- Misma venta con UUID diferente: no queda stock, no debe quedar cabecera.
 PERFORM pg_temp.esperar_error(gen_random_uuid(),s,'22023');
 RAISE NOTICE 'Casos de identidad, receta, stock, FEFO, multilote e idempotencia OK';
END;
$casos$;
-- Fallo inyectado DESPUES de insertar cabecera y DESPUES de descontar un lote.
UPDATE public.inventario_lotes SET cantidad_disponible=cantidad_inicial WHERE id IN (SELECT id FROM fase3_lotes_creados);
CREATE FUNCTION pg_temp.fallo_consumo() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN RAISE EXCEPTION 'Fallo deliberado de prueba' USING ERRCODE='P0099'; END;
$f$;
CREATE TRIGGER fase3_fallo_test BEFORE INSERT ON public.inventario_movimientos
FOR EACH ROW WHEN (NEW.venta_id IS NOT NULL) EXECUTE FUNCTION pg_temp.fallo_consumo();
SELECT pg_temp.esperar_error(gen_random_uuid(),solicitud,'P0099') FROM fase3_solicitud;
DROP TRIGGER fase3_fallo_test ON public.inventario_movimientos;
-- Ejecucion con rol cliente: no concederle administracion de inventario.
GRANT SELECT ON fase3_solicitud TO authenticated;
SET LOCAL ROLE authenticated;
SELECT public.registrar_venta_con_consumo(gen_random_uuid(),solicitud) FROM fase3_solicitud;
RESET ROLE;
ROLLBACK;
