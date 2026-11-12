-- Reversion OPERATIVA, como postgres. No borra ventas, recetas, vinculos ni saldos.
-- Primero detener llamadas a la nueva RPC. No activar/desactivar Flutter aqui.
BEGIN;
SET LOCAL lock_timeout = '5s';
DROP FUNCTION public.registrar_venta_con_consumo(uuid,jsonb);
NOTIFY pgrst, 'reload schema';
COMMIT;
-- Se conservan columnas, indices y restricciones aditivas de 01 para no perder
-- trazabilidad de ventas ya consumidas. El escritor antiguo sigue compatible.
-- No devolver stock automaticamente: cancelar/reponer es otra operacion futura.
-- Para reactivar: revisar estructura conservada y ejecutar SOLO 02.
-- No volver a ejecutar 01: falla ante columnas existentes deliberadamente.
