import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';

class ConfigService extends ChangeNotifier {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  AppConfig _config = const AppConfig();
  bool _initialized = false;

  AppConfig get config => _config;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('texas_config');
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        _config = AppConfig.fromJson(jsonDecode(jsonString));
      } catch (e) {
        _config = const AppConfig();
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('texas_config', jsonEncode(_config.toJson()));
    notifyListeners();
  }
}