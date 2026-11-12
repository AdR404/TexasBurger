## Instalación y ejecución

Texas Burger es una aplicación desarrollada en Flutter y Dart para Android, que utiliza Supabase como base de datos.

### Requisitos

* Flutter SDK instalado.
* Android Studio.
* Emulador Android o dispositivo físico.
* Conexión a Internet para utilizar Supabase.

### Ejecutar la aplicación

1. Clonar el repositorio y cambiar a la rama de integración:

```bash
git clone <URL_DEL_REPOSITORIO>
cd TexasBurguer
```

2. Instalar las dependencias:

```bash
flutter pub get
```

3. Iniciar un emulador Android o conectar un dispositivo con depuración USB habilitada.

4. Ejecutar la aplicación:

```bash
flutter run --dart-define=TEXAS_ENABLE_SIMPLE_SALES=true --dart-define=TEXAS_ENABLE_INVENTORY_SALES=true --dart-define=TEXAS_ENABLE_SALE_CANCELLATIONS=true --dart-define=TEXAS_ENABLE_VERIFIED_CASH_CLOSE=true
```

**Importante:** utilizar los parámetros para que la aplicación tenga la conexión con Supabase.

Los datos simulados del inventario están desactivados de forma predeterminada. Para probar su interfaz en una compilación de desarrollo, iniciar con `--dart-define=TEXAS_ENABLE_DEMO_DATA=true`. No habilites esta bandera en compilaciones de producción.

### Configuración de Supabase

La aplicación utiliza el proyecto Supabase configurado en el código.

Para trabajar con las funciones remotas:

1. Abrir Texas Burger.
2. Seleccionar la sucursal y el empleado correspondientes.
3. Activar la conexión remota desde Configuración.
4. Para Inventario y Caja, iniciar sesión con una cuenta autorizada de Supabase Auth.

Las cuentas de administrador local y de Supabase Auth son independientes.

El acceso remoto a Inventario y Caja requiere autorización en `inventario_admins`.

**Importante:** PEDIR CREACIÓN DE CUENTA PARA ACCEDER A LA BASE DE DATOS DESDE LA APLICACIÓN.

### Funcionalidades disponibles

* Registro de ventas.
* Productos, promociones y descuentos.
* Tickets de compra.
* Historial de ventas.
* Apertura y cierre de caja.
* Entradas y salidas de efectivo.
* Inventario de ingredientes.
* Registro de lotes, salidas y descartes.
* Control de existencias y caducidades.

Ventas, Historial, Caja e Inventario están conectados a Supabase cuando se utiliza el modo remoto correspondiente.

### Generar APK

Para generar el APK de Android:

```bash
flutter build apk --release --dart-define=TEXAS_ENABLE_SIMPLE_SALES=true --dart-define=TEXAS_ENABLE_INVENTORY_SALES=true --dart-define=TEXAS_ENABLE_SALE_CANCELLATIONS=true --dart-define=TEXAS_ENABLE_VERIFIED_CASH_CLOSE=true
```

El archivo generado se encuentra en:

```text
build/app/outputs/flutter-apk/app-release.apk
```

### Consideraciones

* La aplicación requiere conexión a Internet para realizar operaciones remotas.
* Los datos registrados en Supabase son compartidos entre los dispositivos que utilizan el mismo proyecto.
* Inventario y Caja requieren una sesión remota autorizada.
* Para operar Caja, configurar correctamente la fecha, hora y zona horaria del dispositivo (`America/Monterrey`, UTC−6).
* El historial y la caja locales son independientes de sus registros remotos; no existe sincronización automática entre ambos modos.
* Las ventas de prueba realizadas contra Supabase generan registros reales.
