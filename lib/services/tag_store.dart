import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TagStore {
  static String _keyFor(String photoID) => 'tags_' + photoID;

  /// Save tags locally under canonical `photoID`.
  static Future<void> saveLocalTags(String photoID, List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(photoID), json.encode(tags));
  }

  /// Load tags saved locally for `photoID`. Returns null if none stored.
  static Future<List<String>?> loadLocalTags(String photoID) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(photoID));
    if (raw == null) return null;
    try {
      final list = json.decode(raw) as List;
      return list.cast<String>();
    } catch (_) {
      return null;
    }
  }

  /// Remove local tags for a photoID
  static Future<void> removeLocalTags(String photoID) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(photoID));
  }
}
