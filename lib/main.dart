import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/product_service.dart';
import 'services/sales_service.dart';
import 'services/config_service.dart';
import 'services/caja_service.dart';
import 'services/db_service.dart';
import 'services/discount_code_service.dart';
import 'services/app_auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';

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
  await AppAuthService().init();
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

class _StartupScreenState extends State<_StartupScreen>
    with WidgetsBindingObserver {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialization = Future<void>.sync(widget.initialize);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        AppAuthService().isAuthenticated) {
      unawaited(AppAuthService().refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return ListenableBuilder(
          listenable: AppAuthService(),
          builder: (context, _) {
            if (AppAuthService().isRecoveringPassword) {
              return const ResetPasswordScreen();
            }
            if (AppAuthService().isAuthenticated) {
              return Navigator(
                key: ValueKey(AppAuthService().currentUser!.id),
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
              );
            }
            return Navigator(
              key: const ValueKey('login'),
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
            );
          },
        );
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
