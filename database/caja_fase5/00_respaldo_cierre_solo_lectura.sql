-- ANTES de 01, guardar ambos resultados. No sobrescribir respaldo tras instalar.
SELECT pg_get_functiondef('public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)'::regprocedure) ddl_original;
-- Comandos de restauracion de ACL para pegar en 03, dentro de su transaccion.
SELECT string_agg(format('GRANT EXECUTE ON FUNCTION public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text) TO %s%s;',
 CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END,
 CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END),E'\n') restaurar_acl_original
FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
WHERE p.oid='public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)'::regprocedure
 AND a.grantee<>p.proowner;
