begin;

update public.empleados_pos
set activo = false
where es_demo = true and activo = true;

commit;

notify pgrst, 'reload schema';