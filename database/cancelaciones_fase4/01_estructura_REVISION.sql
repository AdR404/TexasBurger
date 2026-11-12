-- LOCAL, no ejecutado. Requiere Login fase4 y Ventas/Inventario fase3 revisada.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $pre$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
 IF to_regprocedure('public.login_contexto_operativo()') IS NULL OR
    to_regprocedure('public.registrar_venta_con_consumo(uuid,jsonb)') IS NULL THEN
   RAISE EXCEPTION 'Faltan dependencias Login/Ventas fase3'; END IF;
 IF NOT EXISTS (SELECT FROM pg_constraint WHERE conrelid='public.inventario_movimientos'::regclass
   AND conname='fase3_movimiento_venta') OR EXISTS
   (SELECT FROM pg_constraint WHERE conrelid='public.inventario_movimientos'::regclass AND conname='fase3_consumo_salida') THEN
   RAISE EXCEPTION 'Revisar fase3: se requiere permitir entrada y salida vinculadas'; END IF;
 IF has_table_privilege('anon','public.ventas','INSERT,UPDATE') OR
    has_table_privilege('authenticated','public.ventas','INSERT,UPDATE') THEN
   RAISE EXCEPTION 'Permisos amplios incompatibles; no se cambian automaticamente'; END IF;
END;
$pre$;
ALTER TABLE public.ventas
 ADD COLUMN estado text NOT NULL DEFAULT 'activa',
 ADD COLUMN cancelada_en timestamptz,
 ADD COLUMN cancelada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 ADD COLUMN cancelacion_motivo text,
 ADD COLUMN inventario_reintegrado boolean NOT NULL DEFAULT false,
 ADD CONSTRAINT fase4_cancelacion_estado CHECK (
   (estado='activa' AND cancelada_en IS NULL AND cancelada_por IS NULL
    AND cancelacion_motivo IS NULL AND NOT inventario_reintegrado)
   OR (estado='cancelada' AND cancelada_en IS NOT NULL AND cancelada_por IS NOT NULL
       AND cancelacion_motivo IS NOT NULL AND length(btrim(cancelacion_motivo))>0));

-- Todos los administradores requieren habilitacion expresa. No se copia inventario_admins.
CREATE TABLE public.cancelacion_permisos (
 usuario_auth_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 sucursal_id text NOT NULL REFERENCES public.sucursales(id) ON DELETE RESTRICT,
 activo boolean NOT NULL DEFAULT true,
 PRIMARY KEY(usuario_auth_id,sucursal_id)
);
ALTER TABLE public.cancelacion_permisos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.cancelacion_permisos FROM PUBLIC,anon,authenticated,service_role;
-- No hay politica cliente: se administra exclusivamente desde SQL Editor postgres.
DO $acl$
DECLARE r record; rol text; col text;
BEGIN
 FOR r IN SELECT DISTINCT roles.rolname FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
  JOIN pg_roles roles ON roles.oid=a.grantee WHERE c.oid='public.cancelacion_permisos'::regclass
  AND a.grantee<>c.relowner LOOP
  EXECUTE format('REVOKE ALL ON TABLE public.cancelacion_permisos FROM %I',r.rolname);
 END LOOP;
 FOREACH rol IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOREACH col IN ARRAY ARRAY['estado','cancelada_en','cancelada_por','cancelacion_motivo','inventario_reintegrado'] LOOP
   IF has_column_privilege(rol,'public.ventas',col,'INSERT,UPDATE') THEN
    RAISE EXCEPTION 'Permiso heredado permite falsificar cancelacion'; END IF;
  END LOOP;
  IF has_table_privilege(rol,'public.cancelacion_permisos','INSERT,UPDATE,DELETE,TRUNCATE') THEN
   RAISE EXCEPTION 'Permiso heredado sobre autorizaciones'; END IF;
 END LOOP;
END;
$acl$;
COMMIT;
