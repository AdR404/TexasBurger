-- Consultas de apoyo para revisar las columnas, restricciones y políticas RLS
-- de las tablas de ventas y personal en Supabase.
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('ventas', 'usuarios', 'sucursales', 'empleados_pos')
order by table_name, ordinal_position;

select c.relname as tabla, con.conname, pg_get_constraintdef(con.oid) as definicion
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('ventas', 'usuarios', 'sucursales', 'empleados_pos');

select tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('ventas', 'usuarios', 'sucursales', 'empleados_pos');

select c.relname as tabla, c.relrowsecurity as rls_activa
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('ventas', 'usuarios', 'sucursales', 'empleados_pos');
