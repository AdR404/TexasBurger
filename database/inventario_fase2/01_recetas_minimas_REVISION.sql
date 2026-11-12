-- REVISION LOCAL. No ejecutar automaticamente.
-- Solo public.producto_ingrediente. Ejecutar como postgres en SQL Editor.
-- A y B se ejecutan POR SEPARADO. Guardar primero el JSON de A para 02.
-- No volver a ejecutar A despues de migrar: perderia el respaldo original.

-- A. RESPALDO DE SOLO LECTURA. Copiar el objeto respaldo_recetas completo.
SELECT jsonb_build_object(
  'tabla', 'public.producto_ingrediente',
  'oid', c.oid::bigint,
  'rls', c.relrowsecurity,
  'force_rls', c.relforcerowsecurity,
  'propietario', pg_get_userbyid(c.relowner),
  'tipo', format_type(a.atttypid, a.atttypmod),
  'no_nulo', a.attnotnull,
  'permisos', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'rol', CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
      'privilegio', x.privilege_type,
      'grantable', x.is_grantable
    ))
    FROM aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) x
    WHERE x.grantee=0 OR x.grantee IN (
      SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated')
    )
  ), '[]'::jsonb)
) AS respaldo_recetas
FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid
WHERE c.oid='public.producto_ingrediente'::regclass
  AND a.attname='cantidad_requerida' AND NOT a.attisdropped;

-- B. MIGRACION. Ejecutar solo despues de guardar el respaldo de A.
BEGIN;
SET LOCAL lock_timeout = '5s';
LOCK TABLE public.producto_ingrediente IN ACCESS EXCLUSIVE MODE;
DO $pre$
BEGIN
  IF current_user <> 'postgres' OR NOT EXISTS (
    SELECT FROM pg_class c WHERE c.oid='public.producto_ingrediente'::regclass
      AND c.relowner='postgres'::regrole AND NOT c.relrowsecurity
      AND NOT c.relforcerowsecurity
  ) THEN RAISE EXCEPTION 'Se requiere postgres, propietario postgres y RLS originalmente desactivado'; END IF;
  IF NOT EXISTS (
    SELECT FROM pg_attribute WHERE attrelid='public.producto_ingrediente'::regclass
      AND attname='cantidad_requerida' AND NOT attisdropped AND NOT attnotnull
      AND format_type(atttypid,atttypmod)='numeric(10,2)'
  ) THEN RAISE EXCEPTION 'La columna difiere de numeric(10,2) NULL confirmado; revisar antes de continuar'; END IF;
  IF EXISTS (SELECT FROM pg_policy WHERE polrelid='public.producto_ingrediente'::regclass)
    OR EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.producto_ingrediente'::regclass
      AND attacl IS NOT NULL AND cardinality(attacl)>0)
    OR EXISTS (SELECT FROM pg_constraint WHERE conrelid='public.producto_ingrediente'::regclass
      AND conname='fase2_receta_cantidad_positiva')
  THEN RAISE EXCEPTION 'Hay politicas, permisos de columna o restriccion previa; revisar sin sobrescribir'; END IF;
  IF EXISTS (
    SELECT FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) x
    WHERE c.oid='public.producto_ingrediente'::regclass AND x.is_grantable
      AND (x.grantee=0 OR x.grantee IN (
        SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated')
      ))
  ) THEN RAISE EXCEPTION 'Hay permisos delegables; revisar dependencias antes de revocar'; END IF;
  IF EXISTS (SELECT FROM public.producto_ingrediente
    WHERE cantidad_requerida IS NULL OR cantidad_requerida<=0
       OR cantidad_requerida::text IN ('NaN','Infinity','-Infinity'))
  THEN RAISE EXCEPTION 'Hay cantidades invalidas; no se corrigen ni eliminan automaticamente'; END IF;
END;
$pre$;

-- 11,3 mantiene los ocho digitos enteros de 10,2 y agrega un decimal.
ALTER TABLE public.producto_ingrediente
  ALTER COLUMN cantidad_requerida TYPE numeric(11,3),
  ALTER COLUMN cantidad_requerida SET NOT NULL,
  ADD CONSTRAINT fase2_receta_cantidad_positiva
    CHECK (cantidad_requerida>0 AND cantidad_requerida<100000000);

-- RLS no protege TRUNCATE: tambien revocar privilegios de objeto.
-- PUBLIC se incluye para impedir que el permiso se herede de ese grupo.
REVOKE ALL PRIVILEGES ON TABLE public.producto_ingrediente FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.producto_ingrediente TO authenticated;
ALTER TABLE public.producto_ingrediente ENABLE ROW LEVEL SECURITY;
CREATE POLICY fase2_recetas_lectura ON public.producto_ingrediente
  FOR SELECT TO authenticated USING (true);

DO $post$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF has_any_column_privilege(r,'public.producto_ingrediente','INSERT')
      OR has_any_column_privilege(r,'public.producto_ingrediente','UPDATE')
      OR has_table_privilege(r,'public.producto_ingrediente','DELETE,TRUNCATE,TRIGGER,REFERENCES')
      OR EXISTS (SELECT FROM pg_roles WHERE rolname=r AND (rolsuper OR rolbypassrls))
    THEN RAISE EXCEPTION 'Persisten privilegios heredados no previstos para %; rollback total',r; END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated','public.producto_ingrediente','SELECT') THEN
    RAISE EXCEPTION 'Falta lectura authenticated'; END IF;
END;
$post$;
COMMIT;
-- No FORCE RLS: postgres propietario conserva administracion desde SQL Editor.
-- Una futura RPC SECURITY DEFINER de postgres podra leer recetas. Una invoker
-- authenticated tambien tendra SELECT, sujeto al USAGE del esquema existente.
-- No se cambian FK, otras tablas, secuencias, funciones ni permisos globales.
-- Piezas enteras: ver 03. La futura RPC debe rechazar consumo fraccionario en pzas.
