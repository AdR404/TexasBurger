-- Migración para agregar catálogo de sucursales, empleados de caja
-- y campos de referencia en la tabla de ventas.
begin;

create table public.sucursales (
  id text primary key,
  empresa_id text not null check (empresa_id = 'texas_burger'),
  nombre text not null,
  activo boolean not null default true
);

-- Catálogo de personal operativo para el punto de venta.
create table public.empleados_pos (
  id text primary key,
  nombre text not null,
  es_demo boolean not null default true,
  activo boolean not null default true,
  usuario_id integer unique references public.usuarios(id)
);

insert into public.sucursales (id, empresa_id, nombre) values
  ('perimetral_sur', 'texas_burger', 'Perimetral Sur'),
  ('norte', 'texas_burger', 'Norte');

insert into public.empleados_pos (id, nombre, es_demo) values
  ('demo_ana_torres', 'Ana Torres', true),
  ('demo_luis_garcia', 'Luis García', true),
  ('demo_sofia_reyes', 'Sofía Reyes', true);

-- Se permiten nulos para no afectar las ventas registradas anteriormente.
alter table public.ventas
  add column empresa_id text check (empresa_id = 'texas_burger'),
  add column empresa_nombre text,
  add column sucursal_id text references public.sucursales(id),
  add column sucursal_nombre text,
  add column empleado_pos_id text references public.empleados_pos(id),
  add column empleado_nombre text;

create index ventas_sucursal_id_idx on public.ventas (sucursal_id);
create index ventas_empleado_pos_id_idx on public.ventas (empleado_pos_id);

alter table public.sucursales enable row level security;
alter table public.empleados_pos enable row level security;

commit;
