# Fase 2 — Recetas y consumo (diseño para revisión, no activado)

## Alcance y evidencia

Revisión sobre main 6b6149b, conservando cambios pendientes de fase 1.
El usuario confirmó 22 productos sin filas de receta en producto_ingrediente.
No se ha consultado ni modificado Supabase en esta fase. database/schema.sql:45–58
declara ingredientes y producto_ingrediente, pero no es un volcado actualizado.
No contiene el DDL completo de lotes, movimientos y RPC instaladas. Los scripts
login_fase4 alteran funciones existentes por patrones, no reconstruyen el esquema.

## Revisión de fase 1

ProductService.resolveRemoteId conserva ID local -> remoto en una clave por
proyecto. Serializa vinculaciones dentro del proceso. Rechaza duplicar un ID
remoto entre dos IDs locales; valida activo e ID en cada cobro y no vuelve al
nombre si el vínculo deja de funcionar. Los renombres locales/remotos no rompen
un vínculo existente. No cambia precios al leer productos remotos.

La correspondencia es local por dispositivo, no un catálogo maestro compartido.
Después de borrar datos/desinstalar, el vínculo se pierde: se exige otra vez un
nombre exacto único. Un nombre renombrado antes de esa nueva vinculación bloquea
el producto. No puede demostrar identidad histórica tras perder la clave, ni
detectar que otro operador reutilizó un ID remoto para un producto distinto.
El servidor debe conservar los IDs como identidades estables (no reutilizarlos).
Si se necesita recuperación inequívoca entre dispositivos, hará falta un código
estable de catálogo en BD o vinculación administrativa explícita. No se inventa
esa correspondencia aquí. Una desactivación entre la lectura y el INSERT sigue
siendo una carrera del flujo actual; la futura RPC debe validarlo en transacción.
No se modifica la implementación de fase 1 en esta fase.

## Diferencia de pruebas 76 / 71

`git log --all -- test/auth_service_test.dart` localiza el respaldo WIP 02dbf23.
Se inspeccionó con git show, sin aplicar ni modificar el respaldo.
Comparación con HEAD (conteos expandiendo los bucles de tests):

| Archivo/grupo | Respaldo | HEAD | Diferencia |
|---|---:|---:|---:|
| auth_service_test.dart | 23 | 5 | -18 |
| auth_widgets_test.dart | 8 | 4 | -4 |
| inventory_demo_test.dart | 0 | 3 | +3 |
| operator_access_card_test.dart | 0 | 2 | +2 |
| sale_context_test.dart (caso bandera demo) | — | — | +1 |
| Resto (incluidos casos renombrados) | | | 0 |

76 - 18 - 4 + 3 + 2 + 1 = 60 en HEAD; fase 1 añadió 11 = 71.
No es una pérdida causada por fase 1. El WIP no es ancestro integrado: la evidencia
no permite atribuir su omisión a una resolución concreta de merge.
También d99c514 sustituyó pruebas antiguas de credenciales demo por fixtures.

Cobertura del WIP ausente/reducida en HEAD: respuestas 200/409/422/503 del alta,
solicitudes concurrentes, conservación de sesión administrativa, recuperación
aislada/rechazada/restaurada, identidad desde RPC frente a metadata, seis perfiles
inválidos, limpieza de identidades legacy, revocación/restauración de sesión,
escritor remoto con detalles completos/incompletos, empleado de apertura Caja,
eliminación de rutas protegidas al cerrar sesión, flujo visual de recuperación
y acceso de cajero a Caja. Hay pruebas superficiales equivalentes para algunos
casos; no sustituyen toda la cobertura anterior. Restaurarlas/adaptarlas merece
una tarea separada; no reactivar login demo ni aplicar todo el WIP.

## Unidades, cantidades y lotes actuales

- Ingredientes: ID entero; unidad_medida textual. schema.sql también mantiene
  stock_actual global, pero InventoryRepository.load usa lotes por sucursal.
- Receta base: PK (producto_id, ingrediente_id), cantidad_requerida numeric(10,2)
  en esquema local. No existe unidad explícita en esa definición.
- Lotes: InventoryRepository.load consume ingrediente_id, sucursal_id, unidad,
  cantidad_inicial/disponible, costo y fechas. No hay consulta de recetas al cobrar.
