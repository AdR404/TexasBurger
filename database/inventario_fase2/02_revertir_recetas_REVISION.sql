-- REVISION LOCAL. Solo para revertir 01, como postgres.
-- Pegar en v_respaldo el OBJETO JSON generado por el bloque A de 01 antes de migrar.
-- NULL bloquea la reversion. No adivinar permisos originales.
-- Restituye tambien los permisos amplios anteriores: implica reabrir escritura
-- a los roles que la tenian. Revisar esa decision antes de ejecutar.
BEGIN;
SET LOCAL lock_timeout = '5s';
LOCK TABLE public.producto_ingrediente IN ACCESS EXCLUSIVE MODE;
DO $revertir$
DECLARE
  v_respaldo jsonb := NULL; -- Sustituir por $json${...}$json$::jsonb
  p record;
BEGIN
  IF current_user <> 'postgres' OR v_respaldo IS NULL THEN
    RAISE EXCEPTION 'Se requiere postgres y el respaldo original de 01'; END IF;
  IF v_respaldo->>'tabla' IS DISTINCT FROM 'public.producto_ingrediente'
    OR (v_respaldo->>'oid')::bigint IS DISTINCT FROM 'public.producto_ingrediente'::regclass::oid::bigint
    OR v_respaldo->>'tipo' IS DISTINCT FROM 'numeric(10,2)'
    OR v_respaldo->>'propietario' IS DISTINCT FROM 'postgres'
    OR (v_respaldo->>'rls')::boolean IS DISTINCT FROM false
    OR (v_respaldo->>'force_rls')::boolean IS DISTINCT FROM false
    OR (v_respaldo->>'no_nulo')::boolean IS DISTINCT FROM false
    OR jsonb_typeof(v_respaldo->'permisos') IS DISTINCT FROM 'array'
  THEN RAISE EXCEPTION 'El respaldo no corresponde al estado previo esperado'; END IF;
  IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.producto_ingrediente'::regclass
      AND attname='cantidad_requerida' AND attnotnull AND format_type(atttypid,atttypmod)='numeric(11,3)')
    OR NOT EXISTS (SELECT FROM pg_class WHERE oid='public.producto_ingrediente'::regclass
      AND relowner='postgres'::regrole AND relrowsecurity AND NOT relforcerowsecurity)
    OR (SELECT count(*) FROM pg_policy WHERE polrelid='public.producto_ingrediente'::regclass)<>1
    OR NOT EXISTS (SELECT FROM pg_policy WHERE polrelid='public.producto_ingrediente'::regclass
      AND polname='fase2_recetas_lectura')
  THEN RAISE EXCEPTION 'El estado posterior cambio; revisar antes de revertir'; END IF;
  -- Evitar redondear recetas nuevas, p.ej. 0.025 -> 0.03. No perder informacion.
  IF EXISTS (SELECT FROM public.producto_ingrediente
    WHERE cantidad_requerida<>round(cantidad_requerida,2)) THEN
    RAISE EXCEPTION 'Existen cantidades con tercer decimal; no se puede volver a 10,2 sin perder precision. Conservar estructura y revisar';
  END IF;
  ALTER TABLE public.producto_ingrediente
    DROP CONSTRAINT fase2_receta_cantidad_positiva,
    ALTER COLUMN cantidad_requerida DROP NOT NULL,
    ALTER COLUMN cantidad_requerida TYPE numeric(10,2);
  DROP POLICY fase2_recetas_lectura ON public.producto_ingrediente;
  ALTER TABLE public.producto_ingrediente DISABLE ROW LEVEL SECURITY;
  REVOKE ALL PRIVILEGES ON TABLE public.producto_ingrediente FROM PUBLIC, anon, authenticated;
  FOR p IN SELECT * FROM jsonb_to_recordset(v_respaldo->'permisos')
    AS x(rol text, privilegio text, grantable boolean)
  LOOP
    IF p.rol IS NULL OR p.rol NOT IN ('PUBLIC','anon','authenticated')
      OR p.privilegio IS NULL OR p.privilegio NOT IN
        ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
      OR p.grantable IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'Permiso del respaldo no esperado'; END IF;
    EXECUTE format('GRANT %s ON TABLE public.producto_ingrediente TO %s',
      p.privilegio, CASE WHEN p.rol='PUBLIC' THEN 'PUBLIC' ELSE quote_ident(p.rol) END);
  END LOOP;
END;
$revertir$;
COMMIT;
