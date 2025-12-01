import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkUtils {
  /// Returns whether the current connection is Wi‑Fi.
  static Future<bool> isOnWifi() async {
    try {
      final res = await Connectivity().checkConnectivity();
      return res == ConnectivityResult.wifi;
    } catch (_) {
      return false;
    }
  }

  /// Returns whether the device has any network connectivity.
  static Future<bool> isConnected() async {
    try {
      final res = await Connectivity().checkConnectivity();
      return res != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }
}
