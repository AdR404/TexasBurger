-- Como postgres; no llama a cierre ni modifica filas.
SELECT p.oid::regprocedure firma,p.proowner::regrole,p.prosecdef,p.proconfig,p.proacl
FROM pg_proc p WHERE p.oid IN ('public.caja_resumen_turno(bigint)'::regprocedure,
 'public.caja_cerrar_turno_verificado(bigint,text,numeric,text)'::regprocedure,
 'public.caja_cerrar_turno(bigint,numeric,numeric,numeric,integer,numeric,text)'::regprocedure);
SELECT rolname,has_function_privilege(oid,'public.caja_resumen_turno(bigint)','EXECUTE') resumen,
 has_function_privilege(oid,'public.caja_cerrar_turno_verificado(bigint,text,numeric,text)','EXECUTE') cierre
FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role');
SELECT rolname,
 has_function_privilege(oid,'public.caja_cerrar_turno_base_fase5(bigint,numeric,numeric,numeric,integer,numeric,text)','EXECUTE') eludir_control,
 has_function_privilege(oid,'public.caja_conciliar_efectivo_cancelado(integer,text,text,boolean)','EXECUTE') conciliar,
 has_column_privilege(oid,'public.ventas','efectivo_cancelacion_estado','INSERT,UPDATE') falsificar_conciliacion
FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role');
-- base=false para los tres roles; service_role sin EXECUTE (requiere sesión authenticated); conciliar solo authenticated (autorizacion interna admin);
-- falsificar=false ambos. No ejecutar el cuerpo base directamente desde clientes.
SELECT id,estado,metodo_pago,efectivo_cancelacion_estado,efectivo_conciliado_por,
 efectivo_conciliado_en,efectivo_conciliacion_nota FROM public.ventas
WHERE estado='cancelada' AND metodo_pago='Efectivo';
-- anon false/false, authenticated true/true; ambas RPC validan perfil/sucursal.

-- Informe por sucursal y vinculo EXPLICITO. NULL permanece grupo sin turno.
-- Importes son cobros registrados (tras descuentos), no subtotal de productos.
SELECT empresa_id,sucursal_id,caja_turno_id,metodo_pago,
 count(*) FILTER(WHERE estado='activa') ordenes_validas,
 count(*) FILTER(WHERE estado='cancelada') ordenes_canceladas,
 coalesce(sum(total),0) bruto_registrado,
 coalesce(sum(total) FILTER(WHERE estado='cancelada'),0) total_cancelado,
 coalesce(sum(total) FILTER(WHERE estado='activa'),0) total_neto
FROM public.ventas GROUP BY empresa_id,sucursal_id,caja_turno_id,metodo_pago
ORDER BY sucursal_id,caja_turno_id,metodo_pago;

-- Historial CERRADO: estos son los importes guardados, NO recalcular/actualizar.
SELECT id,sucursal_id,fecha_apertura,fecha_cierre,total_ventas,ventas_efectivo,
 ventas_tarjeta,ventas_transferencia,numero_ordenes,entradas_total,salidas_total,
 efectivo_esperado,efectivo_contado,diferencia FROM public.caja_turnos
WHERE fecha_cierre IS NOT NULL ORDER BY id;

-- Diagnostico de legado que Flutter actualmente seleccionaria por periodo.
-- Se incluye temporalmente en el resumen de cierre como el filtro de Flutter,
-- pero NO constituye una asociacion persistente ni instruccion de UPDATE.
SELECT t.id turno_a_revisar,v.id venta_sin_vinculo,v.total,v.estado,v.fecha_hora
FROM public.caja_turnos t JOIN public.ventas v ON v.empresa_id=t.empresa_id AND v.sucursal_id=t.sucursal_id
WHERE t.fecha_cierre IS NULL AND v.caja_turno_id IS NULL AND v.operacion_id IS NULL
 AND v.fecha_hora >= (t.fecha_apertura AT TIME ZONE 'America/Monterrey')
 AND v.fecha_hora < (clock_timestamp() AT TIME ZONE 'America/Monterrey');
SELECT id,sucursal_id,total,metodo_pago,estado FROM public.ventas
WHERE caja_turno_id IS NULL AND operacion_id IS NOT NULL;
-- Las filas de arriba nunca entran en los importes por turno de la nueva RPC.
