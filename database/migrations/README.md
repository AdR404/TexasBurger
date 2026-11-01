# Guía de Base de Datos y Migraciones (Supabase)

Este directorio contiene los scripts SQL para configurar y actualizar el esquema de PostgreSQL en Supabase.

## Estructura de archivos

- `../schema.sql`: Esquema inicial del proyecto (creación de tablas desde cero).
- `000_inspect_ticket_schema.sql`: Consultas de verificación para revisar columnas, llaves foráneas y políticas RLS en las tablas principales.
- `001_sale_staff_context.sql`: Creación de tablas `sucursales` y `empleados_pos`, más las columnas de contexto en `ventas`.
- `002_fix_and_complete_supabase.sql`: Script consolidado (idempotente) para actualizar una base de datos existente en Supabase con todas las tablas, restricciones `UNIQUE`, columnas de tickets/IVA y permisos de API.

## Funcionamiento del contexto de venta y personal

- Cada venta guarda un `saleContext` con el identificador y nombre de la empresa, sucursal y empleado que atendió.
- Catálogo local en `lib/data/staff_catalog.dart`:
  - Sucursales: `perimetral_sur` (Perimetral Sur) y `norte` (Norte).
  - Personal: `demo_ana_torres`, `demo_luis_garcia` y `demo_sofia_reyes`.
- Al abrir turno en caja, la sucursal seleccionada queda fija hasta realizar el corte de caja, mientras que el cajero activo puede cambiarse entre ventas.

## Relación entre el modelo de la app y la tabla `ventas`

| Campo en `Venta` (Flutter) | Columna en `public.ventas` (Supabase) |
|---|---|
| `saleContext.companyId` | `empresa_id` |
| `saleContext.companyName` | `empresa_nombre` |
| `saleContext.branchId` | `sucursal_id` |
| `saleContext.branchName` | `sucursal_nombre` |
| `saleContext.employeeId` | `empleado_pos_id` |
| `saleContext.employeeName` | `empleado_nombre` |
| `subtotal` | `subtotal` |
| `discount` | `descuento` |
| `discountCode` | `codigo_descuento` |
| `iva` | `iva` |
| `ivaRate` | `tasa_iva` |
| `ivaIncluded` | `iva_incluido` |
| `timestamp` | `fecha_hora` |

## Control de sincronización desde la aplicación

En `lib/services/db_service.dart` (`DbService`), la aplicación cuenta con un interruptor (`isSyncEnabled`) administrable desde la pantalla de **Ajustes** (modo Administrador):
- **Sincronización activa:** Cada venta registrada se guarda localmente y se envía a `ventas` y `detalle_venta` en Supabase.
- **Base de datos frenada (modo local):** Las ventas se almacenan únicamente en el dispositivo (`SharedPreferences`) sin realizar peticiones de red hasta reactivar el interruptor.
