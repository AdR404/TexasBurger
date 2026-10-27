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

void main() async {
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

  // Initialize services
  await DbService.init();
  await ProductService().init();
  await SalesService().init();
  await DiscountCodeService().init();
  await ConfigService().init();
  await CajaService().init();

  runApp(const TexasBurgerApp());
}

class TexasBurgerApp extends StatelessWidget {
  const TexasBurgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Texas Burger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}