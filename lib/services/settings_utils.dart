import 'package:url_launcher/url_launcher_string.dart';
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';
import 'dart:developer' as developer;

class SettingsUtils {
  /// Try to open the system Wi‑Fi settings.
  /// On Android we use an intent URI; on other platforms we attempt common schemes
  /// and otherwise return false.
  static Future<bool> openWifiSettings() async {
    try {
      if (PlatformInfo.isAndroid) {
        // Use an Android intent URI to open Wi‑Fi settings
        const intent =
            'intent:#Intent;action=android.settings.WIFI_SETTINGS;end';
        developer.log('Opening Android Wi‑Fi settings via intent');
        return await launchUrlString(
          intent,
          mode: LaunchMode.externalApplication,
        );
      }

      if (PlatformInfo.isIOS) {
        // iOS: try the prefs scheme (may be restricted on modern iOS)
        const uri = 'App-Prefs:root=WIFI';
        developer.log('Opening iOS Wi‑Fi settings (may fail on modern iOS)');
        return await launchUrlString(uri, mode: LaunchMode.externalApplication);
      }

      // Desktop / web: nothing standard to open; return false
      developer.log(
        'No OS-specific Wi‑Fi settings open available for this platform',
      );
      return false;
    } catch (e) {
      developer.log('Failed to open Wi‑Fi settings: $e');
      return false;
    }
  }
}
