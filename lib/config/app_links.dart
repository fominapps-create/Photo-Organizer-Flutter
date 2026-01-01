import 'app_config.dart';

/// App-wide external links. Update app_config.dart for version constants.
class AppLinks {
  /// Public URL to your hosted privacy policy.
  /// Example: 'https://filtored.app/privacy-policy'
  static const String kPrivacyPolicyUrl = 'https://filtored.com/privacy';

  /// App version - use AppConfig.appVersion instead
  /// This is kept for backward compatibility
  static String get appVersion => AppConfig.appVersion;
}
