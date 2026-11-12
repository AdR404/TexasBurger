-- Requiere 004, 005, 007 y 01 de esta carpeta. Guardar 00 antes de aplicar.
BEGIN;
SET LOCAL lock_timeout = '5s';
LOCK TABLE public.ventas, public.detalle_venta, public.productos, public.categorias, public.ingredientes, public.empleados_pos, public.sucursales IN ACCESS EXCLUSIVE MODE;
DO $pre$
BEGIN
  IF current_user <> 'postgres' OR NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polrelid='public.caja_turnos'::regclass AND polname='fase4_admin'
  ) THEN RAISE EXCEPTION 'Ejecutar como postgres despues de 01'; END IF;
  IF EXISTS (SELECT FROM pg_policies WHERE schemaname='public' AND tablename IN
    ('ventas','detalle_venta','productos','categorias','ingredientes')) THEN
    RAISE EXCEPTION 'Politicas adicionales no inspeccionadas: revisar antes de aplicar'; END IF;
  IF EXISTS (SELECT FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
    WHERE c.relnamespace='public'::regnamespace AND c.relname IN ('ventas', 'detalle_venta', 'productos', 'categorias', 'ingredientes', 'empleados_pos', 'sucursales')
      AND a.attacl IS NOT NULL AND cardinality(a.attacl)>0) THEN
    RAISE EXCEPTION 'Hay permisos por columna previos: revisar y respaldar'; END IF;
  IF NOT has_function_privilege('service_role',
    'public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean)','EXECUTE')
    OR has_function_privilege('authenticated',
    'public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean)','EXECUTE')
    OR has_function_privilege('anon',
    'public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean)','EXECUTE')
  THEN RAISE EXCEPTION 'Revisar instalacion y permisos de 007'; END IF;
  IF NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname='service_role')
    OR NOT has_column_privilege('service_role','public.usuarios','id','SELECT')
    OR NOT has_column_privilege('service_role','public.usuarios','usuario','SELECT')
    OR NOT has_table_privilege('service_role','public.sucursales','SELECT')
    OR NOT has_function_privilege('authenticated','public.login_mi_perfil()','EXECUTE')
  THEN RAISE EXCEPTION 'No se cumplen las dependencias de lectura de admin-register-user'; END IF;
  IF NOT EXISTS (SELECT FROM pg_policies WHERE schemaname='public' AND
    tablename='sucursales' AND cmd='SELECT' AND permissive='PERMISSIVE' AND qual='true'
    AND 'authenticated'::name=ANY(roles)) OR NOT EXISTS (
    SELECT FROM pg_policies WHERE schemaname='public' AND tablename='empleados_pos'
    AND cmd='SELECT' AND permissive='PERMISSIVE' AND qual='true' AND 'authenticated'::name=ANY(roles))
  THEN RAISE EXCEPTION 'Cambio en las politicas base de sucursales/empleados; revisar el acceso operativo'; END IF;
END;
$pre$;

