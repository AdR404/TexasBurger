-- Script de actualización de esquema y permisos para Supabase
begin;

-- Usuarios base del sistema
insert into public.usuarios (id, nombre, usuario, password_hash, rol, activo)
values
  (1, 'Administrador', 'admin', 'admin123', 'admin', true),
  (2, 'Cajero', 'caja1', 'caja123', 'cajero', true)
on conflict (id) do nothing;

-- Restricciones de unicidad por nombre para categorías y productos
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.categorias'::regclass
      and contype = 'u'
  ) then
    alter table public.categorias
      add constraint categorias_nombre_key unique (nombre);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.productos'::regclass
      and contype = 'u'
  ) then
    alter table public.productos
      add constraint productos_nombre_key unique (nombre);
  end if;
end $$;

insert into public.categorias (nombre)
values ('Hamburguesas'), ('Complementos'), ('Bebidas'), ('Promociones')
on conflict (nombre) do nothing;

-- Tablas de sucursales y personal de punto de venta
create table if not exists public.sucursales (
  id text primary key,
  empresa_id text not null check (empresa_id = 'texas_burger'),
  nombre text not null,
  activo boolean not null default true
);

create table if not exists public.empleados_pos (
  id text primary key,
  nombre text not null,
  es_demo boolean not null default true,
  activo boolean not null default true,
  usuario_id integer unique references public.usuarios(id)
);

insert into public.sucursales (id, empresa_id, nombre) values
  ('perimetral_sur', 'texas_burger', 'Perimetral Sur'),
  ('norte', 'texas_burger', 'Norte')
on conflict (id) do nothing;

insert into public.empleados_pos (id, nombre, es_demo) values
  ('demo_ana_torres', 'Ana Torres', true),
  ('demo_luis_garcia', 'Luis García', true),
  ('demo_sofia_reyes', 'Sofía Reyes', true)
on conflict (id) do nothing;

-- Columnas adicionales en ventas para sucursal, cajero y desglose de cobro
alter table public.ventas
  add column if not exists empresa_id text check (empresa_id = 'texas_burger'),
  add column if not exists empresa_nombre text,
  add column if not exists sucursal_id text references public.sucursales(id),
  add column if not exists sucursal_nombre text,
  add column if not exists empleado_pos_id text references public.empleados_pos(id),
  add column if not exists empleado_nombre text,
  add column if not exists subtotal decimal(10,2),
  add column if not exists descuento decimal(10,2) default 0,
  add column if not exists codigo_descuento text,
  add column if not exists iva decimal(10,2),
  add column if not exists tasa_iva decimal(5,4),
  add column if not exists iva_incluido boolean;

create index if not exists ventas_sucursal_id_idx on public.ventas (sucursal_id);
create index if not exists ventas_empleado_pos_id_idx on public.ventas (empleado_pos_id);

-- Tablas complementarias del módulo administrativo
create table if not exists public.corte_caja (
  id serial primary key,
  usuario_id int references public.usuarios(id),
  fecha date not null default current_date,
  total_ventas decimal(10,2) not null default 0
);

create table if not exists public.eventos (
  id serial primary key,
  usuario_id int references public.usuarios(id),
  nombre_cliente varchar(120) not null,
  fecha_evento date not null,
  costo_total decimal(10,2) not null
);

create table if not exists public.proveedores (
  id serial primary key,
  nombre_empresa varchar(120) not null,
  contacto varchar(100),
  telefono varchar(20),
  activo boolean not null default true
);

create table if not exists public.compras (
  id serial primary key,
  proveedor_id int references public.proveedores(id),
  usuario_id int references public.usuarios(id),
  fecha_compra date not null default current_date,
  total_compra decimal(10,2) not null default 0,
  estado varchar(20) not null default 'pendiente'
);

create table if not exists public.detalle_compra (
  id serial primary key,
  compra_id int not null references public.compras(id) on delete cascade,
  ingrediente_id int not null references public.ingredientes(id),
  cantidad decimal(10,2) not null,
  precio_unitario decimal(10,2) not null,
  fecha_caducidad date
);

-- Permisos de acceso para el cliente de la app
grant usage on schema public to anon, authenticated;
grant select, insert, update on all tables in schema public to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;

-- Proteger la tabla de usuarios y evitar borrados o ediciones de ventas desde cliente público
revoke all on table public.usuarios from anon, authenticated;
revoke delete on all tables in schema public from anon, authenticated;
revoke update on table public.ventas, public.detalle_venta from anon, authenticated;

alter table public.sucursales enable row level security;
alter table public.empleados_pos enable row level security;

drop policy if exists "Lectura publica sucursales" on public.sucursales;
create policy "Lectura publica sucursales"
  on public.sucursales for select
  to anon, authenticated
  using (true);

drop policy if exists "Lectura publica empleados_pos" on public.empleados_pos;
create policy "Lectura publica empleados_pos"
  on public.empleados_pos for select
  to anon, authenticated
  using (true);

notify pgrst, 'reload schema';

commit;
