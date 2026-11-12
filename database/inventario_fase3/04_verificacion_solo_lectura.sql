-- Solo lectura, despues de 01/02. No invoca la RPC ni registra ventas de prueba.
SELECT table_name,column_name,data_type,numeric_precision,numeric_scale,is_nullable,column_default
FROM information_schema.columns WHERE table_schema='public' AND
  ((table_name='productos' AND column_name='consumo_modo') OR
   (table_name='ventas' AND column_name IN ('operacion_id','operacion_actor','operacion_solicitud','caja_turno_id')) OR
   (table_name='inventario_movimientos' AND column_name='venta_id')) ORDER BY table_name,column_name;
SELECT conrelid::regclass tabla,conname,pg_get_constraintdef(oid) definicion
FROM pg_constraint WHERE conname LIKE 'fase3_%';
SELECT r.rolname,has_function_privilege(r.oid,'public.registrar_venta_con_consumo(uuid,jsonb)','EXECUTE') ejecutar,
  has_column_privilege(r.oid,'public.productos','consumo_modo','UPDATE') configurar_modo,
  has_column_privilege(r.oid,'public.ventas','operacion_id','INSERT') falsificar_operacion,
  has_column_privilege(r.oid,'public.inventario_movimientos','venta_id','INSERT') insertar_consumo
FROM pg_roles r WHERE rolname IN ('anon','authenticated','service_role','postgres');
-- authenticated: ejecutar=true; las otras tres=false. anon: cuatro false.
SELECT proowner::regrole propietario,prosecdef,proconfig,proacl
FROM pg_proc WHERE oid='public.registrar_venta_con_consumo(uuid,jsonb)'::regprocedure;
SELECT p.id,p.nombre,p.consumo_modo,count(r.ingrediente_id) ingredientes
FROM public.productos p LEFT JOIN public.producto_ingrediente r ON r.producto_id=p.id
GROUP BY p.id ORDER BY p.id;
SELECT r.producto_id,r.ingrediente_id,r.cantidad_requerida,i.unidad_medida
FROM public.producto_ingrediente r JOIN public.ingredientes i ON i.id=r.ingrediente_id
WHERE i.unidad_medida IS NULL OR i.unidad_medida NOT IN ('kg','L','pza','pzas')
  OR (i.unidad_medida IN ('pza','pzas') AND r.cantidad_requerida<>trunc(r.cantidad_requerida));
-- Debe devolver cero anomalias. Las unidades de lote deben coincidir exactamente.
SELECT l.id,l.unidad_medida unidad_lote,i.unidad_medida unidad_ingrediente
FROM public.inventario_lotes l JOIN public.ingredientes i ON i.id=l.ingrediente_id
WHERE l.unidad_medida IS DISTINCT FROM i.unidad_medida;
-- Trazabilidad posterior a pruebas: historicas operacion_id NULL quedan fuera.
SELECT v.id,v.operacion_id,v.caja_turno_id,
  (SELECT count(*) FROM public.detalle_venta d WHERE d.venta_id=v.id) detalles,
  (SELECT count(*) FROM public.inventario_movimientos m WHERE m.venta_id=v.id) movimientos
FROM public.ventas v WHERE v.operacion_id IS NOT NULL ORDER BY v.id;
SELECT m.id,m.venta_id,m.lote_id FROM public.inventario_movimientos m
JOIN public.ventas v ON v.id=m.venta_id JOIN public.inventario_lotes l ON l.id=m.lote_id
WHERE m.tipo NOT IN ('salida','entrada')
  OR (m.tipo='salida' AND m.actor_uid IS DISTINCT FROM v.operacion_actor)
  OR l.sucursal_id IS DISTINCT FROM v.sucursal_id
  OR (m.tipo='salida' AND m.cantidad_antes-m.cantidad_despues<>m.cantidad)
  OR (m.tipo='entrada' AND m.cantidad_despues-m.cantidad_antes<>m.cantidad);
-- Un futuro reintegro puede tener otro actor autorizado. Su autorizacion y
-- limite contra el consumo original corresponden a la futura RPC de cancelacion.
-- No compara saldos actuales contra recetas actuales: pueden haber cambiado.