-- Invoker: devuelve exclusivamente la proyeccion operativa de la propia sesion.
CREATE FUNCTION public.login_contexto_operativo()
RETURNS TABLE(usuario_id integer, empleado_id text, empleado_nombre text, sucursal_id text, admin boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $perfil$
  SELECT p.usuario_id,p.empleado_pos_id,p.empleado_nombre,p.sucursal_id,p.administrador_efectivo
  FROM public.login_mi_perfil() p WHERE p.activo IS TRUE AND p.empleado_activo IS TRUE AND p.empleado_es_demo IS FALSE
      AND nullif(btrim(p.empleado_pos_id),'') IS NOT NULL AND nullif(btrim(p.empleado_nombre),'') IS NOT NULL
      AND ((p.rol = 'admin' AND p.administrador_efectivo AND (p.sucursal_id IS NULL OR p.sucursal_activa))
        OR (p.rol = 'cajero' AND p.sucursal_id IS NOT NULL AND p.sucursal_activa))
$perfil$;
REVOKE ALL ON FUNCTION public.login_contexto_operativo() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.login_contexto_operativo() TO authenticated;

REVOKE ALL PRIVILEGES ON TABLE public.ventas, public.detalle_venta, public.productos, public.categorias, public.ingredientes, public.empleados_pos, public.sucursales FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.ventas, public.detalle_venta, public.productos, public.categorias, public.ingredientes, public.empleados_pos, public.sucursales TO authenticated;
GRANT INSERT (usuario_id,fecha_hora,total,metodo_pago,subtotal,descuento,codigo_descuento,iva,tasa_iva,iva_incluido,empresa_id,empresa_nombre,sucursal_id,sucursal_nombre,empleado_pos_id,empleado_nombre) ON public.ventas TO authenticated;
GRANT INSERT (venta_id,producto_id,cantidad,precio_unitario) ON public.detalle_venta TO authenticated;
REVOKE ALL ON SEQUENCE public.ventas_id_seq, public.detalle_venta_id_seq, public.productos_id_seq, public.categorias_id_seq, public.ingredientes_id_seq, public.usuarios_id_seq FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SEQUENCE public.ventas_id_seq, public.detalle_venta_id_seq TO authenticated;

ALTER TABLE public.ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.detalle_venta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ingredientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.empleados_pos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sucursales ENABLE ROW LEVEL SECURITY;

CREATE POLICY fase4_historial ON public.ventas FOR SELECT TO authenticated
  USING (empresa_id='texas_burger' AND EXISTS (SELECT FROM public.login_contexto_operativo() p
    WHERE p.sucursal_id IS NULL OR p.sucursal_id=ventas.sucursal_id));
CREATE POLICY fase4_alta ON public.ventas FOR INSERT TO authenticated
  WITH CHECK (empresa_id='texas_burger' AND empresa_nombre='Texas Burger' AND EXISTS (
    SELECT FROM public.login_contexto_operativo() p
    JOIN public.sucursales s ON s.id=ventas.sucursal_id
    WHERE p.usuario_id=ventas.usuario_id AND p.empleado_id=ventas.empleado_pos_id
      AND p.empleado_nombre=ventas.empleado_nombre AND s.activo AND s.empresa_id=ventas.empresa_id
      AND s.nombre=ventas.sucursal_nombre AND (p.sucursal_id IS NULL OR p.sucursal_id=s.id)));
-- La venta padre ya esta filtrada por RLS, incluso para una consulta directa del detalle.
CREATE POLICY fase4_historial ON public.detalle_venta FOR SELECT TO authenticated
  USING (EXISTS (SELECT FROM public.ventas v WHERE v.id=detalle_venta.venta_id));
CREATE POLICY fase4_alta ON public.detalle_venta FOR INSERT TO authenticated
  WITH CHECK (cantidad>0 AND precio_unitario>=0 AND EXISTS (
    SELECT FROM public.ventas v JOIN public.login_contexto_operativo() p
      ON v.usuario_id=p.usuario_id AND v.empleado_pos_id=p.empleado_id
    WHERE v.id=detalle_venta.venta_id AND v.sucursal_id IS NOT NULL)
    AND EXISTS (SELECT FROM public.productos pr WHERE pr.id=detalle_venta.producto_id AND pr.activo));

-- Productos inactivos siguen legibles para mostrar nombres historicos.
CREATE POLICY fase4_catalogo ON public.productos FOR SELECT TO authenticated
  USING (EXISTS (SELECT FROM public.login_contexto_operativo()));
CREATE POLICY fase4_catalogo ON public.categorias FOR SELECT TO authenticated
  USING (EXISTS (SELECT FROM public.login_contexto_operativo()));
CREATE POLICY fase4_catalogo ON public.ingredientes FOR SELECT TO authenticated
  USING (EXISTS (SELECT FROM public.login_contexto_operativo() p WHERE p.admin));
-- Conservar las politicas permisivas anteriores de lectura y acotarlas con AND.
CREATE POLICY fase4_catalogo ON public.sucursales AS RESTRICTIVE FOR SELECT TO authenticated
  USING (empresa_id='texas_burger' AND EXISTS (SELECT FROM public.login_contexto_operativo() p
    WHERE p.sucursal_id IS NULL OR p.sucursal_id=sucursales.id));
CREATE POLICY fase4_catalogo ON public.empleados_pos AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT FROM public.login_contexto_operativo() p
    WHERE p.admin OR p.empleado_id=empleados_pos.id));

-- Detectar privilegios heredados que podrian eludir los REVOKE directos.
DO $post$
DECLARE r text; t text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT FROM pg_roles WHERE rolname=r AND (rolsuper OR rolbypassrls)) THEN
      RAISE EXCEPTION 'Rol cliente elude RLS: %',r; END IF;
    FOREACH t IN ARRAY ARRAY['public.ventas', 'public.detalle_venta', 'public.productos', 'public.categorias', 'public.ingredientes', 'public.empleados_pos', 'public.sucursales'] LOOP
      IF has_table_privilege(r,t,'TRUNCATE,DELETE,TRIGGER,REFERENCES') OR has_any_column_privilege(r,t,'UPDATE')
        OR ((r='anon' OR t NOT IN ('public.ventas','public.detalle_venta')) AND has_any_column_privilege(r,t,'INSERT'))
        OR (r='anon' AND has_any_column_privilege(r,t,'SELECT'))
        OR (t IN ('public.ventas','public.detalle_venta') AND has_column_privilege(r,t,'id','INSERT'))
      THEN RAISE EXCEPTION 'Privilegio inesperado en % para %',t,r; END IF;
    END LOOP;
    FOREACH t IN ARRAY ARRAY['public.ventas_id_seq', 'public.detalle_venta_id_seq', 'public.productos_id_seq', 'public.categorias_id_seq', 'public.ingredientes_id_seq', 'public.usuarios_id_seq'] LOOP
      IF has_sequence_privilege(r,t,'UPDATE,SELECT') OR
        ((r='anon' OR t NOT IN ('public.ventas_id_seq','public.detalle_venta_id_seq')) AND has_sequence_privilege(r,t,'USAGE'))
      THEN RAISE EXCEPTION 'Privilegio inesperado en secuencia % para %',t,r; END IF;
    END LOOP;
  END LOOP;
END;
$post$;
NOTIFY pgrst, 'reload schema';
COMMIT;
