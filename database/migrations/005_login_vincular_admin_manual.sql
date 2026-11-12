-- LOGIN 1B / ETAPA 2. DESPUES de 004. Solo SQL Editor como postgres.
-- Editar unicamente los parametros del bloque. No ejecutar sin elegirlos.
-- Vincula UNA cuenta Auth que YA exista y YA este activa en inventario_admins.
-- No crea cuentas Auth ni perfiles de negocio; crea UN empleado POS real nuevo.
-- No reutiliza empleados existentes, ni siquiera no-demo; asi evita reasignar
-- ventas/historicos de otra persona. Si ya existe el empleado correcto, detener
-- y revisar expresamente su vinculacion en lugar de usar este script.
BEGIN;
DO $vincular$
DECLARE
  v_confirmar boolean := false;          -- Cambiar a true tras revisar.
  v_auth_uid uuid := NULL;               -- UUID REAL elegido en Auth.
  v_usuario_id integer := NULL;          -- ID de negocio admin elegido.
  v_sucursal_id text := NULL;            -- ID REAL, o NULL intencional.
  v_sin_sucursal_confirmado boolean := false; -- true SOLO si admin sin asignacion.
  v_empleado_id text := NULL;            -- ID NUEVO, no demo, elegido manualmente.
  v_empleado_nombre text := NULL;        -- Nombre REAL elegido manualmente.
  v_usuario record;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
  IF v_confirmar IS DISTINCT FROM true OR v_auth_uid IS NULL OR v_usuario_id IS NULL
     OR NULLIF(btrim(v_empleado_id), '') IS NULL
     OR NULLIF(btrim(v_empleado_nombre), '') IS NULL THEN
    RAISE EXCEPTION 'Completar y confirmar los parametros reales; no se realizo la vinculacion';
  END IF;
  IF v_empleado_id <> btrim(v_empleado_id) OR v_empleado_id ~* '^demo_' THEN
    RAISE EXCEPTION 'Elegir un ID nuevo sin espacios extremos ni prefijo demo_';
  END IF;
  IF v_sucursal_id IS NULL AND v_sin_sucursal_confirmado IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Seleccionar sucursal o confirmar expresamente la ausencia de asignacion';
  END IF;

  -- Evitar cambios concurrentes entre las comprobaciones y la vinculacion.
  LOCK TABLE public.usuarios, public.empleados_pos, public.inventario_admins
    IN SHARE ROW EXCLUSIVE MODE;
  PERFORM 1 FROM auth.users WHERE id = v_auth_uid FOR KEY SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'El UUID no corresponde a una cuenta Auth existente'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.inventario_admins WHERE user_id = v_auth_uid AND activo IS TRUE) THEN
    RAISE EXCEPTION 'La cuenta elegida no tiene autorizacion activa en inventario_admins';
  END IF;
  SELECT rol, activo, auth_uid, sucursal_id INTO v_usuario
  FROM public.usuarios WHERE id = v_usuario_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'El usuario de negocio no existe'; END IF;
  IF v_usuario.rol IS DISTINCT FROM 'admin' OR v_usuario.activo IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'El usuario elegido debe ser administrador activo';
  END IF;
  IF v_usuario.auth_uid IS NOT NULL THEN
    RAISE EXCEPTION 'El usuario ya tiene cuenta Auth; no reasignar ni repetir este script';
  END IF;
  IF v_usuario.sucursal_id IS NOT NULL AND v_usuario.sucursal_id IS DISTINCT FROM v_sucursal_id THEN
    RAISE EXCEPTION 'El usuario ya tiene otra sucursal asignada';
  END IF;
  IF EXISTS (SELECT 1 FROM public.usuarios WHERE auth_uid = v_auth_uid) THEN
    RAISE EXCEPTION 'La cuenta Auth ya esta vinculada a otro perfil';
  END IF;
  IF EXISTS (SELECT 1 FROM public.empleados_pos WHERE id = v_empleado_id OR usuario_id = v_usuario_id) THEN
    RAISE EXCEPTION 'El ID de empleado ya existe o el usuario ya tiene empleado; revisar manualmente';
  END IF;
  IF v_sucursal_id IS NOT NULL THEN
    PERFORM 1 FROM public.sucursales
      WHERE id = v_sucursal_id AND empresa_id = 'texas_burger' AND activo IS TRUE FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Sucursal inexistente, inactiva o ajena a Texas Burger'; END IF;
  END IF;

  UPDATE public.usuarios SET auth_uid = v_auth_uid, sucursal_id = v_sucursal_id
  WHERE id = v_usuario_id;
  INSERT INTO public.empleados_pos (id, nombre, es_demo, activo, usuario_id)
  VALUES (v_empleado_id, btrim(v_empleado_nombre), false, true, v_usuario_id);
END;
$vincular$;
COMMIT;

-- VERIFICACION SOLO LECTURA. Revisar ID elegido, empleado nuevo y sucursal.
SELECT u.id AS usuario_id, u.nombre, u.rol, u.activo,
       u.auth_uid IS NOT NULL AS auth_vinculado, u.sucursal_id,
       e.id AS empleado_id, e.nombre AS empleado_nombre, e.es_demo, e.activo AS empleado_activo,
       EXISTS (SELECT 1 FROM public.inventario_admins a WHERE a.user_id = u.auth_uid AND a.activo IS TRUE)
         AS en_lista_admin
FROM public.usuarios u LEFT JOIN public.empleados_pos e ON e.usuario_id = u.id
WHERE u.auth_uid IS NOT NULL;

SELECT count(*) AS empleados_demo, count(*) FILTER (WHERE usuario_id IS NULL) AS demo_sin_usuario
FROM public.empleados_pos WHERE es_demo IS TRUE;
-- Esperado tras la primera vinculacion: un perfil vinculado; tres demo intactos.
-- La segunda cuenta Auth no se vincula ni se desactiva automaticamente.
-- No activar 006 hasta adaptar/probar Flutter; la cuenta no vinculada perdera
-- acceso administrativo cuando se active esa etapa, aunque siga en la lista.
