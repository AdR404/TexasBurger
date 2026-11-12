-- REVISION LOCAL: ejecutar manualmente como postgres, despues de Login fase4 y recetas fase2.
-- No ejecutado contra Supabase. No rellena recetas ni vincula ventas historicas.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $pre$
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
  IF to_regprocedure('public.login_contexto_operativo()') IS NULL THEN
    RAISE EXCEPTION 'Falta Login fase4: login_contexto_operativo()'; END IF;
  IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.producto_ingrediente'::regclass
    AND attname='cantidad_requerida' AND attnotnull AND format_type(atttypid,atttypmod)='numeric(11,3)') THEN
    RAISE EXCEPTION 'Falta estructura de recetas fase2'; END IF;
  -- No cambiar permisos antiguos. Exigir los permisos acotados de Login fase4:
  -- un GRANT INSERT de tabla tambien permitiria falsificar las nuevas columnas.
  IF has_table_privilege('authenticated','public.ventas','INSERT,UPDATE')
    OR has_table_privilege('anon','public.ventas','INSERT,UPDATE')
    OR has_table_privilege('authenticated','public.productos','INSERT,UPDATE')
    OR has_table_privilege('anon','public.productos','INSERT,UPDATE') THEN
    RAISE EXCEPTION 'Permisos amplios incompatibles: revisar Login fase4 antes de aplicar; este script no los cambia'; END IF;
END;
$pre$;

ALTER TABLE public.productos ADD COLUMN consumo_modo text NOT NULL DEFAULT 'pendiente'
  CONSTRAINT fase3_producto_modo CHECK (consumo_modo IN ('pendiente','receta','unidad_completa','exento'));
COMMENT ON COLUMN public.productos.consumo_modo IS
  'SQL Editor: pendiente bloquea RPC; receta completa; unidad_completa exige una linea pza/pzas de cantidad 1; exento exige cero lineas. No inferir por nombre.';

ALTER TABLE public.ventas
  ADD COLUMN operacion_id uuid,
  ADD COLUMN operacion_actor uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  ADD COLUMN operacion_solicitud jsonb,
  ADD COLUMN caja_turno_id bigint REFERENCES public.caja_turnos(id) ON DELETE RESTRICT,
  ADD CONSTRAINT fase3_operacion_unica UNIQUE (operacion_id),
  ADD CONSTRAINT fase3_operacion_completa CHECK (
    (operacion_id IS NULL AND operacion_actor IS NULL AND operacion_solicitud IS NULL)
    OR (operacion_id IS NOT NULL AND operacion_actor IS NOT NULL AND operacion_solicitud IS NOT NULL));
CREATE INDEX fase3_ventas_turno_idx ON public.ventas(caja_turno_id) WHERE caja_turno_id IS NOT NULL;
ALTER TABLE public.inventario_movimientos
  ADD COLUMN venta_id integer REFERENCES public.ventas(id) ON DELETE RESTRICT,
  ADD CONSTRAINT fase3_movimiento_venta CHECK (venta_id IS NULL OR tipo IN ('salida','entrada'));
-- El CHECK de saldos existente distingue entrada/salida. Una futura devolucion
-- podra enlazar la venta; esto NO implementa ni autoriza reintegros.
CREATE INDEX fase3_movimientos_venta_idx ON public.inventario_movimientos(venta_id) WHERE venta_id IS NOT NULL;
DO $acl$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF has_column_privilege(r,'public.ventas','operacion_id','INSERT')
      OR has_column_privilege(r,'public.ventas','operacion_solicitud','UPDATE')
      OR has_column_privilege(r,'public.ventas','caja_turno_id','INSERT')
      OR has_column_privilege(r,'public.inventario_movimientos','venta_id','INSERT')
      OR has_column_privilege(r,'public.productos','consumo_modo','UPDATE') THEN
      RAISE EXCEPTION 'Permisos heredados incompatibles para %; no se aplicara estructura',r; END IF;
  END LOOP;
END;
$acl$;
-- venta_id + lote_id + cantidad/antes/despues + actor_uid conservan el consumo
-- exacto incluso si despues cambia la receta. Se agrega por ingrediente/venta.
COMMIT;
