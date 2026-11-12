-- FASE LOGIN 1: INSPECCION PREVIA. NO ES UNA MIGRACION PARA APLICAR CAMBIOS.
-- Ejecutar manualmente en Supabase SQL Editor con la cuenta administradora.
-- Una sola consulta devuelve un JSON con todos los resultados.
-- No crea objetos, no cambia permisos ni datos y no invoca RPC de la app.
-- No consulta valores de password_hash, contrasenas, emails, tokens ni auth.users.
-- Las definiciones SQL se incluyen para revisar los controles existentes.
-- Revisar esas definiciones antes de compartir el resultado por si el equipo
-- hubiera incluido secretos literalmente dentro de alguna funcion antigua.
-- Conservar los resultados: faltan para preparar la migracion definitiva.
-- No volver a ejecutar los scripts 001/002 para esta inspeccion.

WITH objetivos AS (
  SELECT c.oid, n.nspname AS esquema, c.relname AS tabla,
         c.relkind, c.relrowsecurity AS rls,
         c.relforcerowsecurity AS rls_forzado,
         pg_get_userbyid(c.relowner) AS propietario, c.relacl
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN (
      'usuarios', 'empleados_pos', 'sucursales', 'inventario_admins',
      'ventas', 'detalle_venta', 'productos', 'categorias', 'categoria',
      'ingredientes', 'inventario_lotes', 'inventario_movimientos',
      'caja_turnos', 'caja_movimientos', 'corte_caja'
    )
), roles_cliente AS (
  SELECT oid, rolname, rolsuper, rolbypassrls, rolinherit
  FROM pg_roles WHERE rolname IN ('anon', 'authenticated', 'service_role')
), funciones_usuario AS (
  SELECT p.oid, n.nspname AS esquema, p.proname AS nombre,
         pg_get_function_identity_arguments(p.oid) AS argumentos,
         pg_get_function_result(p.oid) AS retorno,
         p.prosecdef AS security_definer,
         pg_get_userbyid(p.proowner) AS propietario,
         p.proconfig AS configuracion, p.proacl AS privilegios,
         pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.prokind = 'f'
    AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'auth',
      'storage', 'realtime', 'extensions', 'vault', 'graphql', 'graphql_public')
    AND n.nspname NOT LIKE 'pg_%'
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
        AND d.deptype = 'e'
    )
), funciones AS (
  SELECT * FROM funciones_usuario
  WHERE nombre ~* '(caja|inventario|perfil|usuario|admin)'
     OR definicion ~* '(usuarios|empleados_pos|inventario_admins|caja_turnos|inventario_lotes|auth\.uid)'
), vistas AS (
  SELECT DISTINCT v.oid, ns.nspname AS esquema, v.relname AS nombre,
         pg_get_userbyid(v.relowner) AS propietario,
         v.reloptions AS opciones, v.relacl AS privilegios,
         pg_get_viewdef(v.oid, true) AS definicion
  FROM pg_depend d
  JOIN pg_rewrite rw ON d.classid = 'pg_rewrite'::regclass AND rw.oid = d.objid
  JOIN pg_class v ON v.oid = rw.ev_class AND v.relkind IN ('v', 'm')
  JOIN pg_namespace ns ON ns.oid = v.relnamespace
  WHERE d.refclassid = 'pg_class'::regclass
    AND d.refobjid IN (SELECT oid FROM objetivos)
)
SELECT jsonb_build_object(
  'servidor', jsonb_build_object(
    'version', current_setting('server_version'),
    'rol_consulta', current_user,
    'esquemas_postgrest_configurados', current_setting('pgrst.db_schemas', true)
  ),
  'tablas', COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tabla)
    FROM objetivos t), '[]'::jsonb),
  'columnas', COALESCE((SELECT jsonb_agg(to_jsonb(q) ORDER BY q.tabla, q.posicion)
    FROM (
      SELECT o.tabla, a.attnum AS posicion, a.attname AS columna,
             format_type(a.atttypid, a.atttypmod) AS tipo,
             a.attnotnull AS no_nulo, a.attidentity AS identidad,
             a.attgenerated AS generada,
             CASE WHEN a.attname = 'password_hash' THEN NULL
                  ELSE pg_get_expr(ad.adbin, ad.adrelid) END AS valor_por_defecto,
             a.attacl AS privilegios_columna
      FROM objetivos o JOIN pg_attribute a ON a.attrelid = o.oid
      LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
      WHERE a.attnum > 0 AND NOT a.attisdropped
    ) q), '[]'::jsonb),
  'restricciones_y_dependencias_fk', COALESCE((SELECT jsonb_agg(to_jsonb(q))
    FROM (
      SELECT con.conrelid::regclass::text AS tabla, con.conname AS nombre,
             con.contype AS tipo, con.convalidated AS validada,
             pg_get_constraintdef(con.oid, true) AS definicion
      FROM pg_constraint con
      WHERE con.conrelid IN (SELECT oid FROM objetivos)
         OR con.confrelid IN (SELECT oid FROM objetivos)
    ) q), '[]'::jsonb),
  'indices', COALESCE((SELECT jsonb_agg(to_jsonb(q)) FROM (
    SELECT o.tabla, pg_get_indexdef(i.indexrelid) AS definicion,
           i.indisvalid AS valido, i.indisunique AS unico
    FROM objetivos o JOIN pg_index i ON i.indrelid = o.oid
  ) q), '[]'::jsonb),
  'politicas', COALESCE((SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename IN (SELECT tabla FROM objetivos)), '[]'::jsonb),
  'roles', COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM roles_cliente r), '[]'::jsonb),
  'privilegios_efectivos_tablas', COALESCE((SELECT jsonb_agg(to_jsonb(q)) FROM (
    SELECT r.rolname AS rol, o.tabla,
      has_schema_privilege(r.oid, 'public', 'USAGE') AS uso_esquema,
      has_table_privilege(r.oid, o.oid, 'SELECT') AS seleccion_tabla,
      has_table_privilege(r.oid, o.oid, 'INSERT') AS insertar,
      has_table_privilege(r.oid, o.oid, 'UPDATE') AS actualizar,
      has_table_privilege(r.oid, o.oid, 'DELETE') AS eliminar,
      has_table_privilege(r.oid, o.oid, 'TRUNCATE') AS truncar,
      has_table_privilege(r.oid, o.oid, 'TRIGGER') AS crear_trigger
    FROM objetivos o CROSS JOIN roles_cliente r
  ) q), '[]'::jsonb),
  'privilegios_efectivos_columnas_identidad', COALESCE((SELECT jsonb_agg(to_jsonb(q)) FROM (
    SELECT r.rolname AS rol, o.tabla, a.attname AS columna,
      has_column_privilege(r.oid, o.oid, a.attnum, 'SELECT') AS leer,
      has_column_privilege(r.oid, o.oid, a.attnum, 'INSERT') AS insertar,
      has_column_privilege(r.oid, o.oid, a.attnum, 'UPDATE') AS actualizar
    FROM objetivos o JOIN pg_attribute a ON a.attrelid = o.oid
    CROSS JOIN roles_cliente r
    WHERE o.tabla IN ('usuarios', 'empleados_pos', 'sucursales', 'inventario_admins')
      AND a.attnum > 0 AND NOT a.attisdropped
  ) q), '[]'::jsonb),
  'funciones_y_privilegios', COALESCE((SELECT jsonb_agg(to_jsonb(f) || jsonb_build_object(
    'ejecucion_roles', (SELECT jsonb_agg(jsonb_build_object(
      'rol', r.rolname, 'puede_ejecutar', has_function_privilege(r.oid, f.oid, 'EXECUTE')
    )) FROM roles_cliente r)
  )) FROM funciones f), '[]'::jsonb),
  'triggers', COALESCE((SELECT jsonb_agg(to_jsonb(q)) FROM (
    SELECT t.tgrelid::regclass::text AS tabla, t.tgname AS nombre,
           t.tgenabled AS estado, pg_get_triggerdef(t.oid, true) AS definicion,
           pg_get_functiondef(t.tgfoid) AS funcion
    FROM pg_trigger t
    WHERE NOT t.tgisinternal AND t.tgrelid IN (SELECT oid FROM objetivos)
  ) q), '[]'::jsonb),
  'vistas_dependientes', COALESCE((SELECT jsonb_agg(to_jsonb(v)) FROM vistas v), '[]'::jsonb),
  'permisos_por_defecto', COALESCE((SELECT jsonb_agg(to_jsonb(q)) FROM (
    SELECT pg_get_userbyid(d.defaclrole) AS propietario,
      COALESCE(n.nspname, '(global)') AS esquema,
      d.defaclobjtype AS tipo_objeto, d.defaclacl AS privilegios
    FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
    WHERE d.defaclnamespace = 0 OR n.nspname IN ('public', 'private')
  ) q), '[]'::jsonb),
  'secuencias_relacionadas', COALESCE((SELECT jsonb_agg(to_jsonb(q)) FROM (
    SELECT o.tabla, ns.nspname AS esquema, s.relname AS secuencia,
      r.rolname AS rol,
      has_sequence_privilege(r.oid, s.oid, 'USAGE') AS uso,
      has_sequence_privilege(r.oid, s.oid, 'SELECT') AS lectura,
      has_sequence_privilege(r.oid, s.oid, 'UPDATE') AS actualizar
    FROM pg_class s JOIN pg_namespace ns ON ns.oid = s.relnamespace
    JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = s.oid
      AND d.refclassid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
    JOIN objetivos o ON o.oid = d.refobjid
    CROSS JOIN roles_cliente r WHERE s.relkind = 'S'
  ) q), '[]'::jsonb),
  'resumen_perfiles_sin_datos_sensibles', (SELECT jsonb_build_object(
    'total', count(*),
    'activos', count(*) FILTER (WHERE activo IS TRUE),
    'roles_no_previstos', count(*) FILTER (WHERE rol IS NULL OR rol NOT IN ('admin', 'cajero')),
    'usuarios_sin_empleado', count(*) FILTER (WHERE NOT EXISTS (
      SELECT 1 FROM public.empleados_pos e WHERE e.usuario_id = u.id
    ))
  ) FROM public.usuarios u),
  'roles_existentes', (SELECT jsonb_agg(to_jsonb(q)) FROM (
    SELECT rol, activo, count(*) AS cantidad FROM public.usuarios GROUP BY rol, activo
  ) q),
  'resumen_empleados', (SELECT jsonb_build_object(
    'total', count(*), 'demo', count(*) FILTER (WHERE es_demo IS TRUE),
    'sin_usuario', count(*) FILTER (WHERE usuario_id IS NULL),
    'referencias_huerfanas', count(*) FILTER (WHERE usuario_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.usuarios u WHERE u.id = e.usuario_id
    ))
  ) FROM public.empleados_pos e),
  'usuarios_con_varios_empleados', (SELECT count(*) FROM (
    SELECT usuario_id FROM public.empleados_pos WHERE usuario_id IS NOT NULL
    GROUP BY usuario_id HAVING count(*) > 1
  ) duplicados),
  'administradores_autorizados_actualmente', (SELECT jsonb_build_object(
    'total', count(*), 'activos', count(*) FILTER (WHERE activo IS TRUE)
  ) FROM public.inventario_admins),
  'sucursales_disponibles', (SELECT jsonb_agg(jsonb_build_object(
    'id', id, 'empresa_id', empresa_id, 'nombre', nombre, 'activo', activo
  ) ORDER BY id) FROM public.sucursales)
) AS inspeccion_login;

-- IMPORTANTE PARA INTERPRETAR EL RESULTADO:
-- 1. Los privilegios efectivos incluyen concesiones heredadas y PUBLIC.
--    Son privilegios de objeto, NO una demostracion de acceso permitido por RLS.
-- 2. RLS no oculta columnas. SELECT de tabla permite leer password_hash aunque
--    solo se concedan adicionalmente algunas columnas: hay que revisar ambos.
-- 3. SECURITY DEFINER puede omitir RLS por su propietario. Restringir una policy
--    de inventario_admins no garantiza restringir las RPC existentes.
-- 4. pgrst.db_schemas puede ser NULL en SQL Editor; eso NO demuestra que un
--    esquema este expuesto o no. Confirmarlo en la configuracion de la API.
-- 5. El catalogo no revela todas las dependencias de SQL dinamico ni las
--    consultas de aplicaciones de los companeros: confirmar esos consumidores.
-- 6. No asignar auth_uid por nombre/correo. La futura vinculacion manual debe
--    usar un UUID Auth verificado, un usuarios.id elegido expresamente y un
--    empleado real autorizado. No se solicitan aqui UUID ni credenciales.