- inventoryAvailableText suma por unidad, sin conversión; incluye todos los lotes
  que recibe, incluso caducados. No equivale al stock utilizable para una venta.
- registerLot admite kg, pzas y L y tres decimales. Datos SQL antiguos usan pza y
  reb. El selector demo ofrece g/ml: no son unidades reales automáticamente válidas.
- La UI de bajas excluye caducados para salida y ordena por caducidad, pero elige
  un lote manualmente. Descarte admite caducados. Usa reloj local para el filtro.
- La RPC de baja se invoca por lote con tipo, cantidad y motivo; necesita permiso
  administrativo. Sus bloqueos/CHECK definitivos deben verificarse en servidor.

Referencias: lib/services/inventory_repository.dart:76,144,181;
lib/models/inventory_lot.dart:39; lib/widgets/inventory_movements_sheet.dart:89,132;
lib/widgets/add_inventory_lot_sheet.dart:265; database/schema.sql:45.

## Estructura propuesta (no DDL ejecutable todavía)

Reutilizar producto_ingrediente como única receta base. Cantidad positiva y
precisión suficiente (candidato numeric(18,6), sujeto a límites de lotes reales).
Añadir unidad_receta explícita para configurar líneas nuevas; no rellenar unidades
históricas por suposición. Debe pertenecer a la misma dimensión que el ingrediente.
Una receta publicada no puede contener líneas sin unidad/cantidad válidas.

En productos, proponer modo_consumo y receta_estado/version:
- pendiente: bloquea el futuro cobro con consumo; estado inicial seguro.
- receta: requiere líneas configuradas y aprobadas.
- unidad_completa: requiere una línea explícita hacia el ingrediente que representa
  la unidad comercial; no deducirlo por categoría o nombre ni asumir cantidad uno.
- combo: requiere composición configurada y componentes válidos.
- sin_consumo: exención explícita aprobada por administrador, con motivo; nunca
  consecuencia automática de que no existan líneas.
La modalidad es excluyente para evitar contar receta y componentes dos veces.
Estos estados no alteran ventas antiguas ni el cobro actual mientras esté vigente.

Extensiones propuestas solo para conceptos que no cubre producto_ingrediente:
- producto_componentes: combo_id, componente_producto_id, cantidad por combo,
  unicidad del par. FK, cantidad positiva y validación de ciclos/profundidad.
  Primera versión: composición fija. Elecciones variables requieren reglas propias.
- modificadores_producto: ID estable, producto aplicable, tipo extra/exclusion,
  activo, límites por unidad y versión aprobada.
- modificador_ingrediente: modificador_id, ingrediente_id, cantidad positiva,
  unidad; el tipo del modificador determina sumar/restar. No cantidades negativas
  arbitrarias enviadas desde el cliente. Exclusiones solo de componentes permitidos.
  Definir incompatibilidades (extra y exclusión simultáneos) antes de publicar.
- consumo trazable: ampliar inventario_movimientos con detalle_venta_id y origen
  consumo_venta (más clave de reversión futura), o usar tabla enlace si restricciones
  instaladas impiden esa ampliación. No crear una segunda contabilidad de saldos.

## Conversiones y precisión propuestas

Usar numeric PostgreSQL, no double para saldo/consumo definitivo.
1 kg = 1000 g; 1 L = 1000 ml. No convertir masa a volumen ni piezas a peso.
Piezas deben ser enteras si la unidad se define como indivisible. Normalizar pza /
pzas solo después de confirmar que significan la misma unidad en los datos reales.
reb, porciones, cucharadas y equivalencias similares requieren datos del negocio.

Multiplicar receta + modificadores por cantidad vendida; agregar por ingrediente
antes de asignar lotes. Rechazar exclusiones que generen consumo negativo.
La suma debe conservarse exactamente al distribuirla. Si un resultado no es
representable con la escala de saldo instalada, bloquear configuración/operación;
no redondear silenciosamente ni elevar el consumo sin una regla aprobada.

## Contrato y transacción futura

Entrada conceptual: solicitud_id estable, sucursal solicitada, líneas con producto_id,
cantidad y modificadores estructurados; importes comerciales según regla aprobada.
La nota libre se conserva pero no decide consumo. Extra local ext_* no es todavía
ID remoto. «Salsas aparte» no significa quitar salsa. Los combos hoy son productos
independientes sin componentes (BootstrapService). No deducir recetas de sus nombres.

