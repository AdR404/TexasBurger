-- Sustituye al 006 original. Primero exportar el resultado de 00_respaldo.sql.
-- Completar los tres parámetros de revisión antes del mantenimiento.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL standard_conforming_strings = on;

DO $preflight$
DECLARE
  v_flutter_adaptado_confirmado boolean := true;
  v_admin_conservado uuid := '8de696e4-74eb-4d23-a890-2f6768d3ec9a';
  v_aceptar_bloqueo_cuentas_sin_perfil boolean := true;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
  -- La fase conserva el canal de escritura privilegiado. Si existen vias
  -- directas inesperadas no basta con endurecer las RPC.
  IF EXISTS (
    SELECT FROM unnest(ARRAY['anon','authenticated']) r,
      unnest(ARRAY['public.usuarios','public.inventario_admins','public.inventario_lotes',
        'public.inventario_movimientos','public.caja_turnos','public.caja_movimientos']) t
    WHERE has_any_column_privilege(r,t,'INSERT,UPDATE') OR has_table_privilege(r,t,'DELETE,TRUNCATE,TRIGGER')
      OR (t='public.usuarios' AND has_any_column_privilege(r,t,'SELECT'))
  ) THEN RAISE EXCEPTION 'Permisos directos inesperados en usuarios, Caja o Inventario'; END IF;
  IF v_flutter_adaptado_confirmado IS DISTINCT FROM true OR v_admin_conservado IS NULL THEN
    RAISE EXCEPTION 'Etapa futura bloqueada: adaptar/probar Flutter y elegir administrador conservado';
  END IF;
  LOCK TABLE public.usuarios, public.empleados_pos, public.inventario_admins
    IN SHARE ROW EXCLUSIVE MODE;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios u
    JOIN public.empleados_pos e ON e.usuario_id = u.id
    JOIN public.inventario_admins a ON a.user_id = u.auth_uid
    WHERE u.auth_uid = v_admin_conservado AND u.activo IS TRUE AND u.rol = 'admin'
      AND (u.sucursal_id IS NULL OR EXISTS (SELECT 1 FROM public.sucursales s WHERE s.id = u.sucursal_id AND s.activo AND s.empresa_id = 'texas_burger'))
      AND e.activo IS TRUE AND e.es_demo IS FALSE AND length(btrim(e.id))>0 AND length(btrim(e.nombre))>0 AND a.activo IS TRUE
  ) THEN
    RAISE EXCEPTION 'Debe conservarse un administrador activo con perfil y empleado real vinculados';
  END IF;
  IF v_aceptar_bloqueo_cuentas_sin_perfil IS DISTINCT FROM true AND EXISTS (
    SELECT 1 FROM public.inventario_admins a WHERE a.activo IS TRUE AND NOT EXISTS (
      SELECT 1 FROM public.usuarios u
      JOIN public.empleados_pos e ON e.usuario_id = u.id
      WHERE u.auth_uid = a.user_id AND u.activo IS TRUE AND u.rol = 'admin'
        AND (u.sucursal_id IS NULL OR EXISTS (SELECT 1 FROM public.sucursales s WHERE s.id = u.sucursal_id AND s.activo AND s.empresa_id = 'texas_burger'))
      AND e.activo IS TRUE AND e.es_demo IS FALSE AND length(btrim(e.id))>0 AND length(btrim(e.nombre))>0
    )
  ) THEN
    RAISE EXCEPTION 'Hay cuentas administrativas sin perfil: vincularlas por separado o aceptar expresamente su bloqueo';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.caja_turnos t WHERE t.fecha_cierre IS NULL AND NOT EXISTS (
      SELECT 1 FROM public.sucursales s JOIN public.usuarios u ON u.sucursal_id IS NULL OR u.sucursal_id = s.id
      JOIN public.empleados_pos e ON e.usuario_id = u.id
      JOIN public.inventario_admins a ON a.user_id = u.auth_uid
      WHERE s.id = t.sucursal_id AND s.activo AND s.empresa_id = t.empresa_id
        AND u.activo AND u.rol = 'admin' AND e.activo AND NOT e.es_demo AND length(btrim(e.id))>0 AND length(btrim(e.nombre))>0 AND a.activo
    )
  ) THEN RAISE EXCEPTION 'Turno abierto sin administrador habilitado para cerrarlo'; END IF;
  -- La RPC de perfil lee estas tablas como su propietario. Evitar recursion RLS
  -- si alguien cambio propietario/FORCE RLS desde la instalacion compatible.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = 'public.login_mi_perfil()'::regprocedure
      AND p.proowner = 'postgres'::regrole AND p.prosecdef
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    WHERE c.oid IN ('public.usuarios'::regclass, 'public.empleados_pos'::regclass,
                   'public.inventario_admins'::regclass, 'public.sucursales'::regclass)
      AND (c.relowner <> 'postgres'::regrole OR c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'Propietarios o FORCE RLS cambiaron: revisar antes de aplicar';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    WHERE c.oid IN ('public.inventario_admins'::regclass, 'public.inventario_lotes'::regclass,
                   'public.inventario_movimientos'::regclass, 'public.caja_turnos'::regclass,
                   'public.caja_movimientos'::regclass)
      AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'RLS fue deshabilitado en Caja/Inventario: revisar antes de aplicar';
  END IF;
END;
$preflight$;

-- Modificar SOLO la condicion de autorizacion de las cinco implementaciones
-- confirmadas por la inspeccion. pg_get_functiondef conserva sus cuerpos reales;
-- no reconstruimos calculos, bloqueos, INSERT ni UPDATE a partir de un borrador.
-- El patron exige exactamente la comprobacion antigua una sola vez. Si cambio,
-- se aborta TODA la transaccion para revisar el nuevo codigo instalado.
-- CREATE OR REPLACE sobre funciones existentes conserva propietario y ACL.
-- Los wrappers public.inventario_registrar_* permanecen intactos: el control se
-- aplica tambien a llamadas directas a inventario_backend.*_impl.
DO $reforzar_rpc$
DECLARE
  v_firma text;
  v_oid oid;
  v_definicion text;
  v_cuerpo text;
  v_coincidencias integer;
  v_patron constant text := 'IF[[:space:]]+v_actor[[:space:]]+IS[[:space:]]+NULL[[:space:]]+OR[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]*\([[:space:]]*SELECT[[:space:]]+1[[:space:]]+FROM[[:space:]]+public\.inventario_admins[[:space:]]+WHERE[[:space:]]+user_id[[:space:]]*=[[:space:]]*v_actor[[:space:]]+AND[[:space:]]+activo[[:space:]]+IS[[:space:]]+TRUE[[:space:]]*\)[[:space:]]+THEN';
  v_nueva text;
BEGIN
  FOREACH v_firma IN ARRAY ARRAY[
    'inventario_backend.registrar_lote_impl(integer,text,text,text,numeric,numeric,date,date,boolean)',
    'inventario_backend.registrar_baja_impl(bigint,text,numeric,text)',
    'public.caja_abrir_turno(text,text,text,numeric)',
    'public.caja_registrar_movimiento(bigint,text,numeric,text)',
    'public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)'
  ] LOOP
    v_oid := pg_catalog.to_regprocedure(v_firma);
    IF v_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid = p.prolang
      WHERE p.oid = v_oid AND p.proowner = 'postgres'::regrole
        AND p.prosecdef AND p.prorettype = 'bigint'::regtype AND l.lanname = 'plpgsql'
        AND 'search_path=""' = ANY(p.proconfig)
    ) THEN
      RAISE EXCEPTION 'Funcion ausente o configuracion distinta de la inspeccion: %', v_firma;
    END IF;
    SELECT p.prosrc, pg_catalog.pg_get_functiondef(p.oid)
      INTO v_cuerpo, v_definicion FROM pg_catalog.pg_proc p WHERE p.oid = v_oid;
    SELECT count(*) INTO v_coincidencias FROM pg_catalog.regexp_matches(v_cuerpo, v_patron, 'g');
    IF v_coincidencias <> 1 THEN
      RAISE EXCEPTION 'No se encontro exactamente un control antiguo en %; revisar sin reemplazar', v_firma;
    END IF;
    v_nueva := 'IF NOT EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE AND length(btrim(p.empleado_pos_id))>0 AND length(btrim(p.empleado_nombre))>0 AND (p.sucursal_id IS NULL OR p.sucursal_activa IS TRUE) AND ' ||
      CASE v_firma
        WHEN 'public.caja_abrir_turno(text,text,text,numeric)' THEN
          'p.empleado_pos_id = p_empleado_pos_id AND p.empleado_nombre = p_empleado_nombre AND (p.sucursal_id IS NULL OR p.sucursal_id = p_sucursal_id)'
        WHEN 'inventario_backend.registrar_lote_impl(integer,text,text,text,numeric,numeric,date,date,boolean)' THEN
          '(p.sucursal_id IS NULL OR p.sucursal_id = p_sucursal_id)'
        WHEN 'inventario_backend.registrar_baja_impl(bigint,text,numeric,text)' THEN
          '(p.sucursal_id IS NULL OR EXISTS (SELECT 1 FROM public.inventario_lotes l WHERE l.id = p_lote_id AND l.sucursal_id = p.sucursal_id))'
        ELSE
          '(p.sucursal_id IS NULL OR EXISTS (SELECT 1 FROM public.caja_turnos t WHERE t.id = p_turno_id AND t.sucursal_id = p.sucursal_id))'
      END || ') THEN';
    EXECUTE pg_catalog.regexp_replace(v_definicion, v_patron, v_nueva);
  END LOOP;
