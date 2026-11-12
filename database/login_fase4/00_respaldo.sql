-- SOLO LECTURA, antes de 01 y 02, como postgres en el proyecto correcto.
-- Exportar los DOS textos completos como archivos SQL y conservar fuera del cliente.
-- Confirmar cinco CREATE OR REPLACE en revertir_01. Guardar tambien respaldo de esquema.
-- Ejecutar la reversion unicamente en la misma ventana, sin cambios concurrentes de ACL/DDL:
-- si solo se aplico 01, revertir_01; si ambos, revertir_02 y luego revertir_01.
-- Restituye los permisos ANTERIORES (incluidos los amplios). No revierte datos ni secuencias.
WITH objetos AS (
  SELECT c.*, CASE WHEN c.relkind='S' THEN 'SEQUENCE' ELSE 'TABLE' END AS tipo
  FROM pg_class c WHERE c.relnamespace='public'::regnamespace
    AND c.relname IN ('ventas', 'detalle_venta', 'productos', 'categorias', 'ingredientes', 'empleados_pos', 'sucursales', 'ventas_id_seq', 'detalle_venta_id_seq', 'productos_id_seq', 'categorias_id_seq', 'ingredientes_id_seq', 'usuarios_id_seq', 'corte_caja', 'corte_caja_id_seq')
), restaurar AS (
  SELECT 1 orden, format('REVOKE ALL PRIVILEGES ON %s public.%I FROM PUBLIC, anon, authenticated;',tipo,relname) ddl FROM objetos
  UNION ALL SELECT 2, format('GRANT %s ON %s public.%I TO %s%s;',x.privilege_type,o.tipo,o.relname,
    CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(x.grantee)) END,
    CASE WHEN x.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END)
  FROM objetos o CROSS JOIN LATERAL aclexplode(o.relacl) x
  WHERE x.grantee IN (0,'authenticated'::regrole,'anon'::regrole)
  UNION ALL SELECT 3, format('ALTER TABLE public.%I %s ROW LEVEL SECURITY;',relname,
    CASE WHEN relrowsecurity THEN 'ENABLE' ELSE 'DISABLE' END) FROM objetos WHERE tipo='TABLE'
), funciones AS (
  SELECT pg_get_functiondef(firma::regprocedure) AS ddl FROM unnest(ARRAY['inventario_backend.registrar_lote_impl(integer,text,text,text,numeric,numeric,date,date,boolean)', 'inventario_backend.registrar_baja_impl(bigint,text,numeric,text)', 'public.caja_abrir_turno(text,text,text,numeric)', 'public.caja_registrar_movimiento(bigint,text,numeric,text)', 'public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)']) firma
)
SELECT concat_ws(E'\n','BEGIN;', 'SET LOCAL lock_timeout = ''5s'';',
  (SELECT string_agg(format('DROP POLICY fase4_admin ON public.%I;',t),E'\n') FROM unnest(ARRAY['inventario_admins', 'inventario_lotes', 'inventario_movimientos', 'caja_turnos', 'caja_movimientos']) t),
  (SELECT string_agg(ddl || ';',E'\n') FROM funciones),
  'NOTIFY pgrst, ''reload schema'';', 'COMMIT;') AS revertir_01,
  concat_ws(E'\n','BEGIN;', 'SET LOCAL lock_timeout = ''5s'';',
  (SELECT string_agg(format('DROP POLICY fase4_catalogo ON public.%I;',t),E'\n')
     FROM unnest(ARRAY['productos', 'categorias', 'ingredientes', 'empleados_pos', 'sucursales']) t),
  'DROP POLICY fase4_alta ON public.ventas;', 'DROP POLICY fase4_alta ON public.detalle_venta;',
  'DROP POLICY fase4_historial ON public.ventas;', 'DROP POLICY fase4_historial ON public.detalle_venta;',
  'REVOKE INSERT (usuario_id,fecha_hora,total,metodo_pago,subtotal,descuento,codigo_descuento,iva,tasa_iva,iva_incluido,empresa_id,empresa_nombre,sucursal_id,sucursal_nombre,empleado_pos_id,empleado_nombre) ON public.ventas FROM authenticated;',
  'REVOKE INSERT (venta_id,producto_id,cantidad,precio_unitario) ON public.detalle_venta FROM authenticated;',
  (SELECT string_agg(ddl,E'\n' ORDER BY orden, ddl) FROM restaurar),
  'DROP FUNCTION public.login_contexto_operativo();', 'NOTIFY pgrst, ''reload schema'';', 'COMMIT;') AS revertir_02;
