-- Solo lectura. Ejecutar despues de 01 y conservar el JSON completo.
-- No ejecuta INSERT de prueba, ni RPC, ni simula que SQL Editor es Flutter.
SELECT jsonb_build_object(
  'estructura', (SELECT jsonb_build_object(
    'tipo',format_type(a.atttypid,a.atttypmod),'no_nulo',a.attnotnull,
    'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
    'propietario',pg_get_userbyid(c.relowner))
    FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid
    WHERE c.oid='public.producto_ingrediente'::regclass
      AND a.attname='cantidad_requerida' AND NOT a.attisdropped),
  'restricciones', (SELECT jsonb_agg(jsonb_build_object(
    'nombre',conname,'validada',convalidated,'definicion',pg_get_constraintdef(oid)))
    FROM pg_constraint WHERE conrelid='public.producto_ingrediente'::regclass),
  'politicas', (SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p
    WHERE schemaname='public' AND tablename='producto_ingrediente'),
  'permisos', (SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT rolname,
      has_schema_privilege(oid,'public','USAGE') AS uso_esquema,
      has_table_privilege(oid,'public.producto_ingrediente','SELECT') AS leer,
      has_any_column_privilege(oid,'public.producto_ingrediente','INSERT') AS insertar,
      has_any_column_privilege(oid,'public.producto_ingrediente','UPDATE') AS modificar,
      has_table_privilege(oid,'public.producto_ingrediente','DELETE') AS eliminar,
      has_table_privilege(oid,'public.producto_ingrediente','TRUNCATE') AS vaciar
    FROM pg_roles WHERE rolname IN ('anon','authenticated','postgres')
  ) x),
  'numero_recetas',(SELECT count(*) FROM public.producto_ingrediente),
  'cantidades_invalidas',(SELECT count(*) FROM public.producto_ingrediente
    WHERE cantidad_requerida IS NULL OR cantidad_requerida<=0
      OR cantidad_requerida::text IN ('NaN','Infinity','-Infinity')),
  'piezas_fraccionarias',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'producto_id',r.producto_id,'ingrediente_id',r.ingrediente_id,
    'unidad',i.unidad_medida,'cantidad',r.cantidad_requerida)), '[]'::jsonb)
    FROM public.producto_ingrediente r JOIN public.ingredientes i ON i.id=r.ingrediente_id
    WHERE lower(btrim(i.unidad_medida)) IN ('pza','pzas')
      AND r.cantidad_requerida<>trunc(r.cantidad_requerida))
) AS verificacion_recetas;
-- Esperado: numeric(11,3), no_nulo=true, rls=true, force_rls=false.
-- anon/authenticated: insertar/modificar/eliminar/vaciar=false.
-- authenticated: leer=true. postgres conserva todos los permisos como propietario.
-- Cantidades invalidas=0 y piezas_fraccionarias=[]. No se agregan filas en 01.
-- cantidad_requerida se expresa en ingredientes.unidad_medida, sin conversion
-- implicita: kg -> 0.150=150 g; L -> 0.025=25 ml; pzas -> 1=una pieza.
-- Son ejemplos, no se insertan. No inferir equivalencias de reb/porcion.
-- La integridad de piezas depende de la unidad de OTRA tabla. Para mantener esta
-- fase minima no se agrega trigger ni CHECK con consultas externas. El editor
-- debe registrar piezas enteras y ejecutar esta verificacion; la futura RPC
-- debera RECHAZAR recetas/consumos fraccionarios para ingredientes en pzas.
-- No cambiar la unidad de un ingrediente con recetas/lotes sin revisar ambos.
