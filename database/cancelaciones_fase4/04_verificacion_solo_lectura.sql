SELECT column_name,data_type,is_nullable,column_default FROM information_schema.columns
WHERE table_schema='public' AND table_name='ventas' AND column_name IN
 ('estado','cancelada_en','cancelada_por','cancelacion_motivo','inventario_reintegrado');
SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid IN ('public.ventas'::regclass,'public.cancelacion_permisos'::regclass)
 AND (conname LIKE 'fase4_%' OR conrelid='public.cancelacion_permisos'::regclass);
SELECT rolname,has_function_privilege(oid,'public.cancelar_venta(integer,text,boolean)','EXECUTE') ejecutar,
 has_column_privilege(oid,'public.ventas','estado','INSERT,UPDATE') alterar_estado,
 has_table_privilege(oid,'public.cancelacion_permisos','INSERT,UPDATE,DELETE,TRUNCATE') alterar_permisos
FROM pg_roles WHERE rolname IN ('anon','authenticated');
-- authenticated: true,false,false; anon: false,false,false.
SELECT proowner::regrole,prosecdef,proconfig,proacl FROM pg_proc
WHERE oid='public.cancelar_venta(integer,text,boolean)'::regprocedure;
SELECT relrowsecurity,relforcerowsecurity,relacl FROM pg_class WHERE oid='public.cancelacion_permisos'::regclass;
SELECT usuario_auth_id,sucursal_id,activo FROM public.cancelacion_permisos;
SELECT id,estado,caja_turno_id,cancelada_en,cancelada_por,cancelacion_motivo,inventario_reintegrado
FROM public.ventas WHERE estado='cancelada' ORDER BY id;
-- Cantidades reintegradas deben corresponder exactamente a las salidas originales
-- POR LOTE, y solo existir cuando la venta figura cancelada con reintegro.
WITH balances AS (
 SELECT venta_id,lote_id,sum(cantidad) FILTER(WHERE tipo='salida') salida,
 coalesce(sum(cantidad) FILTER(WHERE tipo='entrada'),0) entrada
 FROM public.inventario_movimientos WHERE venta_id IS NOT NULL GROUP BY venta_id,lote_id)
SELECT b.*,v.estado,v.inventario_reintegrado FROM balances b JOIN public.ventas v ON v.id=b.venta_id
WHERE (v.estado='cancelada' AND v.inventario_reintegrado AND b.entrada IS DISTINCT FROM b.salida)
 OR ((v.estado<>'cancelada' OR NOT v.inventario_reintegrado) AND b.entrada<>0);
SELECT m.id,m.venta_id,m.lote_id FROM public.inventario_movimientos m
JOIN public.ventas v ON v.id=m.venta_id JOIN public.inventario_lotes l ON l.id=m.lote_id
WHERE m.tipo='entrada' AND (m.actor_uid IS DISTINCT FROM v.cancelada_por
 OR l.sucursal_id IS DISTINCT FROM v.sucursal_id OR m.cantidad_despues-m.cantidad_antes<>m.cantidad);
SELECT id FROM public.inventario_lotes WHERE cantidad_disponible<0 OR cantidad_disponible>cantidad_inicial;
-- Estas consultas de anomalias deben devolver cero filas.
