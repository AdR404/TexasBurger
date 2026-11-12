-- SOLO LECTURA, despues de 01 y 02. Como postgres, inspecciona configuracion, no simula un cliente.
SELECT p.oid::regprocedure AS firma, p.prosecdef, p.proconfig,
       position('public.login_mi_perfil()' IN p.prosrc)>0 AS exige_perfil,
       CASE WHEN proname='caja_abrir_turno' THEN
         position('p.empleado_pos_id = p_empleado_pos_id AND p.empleado_nombre = p_empleado_nombre' IN p.prosrc)>0
       END AS comprueba_responsable,
       has_function_privilege('anon',p.oid,'EXECUTE') AS ejecutable_anon,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS ejecutable_authenticated
FROM pg_proc p WHERE p.oid IN ('inventario_backend.registrar_lote_impl(integer,text,text,text,numeric,numeric,date,date,boolean)'::regprocedure,
'inventario_backend.registrar_baja_impl(bigint,text,numeric,text)'::regprocedure,
'public.caja_abrir_turno(text,text,text,numeric)'::regprocedure,
'public.caja_registrar_movimiento(bigint,text,numeric,text)'::regprocedure,
'public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)'::regprocedure);
-- Cinco perfiles=true, apertura responsable=true; anon=false, authenticated=true.

SELECT tablename,policyname,permissive,cmd,roles,qual,with_check FROM pg_policies
WHERE schemaname='public' AND tablename IN ('ventas', 'detalle_venta', 'productos', 'categorias', 'ingredientes', 'empleados_pos', 'sucursales', 'inventario_admins', 'inventario_lotes', 'inventario_movimientos', 'caja_turnos', 'caja_movimientos') ORDER BY tablename,policyname;

SELECT r.rol,t.tabla,c.relrowsecurity,
  has_table_privilege(r.rol,t.tabla,'SELECT') AS leer,
  has_any_column_privilege(r.rol,t.tabla,'INSERT') AS insertar_alguna_columna,
  has_any_column_privilege(r.rol,t.tabla,'UPDATE') AS actualizar,
  has_table_privilege(r.rol,t.tabla,'TRUNCATE') AS truncar,
  has_table_privilege(r.rol,t.tabla,'DELETE') AS eliminar
FROM unnest(ARRAY['anon','authenticated','service_role']) r(rol)
CROSS JOIN unnest(ARRAY['public.ventas', 'public.detalle_venta', 'public.productos', 'public.categorias', 'public.ingredientes', 'public.empleados_pos', 'public.sucursales', 'public.corte_caja']) t(tabla)
JOIN pg_class c ON c.oid=t.tabla::regclass ORDER BY tabla,rol;
-- anon todo false. authenticated SELECT con RLS, INSERT limitado a ventas/detalle.
-- Para el corte_caja legado ambos roles cliente quedan sin acceso directo.
SELECT r, has_function_privilege(r,'public.login_completar_alta(uuid,uuid,uuid,text,text,text,text,boolean)','EXECUTE') alta,
  has_function_privilege(r,'public.login_mi_perfil()','EXECUTE') perfil,
  has_any_column_privilege(r,'public.usuarios','SELECT') lectura_directa_usuarios
FROM unnest(ARRAY['anon','authenticated','service_role']) r;
-- Alta unicamente service_role entre estos roles. Perfil via authenticated, sin lectura directa de usuarios.

SELECT EXISTS (SELECT FROM auth.users WHERE lower(email)='texas@burguer.com') cuenta_existe,
  EXISTS (SELECT FROM auth.users au JOIN public.inventario_admins a ON a.user_id=au.id
    WHERE lower(au.email)='texas@burguer.com' AND a.activo) lista_activa,
  EXISTS (SELECT FROM auth.users au JOIN public.usuarios u ON u.auth_uid=au.id
    JOIN public.empleados_pos e ON e.usuario_id=u.id JOIN public.inventario_admins a ON a.user_id=au.id
    WHERE lower(au.email)='texas@burguer.com' AND u.activo AND u.rol='admin'
      AND e.activo AND NOT e.es_demo AND a.activo
      AND (u.sucursal_id IS NULL OR EXISTS (SELECT FROM public.sucursales s WHERE s.id=u.sucursal_id AND s.activo))) admin_habilitado;
-- Tambien util antes del cambio. Solo devuelve booleanos, sin datos de acceso.

-- Segunda parte: sustituir UUID por un sujeto REAL. Repetir para admin global,
-- admin fijo (si existe), cajero y cuenta sin perfil. No evalua la validez del JWT;
-- simula sus claims para probar RLS. Login Android verificara Auth real.
BEGIN READ ONLY;
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
  'sub','8de696e4-74eb-4d23-a890-2f6768d3ec9a'::uuid)::text,true);
SET LOCAL ROLE authenticated;
SELECT * FROM public.login_contexto_operativo();
SELECT sucursal_id,count(*) ventas_visibles FROM public.ventas GROUP BY sucursal_id;
SELECT v.sucursal_id,count(*) detalles_visibles FROM public.detalle_venta d
  LEFT JOIN public.ventas v ON v.id=d.venta_id GROUP BY v.sucursal_id;
SELECT (SELECT count(*) FROM public.inventario_lotes) lotes,
       (SELECT count(*) FROM public.caja_turnos) turnos,
       (SELECT count(*) FROM public.productos) productos;
ROLLBACK;
-- Cajero: solo su sucursal, cero lotes/turnos. Sin perfil: cero filas en todos.
-- Admin fijo: solo su sucursal. Admin global: ventas de Texas Burger y turnos/lotes permitidos.
-- Comprobar contra filas conocidas: cero filas por si solo no demuestra aislamiento.
