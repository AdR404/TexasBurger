-- FASE 2: ejecutar manualmente; solo lectura, no invoca RPC de negocio.
-- Bloque A devuelve un JSON. Guardar ese resultado antes de ejecutar B.
-- No lee credenciales ni filas de auth.users/usuarios. Las definiciones de
-- funciones deben revisarse antes de compartir por si contienen secretos literales.
WITH objetivos AS (
  SELECT c.oid, n.nspname AS esquema, c.relname AS tabla,
         c.relrowsecurity AS rls, c.relforcerowsecurity AS rls_forzado,
         pg_get_userbyid(c.relowner) AS propietario, c.relacl
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p')
    AND (c.relname IN ('productos','ingredientes','producto_ingrediente',
      'inventario_lotes','inventario_movimientos','ventas','detalle_venta',
      'caja_turnos','caja_movimientos','usuarios','empleados_pos','sucursales',
      'inventario_admins')
      OR c.relname ~* '(receta|modificador|componente|consumo|cancel|reintegro)')
), roles_cliente AS (
  SELECT oid,rolname FROM pg_roles
  WHERE rolname IN ('anon','authenticated','service_role')
), funciones AS (
  SELECT p.oid,n.nspname AS esquema,p.proname AS nombre,
    pg_get_function_identity_arguments(p.oid) AS argumentos,
    pg_get_userbyid(p.proowner) AS propietario,p.prosecdef AS security_definer,
    p.proconfig,p.proacl,pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE p.prokind='f' AND n.nspname IN ('public','inventario_backend')
    AND (p.proname ~* '(inventario|registrar_baja|registrar_lote|venta|receta|consumo|caja|login_|cancel|reintegro)'
      OR p.prosrc ~* '(producto_ingrediente|inventario_lotes|inventario_movimientos)')
)
SELECT jsonb_build_object(
  'servidor',jsonb_build_object('version',current_setting('server_version'),
    'zona_sesion',current_setting('TimeZone')),
  'tablas',(SELECT jsonb_agg(to_jsonb(o) ORDER BY tabla) FROM objetivos o),
  'columnas',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT o.tabla,a.attname AS columna,format_type(a.atttypid,a.atttypmod) AS tipo,
      a.attnotnull AS no_nulo,a.attidentity,a.attgenerated,a.attacl,
      CASE WHEN a.attname='password_hash' THEN NULL
        ELSE pg_get_expr(d.adbin,d.adrelid) END AS predeterminado
    FROM objetivos o JOIN pg_attribute a ON a.attrelid=o.oid
    LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    WHERE a.attnum>0 AND NOT a.attisdropped ORDER BY o.tabla,a.attnum
  ) x),
  'restricciones',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT k.conrelid::regclass::text AS tabla,k.conname,k.contype,k.convalidated,
      pg_get_constraintdef(k.oid) AS definicion
    FROM pg_constraint k WHERE k.conrelid IN (SELECT oid FROM objetivos)
      OR k.confrelid IN (SELECT oid FROM objetivos)
  ) x),
  'indices',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT o.tabla,i.indisunique,i.indisvalid,pg_get_indexdef(i.indexrelid) AS definicion
    FROM objetivos o JOIN pg_index i ON i.indrelid=o.oid
  ) x),
  'triggers',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT o.tabla,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) AS definicion,
      pg_get_functiondef(t.tgfoid) AS funcion
    FROM objetivos o JOIN pg_trigger t ON t.tgrelid=o.oid WHERE NOT t.tgisinternal
  ) x),
  'politicas',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p
    WHERE p.schemaname='public' AND p.tablename IN (SELECT tabla FROM objetivos)),
  'permisos_tablas',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT o.tabla,r.rolname,
      has_table_privilege(r.oid,o.oid,'SELECT') AS lectura_tabla,
      has_any_column_privilege(r.oid,o.oid,'SELECT') AS alguna_lectura,
      has_table_privilege(r.oid,o.oid,'INSERT') AS insertar_tabla,
      has_any_column_privilege(r.oid,o.oid,'INSERT') AS alguna_insercion,
      has_any_column_privilege(r.oid,o.oid,'UPDATE') AS alguna_actualizacion,
      has_table_privilege(r.oid,o.oid,'DELETE') AS eliminar,
      has_table_privilege(r.oid,o.oid,'TRUNCATE') AS truncar
    FROM objetivos o CROSS JOIN roles_cliente r
  ) x),
  'secuencias',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT n.nspname AS esquema,c.relname AS secuencia,r.rolname,
      has_sequence_privilege(r.oid,c.oid,'USAGE') AS uso,
      has_sequence_privilege(r.oid,c.oid,'UPDATE') AS actualizar
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN roles_cliente r WHERE c.relkind='S' AND n.nspname='public'
  ) x),
  'funciones',(SELECT jsonb_agg(to_jsonb(f)) FROM funciones f),
  'ejecucion',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT f.esquema,f.nombre,f.argumentos,r.rolname,
      has_function_privilege(r.oid,f.oid,'EXECUTE') AS ejecutar,
      has_schema_privilege(r.oid,f.esquema,'USAGE') AS uso_esquema
    FROM funciones f CROSS JOIN roles_cliente r
  ) x)
) AS inspeccion_recetas;

-- BLOQUE B: ejecutar por separado, despues de confirmar columnas con A.
-- Datos de catalogo, cantidades y resumen; no cambia ni completa recetas.
SELECT jsonb_build_object(
  'productos',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT p.id,p.nombre,p.activo,count(pi.ingrediente_id) AS lineas_receta
    FROM public.productos p LEFT JOIN public.producto_ingrediente pi
      ON pi.producto_id=p.id GROUP BY p.id,p.nombre,p.activo ORDER BY p.id
  ) x),
  'recetas',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT producto_id,ingrediente_id,cantidad_requerida
    FROM public.producto_ingrediente ORDER BY producto_id,ingrediente_id
  ) x),
  'ingredientes',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT id,nombre,unidad_medida FROM public.ingredientes ORDER BY id
  ) x),
  'lotes_por_unidad',(SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT sucursal_id,ingrediente_id,unidad_medida,count(*) AS lotes,
      sum(cantidad_disponible) AS saldo_total,
      sum(CASE WHEN fecha_caducidad < (now() AT TIME ZONE 'America/Monterrey')::date
        THEN cantidad_disponible ELSE 0 END) AS saldo_fecha_pasada,
      sum(CASE WHEN fecha_caducidad = (now() AT TIME ZONE 'America/Monterrey')::date
        THEN cantidad_disponible ELSE 0 END) AS saldo_caduca_hoy
    FROM public.inventario_lotes GROUP BY sucursal_id,ingrediente_id,unidad_medida
  ) x)
) AS catalogo_recetas;
-- Los privilegios de objeto no prueban lo permitido por RLS con un JWT concreto.
-- Ausencia de recetas no autoriza consumo cero. No ejecutar schema.sql ni 002
-- como sustituto de esta inspeccion. Esta consulta no requiere reversion.