END;
$reforzar_rpc$;

CREATE POLICY fase4_admin ON public.inventario_admins AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE AND length(btrim(p.empleado_pos_id))>0 AND length(btrim(p.empleado_nombre))>0 AND (p.sucursal_id IS NULL OR p.sucursal_activa IS TRUE)
    AND inventario_admins.user_id = auth.uid()));

CREATE POLICY fase4_admin ON public.inventario_lotes AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE AND length(btrim(p.empleado_pos_id))>0 AND length(btrim(p.empleado_nombre))>0 AND (p.sucursal_id IS NULL OR p.sucursal_activa IS TRUE)
    AND (p.sucursal_id IS NULL OR inventario_lotes.sucursal_id = p.sucursal_id)));

CREATE POLICY fase4_admin ON public.inventario_movimientos AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE AND length(btrim(p.empleado_pos_id))>0 AND length(btrim(p.empleado_nombre))>0 AND (p.sucursal_id IS NULL OR p.sucursal_activa IS TRUE)
    AND (p.sucursal_id IS NULL OR EXISTS (SELECT 1 FROM public.inventario_lotes l WHERE l.id = inventario_movimientos.lote_id AND l.sucursal_id = p.sucursal_id))));

CREATE POLICY fase4_admin ON public.caja_turnos AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE AND length(btrim(p.empleado_pos_id))>0 AND length(btrim(p.empleado_nombre))>0 AND (p.sucursal_id IS NULL OR p.sucursal_activa IS TRUE)
    AND (p.sucursal_id IS NULL OR caja_turnos.sucursal_id = p.sucursal_id)));

CREATE POLICY fase4_admin ON public.caja_movimientos AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE AND length(btrim(p.empleado_pos_id))>0 AND length(btrim(p.empleado_nombre))>0 AND (p.sucursal_id IS NULL OR p.sucursal_activa IS TRUE)
    AND (p.sucursal_id IS NULL OR EXISTS (SELECT 1 FROM public.caja_turnos t WHERE t.id = caja_movimientos.turno_id AND t.sucursal_id = p.sucursal_id))));

NOTIFY pgrst, 'reload schema';
COMMIT;
