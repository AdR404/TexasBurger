import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/product_service.dart';
import 'services/sales_service.dart';
import 'services/config_service.dart';
import 'services/caja_service.dart';
import 'services/db_service.dart';
import 'services/discount_code_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system bar styles to match Texas Burger branding
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const TexasBurgerApp());
}

Future<void> initializeServices() async {
  await DbService.init();
  await ProductService().init();
  await SalesService().init();
  await DiscountCodeService().init();
  await ConfigService().init();
  await CajaService().init();
}

class TexasBurgerApp extends StatelessWidget {
  const TexasBurgerApp({super.key, this.initialize = initializeServices});

  final Future<void> Function() initialize;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Texas Burger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _StartupScreen(initialize: initialize),
    );
  }
}

class _StartupScreen extends StatefulWidget {
  const _StartupScreen({required this.initialize});

  final Future<void> Function() initialize;

  @override
  State<_StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<_StartupScreen> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = Future<void>.sync(widget.initialize);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return const HomeScreen();
      }
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snapshot.hasError) ...[
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudieron cargar los datos locales. '
                      'Cierra y vuelve a abrir la aplicación o intenta de nuevo. '
                      'No borres los datos de la aplicación.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {
                        _initialization = Future<void>.sync(widget.initialize);
                      }),
                      child: const Text('Reintentar'),
                    ),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Cargando Texas Burger…'),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
