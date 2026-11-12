# Integracion Flutter preparada, desactivada por defecto

No se modificaron SQL, recetas, dependencias ni datos remotos. No se genero APK.

Para una compilacion futura de pruebas controladas se necesitan AMBAS opciones:
`--dart-define=TEXAS_ENABLE_SIMPLE_SALES=true`
`--dart-define=TEXAS_ENABLE_INVENTORY_SALES=true`
y la preferencia existente de sincronizacion habilitada. Se conserva la seleccion
actual de entorno Supabase (usar entorno aislado de pruebas). La segunda opcion
usa bool.fromEnvironment con default false. No hay activacion desde una pantalla.
Con esa opcion false SalesService conserva su escritor anterior sin cambios de flujo.
Con true y configuracion incompleta, se bloquea el cobro; no pasa a modo local ni
a INSERT separados. DbService.guardarVenta tambien rechaza uso directo en ese modo.

DbService prepara el contrato exacto de registrar_venta_con_consumo y usa
ProductService.resolveRemoteId: primero correspondencia persistente por ID; solo
la vinculacion inicial utiliza nombre exacto unico, como fase1. Ningun ID inventado.
Los importes provienen de Venta/PricingService, sin recalcular ni alterar descuentos.
Se comprueba perfil actual y sucursal fija; el administrador general conserva
su seleccion operativa. El servidor deriva la identidad definitiva de Auth.

Extras/exclusiones/notas de producto o notas generales no vacias se rechazan
ANTES de enviar. Nunca se borran para pasar la validacion. Datos de entrega y mesa
se conservan en la instantanea local del ticket, sin enviarlos como campos extra.

InventorySaleAttempt guarda UN intento en SharedPreferences por proyecto, con
actor UUID, UUID v4 criptograficamente aleatorio, solicitud exacta e instantanea
de Venta. No incluye credenciales ni tokens. No es una cola ni tiene reintentos
automaticos. SalesService serializa el flujo. Antes de cada envio se persiste sent.
Resultado incierto, timeout (30s), respuesta invalida o error no reconocido:
conservar intento y bloquear nuevas ventas. Boton Recuperar cobro pendiente en
la vista existente permite repetir manualmente el mismo UUID y JSON tras reinicio.
Requiere la sesion del mismo usuario y el mismo proyecto; otro usuario no puede
reemplazarlo. No se permite descartar manualmente una operacion incierta.

Un primer rechazo SQL 22023/42501 confirma que esa llamada no registro la venta:
se informa el mensaje y libera el intento para corregir el carrito. Si ya hubo
un envio anterior incierto, incluso esos errores conservan el intento: no prueban
que la primera llamada haya fallado. Si el perfil se desactiva, BD debe verificar
la operacion antes de cualquier decision manual; no se genera otro UUID a ciegas.

Respuesta complete valida exige venta_id positivo, repetida boolean y turno
nullable valido. Repetida=true es confirmacion de la misma venta, nunca otro cobro.
La respuesta se persiste antes del historial. Venta conserva operationId, remoteId
y cashTurnId opcionales, compatibles con historicos sin estos campos. El ID local
de estas ventas es el UUID. Se deduplica por operationId, guarda historial y SOLO
entonces elimina el pendiente. Si falla guardado/limpieza se puede recuperar sin
otra llamada remota cuando ya existe confirmacion local. Tras recuperar, se muestra
el ticket y se limpia el carrito de la vista, igual que al completar un cobro.

Limites: un intento por proyecto/dispositivo; no recupera datos tras desinstalar o
borrar SharedPreferences. No cambiar a una compilacion del escritor antiguo con
intentos inciertos sin reconciliarlos primero. El almacenamiento es el existente,
sin SQLite ni nuevas dependencias. Los 22 productos pendientes seguiran siendo
rechazados por PostgreSQL; faltan recetas reales, reglas de personalizaciones,
pruebas SQL aisladas y prueba integral Android antes de activar consumo.
Persisten las limitaciones comerciales y de cierre de Caja documentadas en SQL.

Pruebas locales con mocks cubren contrato, importes/IDs, personalizaciones,
UUID/JSON estable, respuesta repetida, errores definitivos/inciertos, reinicio,
deduplicacion, aislamiento por actor y seleccion de escritor sin fallback.
