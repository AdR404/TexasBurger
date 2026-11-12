-- LOGIN 1B / ETAPA 1. Ejecutar manualmente como postgres, UNA SOLA VEZ.
-- Compatible con el estado confirmado por 003 (PostgreSQL 17.11).
-- No cambia RLS ni permisos de tablas existentes, ni RPC de Caja/Inventario.
-- No asigna cuentas Auth y no cambia datos existentes. No ejecutar 005/006
-- automaticamente: tienen parametros y condiciones independientes.
BEGIN;

-- Fallar si el entorno cambio; no ocultar una instalacion parcial con IF NOT EXISTS.
DO $preflight$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Ejecutar desde SQL Editor como postgres';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
    WHERE r.rolname IN ('anon', 'authenticated')
      AND (pg_catalog.has_any_column_privilege(r.oid, 'public.usuarios', 'SELECT')
        OR pg_catalog.has_any_column_privilege(r.oid, 'public.usuarios', 'INSERT')
        OR pg_catalog.has_any_column_privilege(r.oid, 'public.usuarios', 'UPDATE')
        OR pg_catalog.has_table_privilege(r.oid, 'public.usuarios', 'DELETE,TRUNCATE,TRIGGER'))
  ) THEN
    RAISE EXCEPTION 'Los permisos de usuarios difieren de la inspeccion: revisar antes de continuar';
  END IF;
END;
$preflight$;

ALTER TABLE public.usuarios
  ADD COLUMN auth_uid uuid,
  ADD COLUMN sucursal_id text,
  ADD CONSTRAINT usuarios_auth_uid_key UNIQUE (auth_uid),
  ADD CONSTRAINT usuarios_auth_uid_fkey FOREIGN KEY (auth_uid)
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  ADD CONSTRAINT usuarios_sucursal_id_fkey FOREIGN KEY (sucursal_id)
    REFERENCES public.sucursales(id) ON DELETE RESTRICT;

-- Supabase valida el JWT; auth.uid()/auth.role() provienen de sus claims firmados.
-- Nunca recibe UUID ni rol desde el formulario. Sin perfil devuelve cero filas.
-- Un perfil inactivo se devuelve con su estado para explicar el bloqueo en UI;
-- NO basta con recibir una fila para permitir operar.
CREATE FUNCTION public.login_mi_perfil()
RETURNS TABLE (
  usuario_id integer, nombre text, rol text, activo boolean,
  sucursal_id text, sucursal_nombre text, sucursal_activa boolean,
  empleado_pos_id text, empleado_nombre text, empleado_activo boolean,
  empleado_es_demo boolean, administrador_efectivo boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $perfil$
  SELECT u.id, u.nombre::text, u.rol::text, u.activo,
         u.sucursal_id, s.nombre, s.activo,
         e.id, e.nombre, e.activo, e.es_demo,
         (u.activo IS TRUE AND u.rol = 'admin'
          AND e.id IS NOT NULL AND e.activo IS TRUE AND e.es_demo IS FALSE
          AND EXISTS (
            SELECT 1 FROM public.inventario_admins a
            WHERE a.user_id = u.auth_uid AND a.activo IS TRUE
          )) IS TRUE
  FROM public.usuarios u
  LEFT JOIN public.sucursales s ON s.id = u.sucursal_id
  LEFT JOIN public.empleados_pos e ON e.usuario_id = u.id
  WHERE u.auth_uid = (SELECT auth.uid())
    AND (SELECT auth.role()) = 'authenticated';
$perfil$;

-- El esquema public concede EXECUTE por defecto a varios roles.
-- Revocar explicitamente a PUBLIC y a TODOS los receptores distintos del dueno
-- del objeto nuevo, sin cambiar los DEFAULT PRIVILEGES del proyecto compartido.
REVOKE ALL ON FUNCTION public.login_mi_perfil() FROM PUBLIC;
DO $acl$
DECLARE v_role record;
BEGIN
  FOR v_role IN
    SELECT DISTINCT r.rolname
    FROM pg_catalog.pg_proc p
    CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) x
    JOIN pg_catalog.pg_roles r ON r.oid = x.grantee
    WHERE p.oid = 'public.login_mi_perfil()'::regprocedure
      AND r.oid <> p.proowner
  LOOP
    EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION public.login_mi_perfil() FROM %I', v_role.rolname);
  END LOOP;
END;
$acl$;
GRANT EXECUTE ON FUNCTION public.login_mi_perfil() TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- VERIFICACION SOLO LECTURA (se puede ejecutar nuevamente por separado).
-- No mostrar SELECT * de usuarios ni consultar password_hash.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'usuarios'
  AND column_name IN ('auth_uid', 'sucursal_id');

SELECT conname, pg_catalog.pg_get_constraintdef(oid) AS definicion
FROM pg_catalog.pg_constraint
WHERE conrelid = 'public.usuarios'::regclass
  AND conname IN ('usuarios_auth_uid_key', 'usuarios_auth_uid_fkey', 'usuarios_sucursal_id_fkey');

SELECT r.rolname,
  pg_catalog.has_function_privilege(r.oid, 'public.login_mi_perfil()', 'EXECUTE') AS ejecutar_perfil,
  pg_catalog.has_any_column_privilege(r.oid, 'public.usuarios', 'SELECT') AS leer_usuarios,
  pg_catalog.has_column_privilege(r.oid, 'public.usuarios', 'password_hash', 'SELECT') AS leer_hash
FROM pg_catalog.pg_roles r WHERE r.rolname IN ('anon', 'authenticated');
-- Esperado: anon=false/false/false; authenticated=true/false/false.

SELECT pg_catalog.pg_get_userbyid(proowner) AS propietario, prosecdef, proconfig
FROM pg_catalog.pg_proc WHERE oid = 'public.login_mi_perfil()'::regprocedure;
-- Esperado: postgres, true, search_path vacio.
-- La prueba funcional sera una RPC GET/POST de SOLO LECTURA desde una sesion
-- Auth real, sin argumentos. En SQL Editor sin JWT devuelve cero filas.
-- Las ACL de usuarios ya impiden leer hashes. NO se habilita RLS aqui: no hace
-- falta para esta RPC filtrada y evitamos cambiar el comportamiento de terceros.
-- La lectura directa usuarios(id,activo) que hoy usa el cobro NO queda habilitada.
-- Cuando Flutter use empleados vinculados debe adaptar esa comprobacion a este
-- perfil; de lo contrario el codigo antiguo fallara por permisos como ya ocurre
-- con cualquier empleado vinculado. Los tres empleados demo no se modifican.
