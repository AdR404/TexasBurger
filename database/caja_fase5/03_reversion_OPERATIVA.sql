-- Detener operaciones: restaura cierre anterior SIN las protecciones nuevas.
-- Guardar 00 antes de instalar; conserva columnas y auditoria de efectivo.
BEGIN;
SET LOCAL lock_timeout='5s';
DROP FUNCTION public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text);
DROP FUNCTION public.caja_cerrar_turno_verificado(bigint,text,numeric,text);
DROP FUNCTION public.caja_resumen_turno(bigint);
DROP FUNCTION public.caja_conciliar_efectivo_cancelado(integer,text,text,boolean);
ALTER FUNCTION public.caja_cerrar_turno_base_fase5(bigint,numeric,numeric,numeric,integer,numeric,text)
 RENAME TO caja_cerrar_turno;
-- PEGAR AQUI los GRANT originales generados por 00.
-- Guard: cambiar false por true SOLO despues de pegar/revisar esos comandos.
DO $guard$ BEGIN
 IF NOT false THEN RAISE EXCEPTION 'Restaurar ACL originales y confirmar guard antes de revertir'; END IF;
END; $guard$;
NOTIFY pgrst,'reload schema';
COMMIT;
-- No borra conciliaciones ni mueve dinero. Para reinstalar, revisar las columnas
-- conservadas: no reejecutar sus ADD COLUMN/CHECK sin adaptar previamente 01.
