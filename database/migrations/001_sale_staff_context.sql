-- PROPUESTA ADITIVA: NO EJECUTADA.
-- Aplicar una sola vez tras revisar 000_inspect_ticket_schema.sql y README.md.
-- Requiere public.ventas y public.usuarios(id integer PK), como en schema.sql.
-- Si hay objetos/columnas homónimos, detenerse y reconciliar el esquema real.
-- No se utiliza IF NOT EXISTS para ocultar diferencias con la BD desplegada.
begin;

create table public.sucursales (
  id text primary key,
  empresa_id text not null check (empresa_id = 'texas_burger'),
  nombre text not null,
  activo boolean not null default true
);

-- El personal no necesita credenciales para atender una venta.
-- usuario_id queda NULL hasta verificar una correspondencia con un usuario real.
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

-- NULL para ventas históricas y para clientes que aún envían el formato antiguo.
-- Las copias de nombres permiten conservar el contenido original del ticket.
alter table public.ventas
  add column empresa_id text check (empresa_id = 'texas_burger'),
  add column empresa_nombre text,
  add column sucursal_id text references public.sucursales(id),
  add column sucursal_nombre text,
  add column empleado_pos_id text references public.empleados_pos(id),
  add column empleado_nombre text;

create index ventas_sucursal_id_idx on public.ventas (sucursal_id);
create index ventas_empleado_pos_id_idx on public.ventas (empleado_pos_id);

-- Revisar/diseñar políticas antes de integrar los nuevos recursos en el cliente.
-- No se cambian las políticas ni los permisos de las tablas existentes.
alter table public.sucursales enable row level security;
alter table public.empleados_pos enable row level security;

-- fecha_hora existente se conserva. No se agrega una segunda fecha/hora.
-- No se rellenan ventas históricas ni se modifica ventas.usuario_id.
commit;
