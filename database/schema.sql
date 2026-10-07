-- Texas Burger - Base de datos
-- Modulo cobrador: categorias, productos, ventas, detalle_venta
-- Modulo admin: usuarios, ingredientes, producto_ingrediente, corte_caja,
--               eventos, proveedores, compras, detalle_compra

create table categorias (
  id serial primary key,
  nombre varchar(100) not null unique
);

create table usuarios (
  id serial primary key,
  nombre varchar(100) not null,
  usuario varchar(50) not null unique,
  password_hash varchar(255) not null,
  rol varchar(20) not null default 'cajero',
  activo boolean not null default true
);

create table productos (
  id serial primary key,
  categoria_id int references categorias(id),
  nombre varchar(120) not null unique,
  descripcion text,
  precio decimal(10,2) not null,
  activo boolean not null default true
);

create table ventas (
  id serial primary key,
  usuario_id int references usuarios(id),
  fecha_hora timestamp not null default now(),
  total decimal(10,2) not null,
  metodo_pago varchar(30) not null
);

create table detalle_venta (
  id serial primary key,
  venta_id int not null references ventas(id) on delete cascade,
  producto_id int not null references productos(id),
  cantidad int not null,
  precio_unitario decimal(10,2) not null
);

create table ingredientes (
  id serial primary key,
  nombre varchar(100) not null,
  stock_actual decimal(10,2) not null default 0,
  unidad_medida varchar(20) not null,
  stock_minimo decimal(10,2) not null default 0
);

create table producto_ingrediente (
  producto_id int references productos(id) on delete cascade,
  ingrediente_id int references ingredientes(id) on delete cascade,
  cantidad_requerida decimal(10,2) not null,
  primary key (producto_id, ingrediente_id)
);

create table corte_caja (
  id serial primary key,
  usuario_id int references usuarios(id),
  fecha date not null default current_date,
  total_ventas decimal(10,2) not null default 0
);

create table eventos (
  id serial primary key,
  usuario_id int references usuarios(id),
  nombre_cliente varchar(120) not null,
  fecha_evento date not null,
  costo_total decimal(10,2) not null
);

create table proveedores (
  id serial primary key,
  nombre_empresa varchar(120) not null,
  contacto varchar(100),
  telefono varchar(20),
  activo boolean not null default true
);

create table compras (
  id serial primary key,
  proveedor_id int references proveedores(id),
  usuario_id int references usuarios(id),
  fecha_compra date not null default current_date,
  total_compra decimal(10,2) not null default 0,
  estado varchar(20) not null default 'pendiente'
);

create table detalle_compra (
  id serial primary key,
  compra_id int not null references compras(id) on delete cascade,
  ingrediente_id int not null references ingredientes(id),
  cantidad decimal(10,2) not null,
  precio_unitario decimal(10,2) not null,
  fecha_caducidad date
);

-- Datos iniciales
insert into usuarios (nombre, usuario, password_hash, rol) values
  ('Administrador', 'admin', 'admin123', 'admin'),
  ('Cajero', 'caja1', 'caja123', 'cajero');

insert into categorias (nombre) values
  ('Hamburguesas'), ('Complementos'), ('Bebidas'), ('Promociones');

insert into ingredientes (nombre, stock_actual, unidad_medida, stock_minimo) values
  ('Pan', 100, 'pza', 20),
  ('Carne de res', 80, 'pza', 15),
  ('Queso amarillo', 120, 'reb', 25),
  ('Tocino', 3, 'kg', 1),
  ('Papa', 15, 'kg', 5);

insert into proveedores (nombre_empresa, contacto, telefono) values
  ('Carnes del Norte', 'Luis Garza', '8112345678'),
  ('Panificadora La Espiga', 'Ana Ruiz', '8187654321');