1. Exigir authenticated, auth.uid(), perfil activo, empleado real activo y sucursal
   activa/autorizada. El servidor deriva usuario y empleado; no acepta rol del cliente.
2. Reclamar solicitud_id con unicidad y contenido canónico (actor, sucursal, líneas,
   modificadores e importes). Igual clave/igual solicitud devuelve resultado previo;
   igual clave/contenido distinto rechaza. Revalidar acceso antes de devolver datos.
   Dos llamadas simultáneas deben esperar/conflictuar por unicidad, no ambas consumir.
3. Validar productos/recetas publicadas/modificadores. Bloquear o fijar sus versiones
   para que un cambio concurrente no mezcle recetas. Persistir consumo resultante
   y versión usada; cambios futuros de receta no alteran el consumo histórico.
4. Validar importes/IVA/cupones según regla por acordar. No cambiar los cobros actuales
   ni considerar seguros totales arbitrarios enviados por Flutter.
5. Asociar turno si esa regla se aprueba y bloquearlo antes de aceptar la venta.
   El cierre deberá compartir el protocolo. Decisión pendiente: ventas sin turno.
6. Normalizar unidades y agrupar necesidades por ingrediente. Rechazar receta ausente.
7. Bloquear lotes de la sucursal: orden global consistente de ingrediente y después
   FEFO (fecha_caducidad, fecha_entrada, id). Releer saldo después de esperar.
   No usar SKIP LOCKED para concluir falsamente que falta stock ocupado por otra venta.
   Coordinar el orden con bajas y futuras devoluciones; revisar RPC actuales primero.
8. Excluir caducados según fecha de servidor en America/Monterrey. Pendiente aprobar
   uso en el propio día de caducidad. Almacén/Refrigerador no intercambiables si el
   negocio exige ubicación específica: debe definirse, no inferirse.
9. Distribuir entre varios lotes. Si falta cualquier ingrediente, error y rollback
   total (incluida cabecera, detalles, movimientos y reclamo idempotente transaccional).
10. Insertar venta/detalles, actualizar saldos y registrar movimientos antes/después,
    actor Auth, detalle y lote. Una única llamada RPC/una transacción PostgreSQL.
11. Devolver venta_id y resultado confirmado. Tras una respuesta perdida, consultar o
    repetir con la MISMA solicitud_id; no generar otra clave ni reintentar ciegamente.

La venta consume como operación de negocio permitida al cajero; no concede EXECUTE
sobre bajas administrativas. Si se comparte lógica, debe ser un auxiliar privado
sin EXECUTE para clientes. RPC pública SECURITY DEFINER con search_path controlado,
objetos calificados, privilegios mínimos y validación explícita de identidad.
No ampliar la RPC administrativa para que acepte cajeros. Cuando se active el nuevo
flujo, coordinar revocación de INSERT directo de ventas/detalles y mutaciones de saldo
para evitar bypass. No cambiar ahora esos permisos.

## SQL preparado y reversión

database/inventario_fase2/00_inspeccion_solo_lectura.sql entrega esquema real,
restricciones, índices, triggers, políticas y definiciones/ACL de funciones.
No se preparan migraciones ni reversión ejecutables hasta revisar esos resultados:
desconocemos escala/check reales, dependencias y modificaciones de otras personas.
La consulta no crea objetos y no necesita reversión.

Tras inspeccionar: migración aditiva con precondiciones explícitas, sin borrar ni
rellenar históricos; compatibilidad del cobro antiguo hasta activar la RPC nueva.
Reversión operativa propuesta: desactivar nuevo escritor, restaurar permisos/funciones
respaldados y conservar columnas, recetas y movimientos ya registrados. No reducir
precisión ni borrar consumo histórico. Los scripts definitivos deberán reflejar las
ACL y cuerpos exactos instalados y revisar que la reversión no habilite bypass.

## Pendientes antes de activar

Unidades y recetas reales de los 22 productos; cantidades de extras/exclusiones;
componentes de combos; productos sin consumo explícito; precisión; caducidad y
ubicaciones; ventas sin turno; reglas de precios/cupones; inspección SQL completa.
Probar en entorno separado consumo multilote, falta de stock con rollback, solicitudes
concurrentes/repetidas, cambio de receta, perfiles inválidos y sucursal manipulada.
No reconstruir consumos de ventas históricas. No modificar datos demo en esta fase.
