-- PARA REVISION. NO ejecutado. Requiere 004 y 005; no requiere ni modifica 006.
-- Ejecutar como postgres solo despues de revisar y autorizar el despliegue.
-- La Edge Function crea Auth con email_confirm=false y un marcador privado.
-- Las asociaciones se crean juntas. La compensacion bloquea la misma fila Auth:
-- si el alta ya hizo COMMIT, nunca elimina la cuenta ante una respuesta perdida.
BEGIN;
CREATE FUNCTION public.login_completar_alta(
  p_actor uuid, p_auth_uid uuid, p_operacion uuid,
  p_nombre text, p_email text, p_rol text, p_sucursal text,
  p_cancelar boolean DEFAULT false
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $alta$
DECLARE
  v_auth auth.users%ROWTYPE;
  v_id integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Solo backend' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_auth FROM auth.users WHERE id = p_auth_uid FOR UPDATE;
  IF NOT FOUND THEN
    IF p_cancelar IS TRUE THEN RETURN 'cancelled'; END IF;
    RAISE EXCEPTION 'Cuenta Auth no encontrada';
  END IF;
  IF p_operacion IS NULL OR
     v_auth.raw_app_meta_data->>'texas_alta_operacion' IS DISTINCT FROM p_operacion::text OR
     v_auth.raw_app_meta_data->>'texas_alta_actor' IS DISTINCT FROM p_actor::text THEN
    RAISE EXCEPTION 'Operacion no corresponde a esta cuenta' USING ERRCODE = '42501';
  END IF;

  -- Conservar todo registro preexistente. Una respuesta de red perdida no implica rollback.
  IF EXISTS (SELECT 1 FROM public.usuarios WHERE auth_uid = p_auth_uid) THEN
    IF EXISTS (
      SELECT 1 FROM public.usuarios u
      JOIN public.empleados_pos e ON e.usuario_id = u.id
      WHERE u.auth_uid = p_auth_uid AND u.activo IS TRUE
        AND e.activo IS TRUE AND e.es_demo IS FALSE
        AND u.nombre = p_nombre AND u.usuario = p_email AND u.rol = p_rol
        AND u.sucursal_id IS NOT DISTINCT FROM p_sucursal
        AND (u.rol <> 'admin' OR EXISTS (
          SELECT 1 FROM public.inventario_admins a WHERE a.user_id = p_auth_uid AND a.activo IS TRUE
        ))
    ) THEN RETURN 'complete'; END IF;
    RAISE EXCEPTION 'Asociacion existente requiere revision';
  END IF;
  IF p_cancelar IS TRUE THEN
    IF EXISTS (SELECT 1 FROM public.inventario_admins WHERE user_id = p_auth_uid) THEN
      RAISE EXCEPTION 'Cuenta con autorizacion existente; no se elimina';
    END IF;
    -- Solo la cuenta creada por ESTA operacion y sin perfil. FK adicionales
    -- impiden eliminar una cuenta usada por Caja/Inventario. No se borran perfiles.
    DELETE FROM auth.users WHERE id = p_auth_uid;
    RETURN 'cancelled';
  END IF;

  -- Revalidar al administrador dentro de la transaccion, sin user_metadata.
  PERFORM u.id FROM public.usuarios u
  JOIN public.empleados_pos e ON e.usuario_id = u.id
  JOIN public.inventario_admins a ON a.user_id = u.auth_uid
  WHERE u.auth_uid = p_actor AND u.rol = 'admin' AND u.activo IS TRUE
    AND e.activo IS TRUE AND e.es_demo IS FALSE AND a.activo IS TRUE
  FOR SHARE OF u, e, a;
  IF NOT FOUND THEN RAISE EXCEPTION 'Administrador no autorizado' USING ERRCODE = '42501'; END IF;
  IF p_nombre IS NULL OR length(btrim(p_nombre)) NOT BETWEEN 1 AND 255 OR
     p_email IS NULL OR length(p_email) > 255 OR
     p_email IS DISTINCT FROM lower(btrim(v_auth.email)) OR
     p_rol IS NULL OR p_rol NOT IN ('admin', 'cajero') OR
     (p_rol = 'cajero' AND p_sucursal IS NULL) THEN
    RAISE EXCEPTION 'Datos de alta invalidos' USING ERRCODE = '22023';
  END IF;
  IF p_sucursal IS NOT NULL THEN
    PERFORM id FROM public.sucursales WHERE id = p_sucursal
      AND activo IS TRUE AND empresa_id = 'texas_burger' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Sucursal no habilitada'; END IF;
  END IF;
  -- Auth garantiza correo unico; este bloqueo tambien protege la correspondencia
  -- con cuentas empresariales antiguas (usuario no tiene UNIQUE).
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_email, 0));
  IF EXISTS (SELECT 1 FROM public.usuarios WHERE lower(btrim(usuario)) = p_email) THEN
    RAISE EXCEPTION 'Correo ya asociado' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.usuarios(nombre, usuario, rol, activo, auth_uid, sucursal_id)
    VALUES (btrim(p_nombre), p_email, p_rol, true, p_auth_uid, p_sucursal)
    RETURNING id INTO v_id;
  INSERT INTO public.empleados_pos(id, nombre, usuario_id, activo, es_demo)
    VALUES ('emp_' || p_auth_uid::text, btrim(p_nombre), v_id, true, false);
  IF p_rol = 'admin' THEN
    INSERT INTO public.inventario_admins(user_id, activo) VALUES (p_auth_uid, true);
  END IF;
  RETURN 'complete';
END;
$alta$;
ALTER FUNCTION public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean) OWNER TO postgres;
-- Los permisos por defecto del proyecto son amplios: quitar TODOS los receptores.
REVOKE ALL ON FUNCTION public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean) FROM PUBLIC;
DO $acl$
DECLARE v_role record;
BEGIN
  FOR v_role IN
    SELECT DISTINCT r.rolname FROM pg_catalog.pg_proc p
    CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) x
    JOIN pg_catalog.pg_roles r ON r.oid = x.grantee
    WHERE p.oid = 'public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean)'::regprocedure
      AND r.oid <> p.proowner
  LOOP
    EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean) FROM %I', v_role.rolname);
  END LOOP;
END;
$acl$;
GRANT EXECUTE ON FUNCTION public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean) TO service_role;
NOTIFY pgrst, 'reload schema';
COMMIT;
