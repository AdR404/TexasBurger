-- Como postgres, despues de detener llamadas nuevas. NO borra evidencia.
BEGIN;
SET LOCAL lock_timeout='5s';
DROP FUNCTION public.cancelar_venta(integer,text,boolean);
NOTIFY pgrst,'reload schema';
COMMIT;
-- Conservar columnas, permisos por sucursal y movimientos. No reactivar ventas
-- canceladas ni volver a descontar stock. No es reversion completa de estructura.
-- Para reinstalar ejecutar SOLO 02, despues de revisar el estado conservado.
