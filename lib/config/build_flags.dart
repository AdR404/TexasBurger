import 'package:flutter/foundation.dart';

class BuildFlags {
  static const bool demoDataEnabledByBuild = bool.fromEnvironment(
    'TEXAS_ENABLE_DEMO_DATA',
    defaultValue: false,
  );

  static bool? _demoDataEnabledForTesting;

  static bool get demoDataEnabled =>
      kDebugMode &&
      (demoDataEnabledByBuild || _demoDataEnabledForTesting == true);

  @visibleForTesting
  static void setDemoDataEnabledForTesting(bool enabled) {
    assert(kDebugMode);
    _demoDataEnabledForTesting = enabled;
  }

  @visibleForTesting
  static void resetDemoDataForTesting() {
    _demoDataEnabledForTesting = null;
  }
}
