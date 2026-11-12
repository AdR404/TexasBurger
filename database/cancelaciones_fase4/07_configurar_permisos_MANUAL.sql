-- LOCAL. Ejecutar bloques A, B y C POR SEPARADO en SQL Editor como postgres.
-- No asigna nada sin completar expresamente UUID y lista de sucursales en B.

-- A. SOLO LECTURA: identificar las cuentas por usuarios.auth_uid -> auth.users.id.
-- Nombre/correo sirven para revisar; el identificador definitivo es el UUID Auth.
SELECT u.id usuario_id,u.auth_uid,au.email,u.nombre,u.rol,u.activo,
 u.sucursal_id,e.id empleado_id,e.activo empleado_activo,e.es_demo,
 coalesce(a.activo,false) habilitado_inventario
FROM public.usuarios u JOIN auth.users au ON au.id=u.auth_uid
LEFT JOIN public.empleados_pos e ON e.usuario_id=u.id
LEFT JOIN public.inventario_admins a ON a.user_id=u.auth_uid
WHERE u.rol='admin' ORDER BY u.id;
SELECT id,nombre,activo FROM public.sucursales WHERE empresa_id='texas_burger' ORDER BY id;

-- B. ASIGNACION MANUAL: ejecutar UNA vez por cuenta que decidan autorizar.
-- Daniel general: su UUID verificado y ARRAY['norte','perimetral_sur'], si se aprueba.
-- Rigoberto fijo Norte: su UUID verificado y ARRAY['norte'], si se aprueba.
-- Verificar los IDs de sucursal en A; los nombres no se usan para resolver cuentas.
BEGIN;
DO $configurar$
DECLARE
 cuenta uuid := NULL; -- Sustituir por UUID de auth.users verificado en A.
 sucursales text[] := ARRAY[]::text[]; -- Solo las autorizaciones decididas.
 perfil record;
BEGIN
 IF current_user<>'postgres' OR cuenta IS NULL OR coalesce(cardinality(sucursales),0)=0 THEN
  RAISE EXCEPTION 'Completar UUID y sucursales expresamente; ejecutar como postgres'; END IF;
 SELECT u.id,u.sucursal_id INTO perfil
 FROM public.usuarios u JOIN auth.users au ON au.id=u.auth_uid
 JOIN public.empleados_pos e ON e.usuario_id=u.id
 JOIN public.inventario_admins a ON a.user_id=u.auth_uid
 WHERE u.auth_uid=cuenta AND u.rol='admin' AND u.activo IS TRUE
   AND e.activo IS TRUE AND e.es_demo IS FALSE AND a.activo IS TRUE
 FOR SHARE OF u,e,a;
 IF NOT FOUND THEN RAISE EXCEPTION 'La cuenta no tiene perfil administrador efectivo'; END IF;
 IF EXISTS (SELECT FROM unnest(sucursales) AS elegida(id) WHERE elegida.id IS NULL
   OR (perfil.sucursal_id IS NOT NULL AND perfil.sucursal_id<>elegida.id)
   OR NOT EXISTS (SELECT FROM public.sucursales s WHERE s.id=elegida.id
     AND s.activo IS TRUE AND s.empresa_id='texas_burger')) THEN
  RAISE EXCEPTION 'Sucursal inexistente/inactiva o fuera de la asignacion fija del administrador'; END IF;
 INSERT INTO public.cancelacion_permisos(usuario_auth_id,sucursal_id,activo)
 SELECT DISTINCT cuenta,id,true FROM unnest(sucursales) AS elegida(id)
 ON CONFLICT(usuario_auth_id,sucursal_id) DO UPDATE SET activo=true;
END;
$configurar$;
COMMIT;
-- Solo agrega/reactiva las parejas indicadas, NO revoca otras autorizaciones.
-- Revisar C completo antes de dar por terminada la configuracion.

-- C. SOLO LECTURA: verificar autorizaciones y su compatibilidad con el perfil.
SELECT p.usuario_auth_id,u.id usuario_id,au.email,u.nombre,p.sucursal_id,
 s.nombre sucursal,p.activo permiso_activo,u.sucursal_id sucursal_asignada,
 (u.rol='admin' AND u.activo IS TRUE AND e.activo IS TRUE AND e.es_demo IS FALSE
  AND a.activo IS TRUE AND s.activo IS TRUE AND s.empresa_id='texas_burger'
  AND (u.sucursal_id IS NULL OR u.sucursal_id=p.sucursal_id)) IS TRUE perfil_compatible
FROM public.cancelacion_permisos p JOIN auth.users au ON au.id=p.usuario_auth_id
LEFT JOIN public.usuarios u ON u.auth_uid=p.usuario_auth_id
LEFT JOIN public.empleados_pos e ON e.usuario_id=u.id
LEFT JOIN public.inventario_admins a ON a.user_id=p.usuario_auth_id
JOIN public.sucursales s ON s.id=p.sucursal_id ORDER BY u.id,p.sucursal_id;
