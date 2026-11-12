-- LOGIN 1B / ETAPA 3 FUTURA. NO ejecutar junto con 004/005.
-- Requiere 004 y 005, Flutter adaptado al perfil, login probado y al menos un
-- administrador real vinculado. Ejecutar manualmente como postgres UNA VEZ.
-- Completar los tres parametros del primer bloque solo cuando corresponda.
-- No cambia ventas, detalles, historial, calculos, firmas RPC ni datos historicos.
-- No registra/desactiva cuentas. Las cuentas sin perfil administrativo completo
-- perderan acceso a Caja e Inventario incluso si siguen en inventario_admins.
-- La gestion futura de usuarios requerira su propia implementacion: este archivo
-- NO habilita escrituras de usuarios desde Flutter ni crea Edge Functions.
BEGIN;
SET LOCAL standard_conforming_strings = on;

DO $preflight$
DECLARE
  v_flutter_adaptado_confirmado boolean := false;
  v_admin_conservado uuid := NULL; -- UUID REAL vinculado y probado tras 005.
  v_aceptar_bloqueo_cuentas_sin_perfil boolean := false;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Ejecutar como postgres'; END IF;
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
      AND e.activo IS TRUE AND e.es_demo IS FALSE AND a.activo IS TRUE
  ) THEN
    RAISE EXCEPTION 'Debe conservarse un administrador activo con perfil y empleado real vinculados';
  END IF;
  IF v_aceptar_bloqueo_cuentas_sin_perfil IS DISTINCT FROM true AND EXISTS (
    SELECT 1 FROM public.inventario_admins a WHERE a.activo IS TRUE AND NOT EXISTS (
      SELECT 1 FROM public.usuarios u
      JOIN public.empleados_pos e ON e.usuario_id = u.id
      WHERE u.auth_uid = a.user_id AND u.activo IS TRUE AND u.rol = 'admin'
        AND e.activo IS TRUE AND e.es_demo IS FALSE
    )
  ) THEN
    RAISE EXCEPTION 'Hay cuentas administrativas sin perfil: vincularlas por separado o aceptar expresamente su bloqueo';
  END IF;
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
  v_nueva constant text := 'IF NOT EXISTS (SELECT 1 FROM public.login_mi_perfil() AS perfil WHERE perfil.administrador_efectivo IS TRUE) THEN';
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
    EXECUTE pg_catalog.regexp_replace(v_definicion, v_patron, v_nueva);
  END LOOP;
END;
$reforzar_rpc$;

-- Conservar las politicas permisivas existentes y agregar un requisito AND.
-- La lectura propia de inventario_admins sigue limitada a auth.uid(); ademas
-- requiere ahora el perfil completo. La RPC de perfil no depende de esa RLS.
CREATE POLICY login_admin_real ON public.inventario_admins
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE));
CREATE POLICY login_admin_real ON public.inventario_lotes
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE));
CREATE POLICY login_admin_real ON public.inventario_movimientos
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE));
CREATE POLICY login_admin_real ON public.caja_turnos
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE));
CREATE POLICY login_admin_real ON public.caja_movimientos
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.login_mi_perfil() p WHERE p.administrador_efectivo IS TRUE));

-- Proteger las asociaciones de identidad. En la inspeccion, RLS ya impide
-- INSERT/UPDATE desde el cliente, pero TRUNCATE NO esta sujeto a RLS.
-- Aplicar solamente en esta etapa futura; mantener SELECT y politicas de lectura.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.empleados_pos, public.sucursales FROM PUBLIC, anon, authenticated;
-- No se otorgan escrituras en usuarios ni se cambian privilegios por defecto.
NOTIFY pgrst, 'reload schema';
COMMIT;

-- VERIFICACION SOLO LECTURA. Ejecutar tambien despues de aplicar por separado.
SELECT tablename, policyname, permissive, roles, cmd, qual
FROM pg_catalog.pg_policies WHERE schemaname = 'public' AND policyname = 'login_admin_real';
-- Esperado: cinco politicas RESTRICTIVE / SELECT / authenticated.

SELECT n.nspname AS esquema, p.proname, p.prosecdef, p.proconfig, p.proacl,
       position('public.login_mi_perfil()' IN p.prosrc) > 0 AS exige_perfil
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE p.oid IN (
  'inventario_backend.registrar_lote_impl(integer,text,text,text,numeric,numeric,date,date,boolean)'::regprocedure,
  'inventario_backend.registrar_baja_impl(bigint,text,numeric,text)'::regprocedure,
  'public.caja_abrir_turno(text,text,text,numeric)'::regprocedure,
  'public.caja_registrar_movimiento(bigint,text,numeric,text)'::regprocedure,
  'public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)'::regprocedure
);
-- Esperado: cinco funciones con exige_perfil=true; ACL anteriores conservadas.

SELECT count(*) AS cuentas_activas,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.usuarios u JOIN public.empleados_pos e ON e.usuario_id = u.id
         WHERE u.auth_uid = a.user_id AND u.activo IS TRUE AND u.rol = 'admin'
           AND e.activo IS TRUE AND e.es_demo IS FALSE
       )) AS administradores_con_perfil_completo
FROM public.inventario_admins a WHERE a.activo IS TRUE;

SELECT r.rolname, t.tabla,
       pg_catalog.has_table_privilege(r.oid, t.tabla, 'TRUNCATE') AS truncar,
       pg_catalog.has_any_column_privilege(r.oid, t.tabla, 'INSERT') AS insertar,
       pg_catalog.has_any_column_privilege(r.oid, t.tabla, 'UPDATE') AS actualizar
FROM pg_catalog.pg_roles r
CROSS JOIN (VALUES ('public.usuarios'), ('public.empleados_pos'), ('public.sucursales')) t(tabla)
WHERE r.rolname IN ('anon', 'authenticated');
-- Esperado: false en las tres columnas de permisos.
-- Probar login_mi_perfil() desde sesiones reales admin/cajero y comprobar lecturas
-- de Caja/Inventario. No llamar RPC de escritura como prueba sin autorizacion.
-- Esta etapa NO impone sucursal a los administradores ni cambia la atribucion de
-- empleado recibida por caja_abrir_turno; conserva el contrato de esas funciones.
-- Ventas/detalles conservan sus permisos amplios por alcance de esta fase: el
-- perfil de login NO constituye por si solo seguridad completa de esos modulos.
