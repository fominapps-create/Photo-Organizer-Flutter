import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TagStore {
  static String _keyFor(String photoID) => 'tags_$photoID';

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

  /// Clear all tags that start with 'tags_' prefix (bulk delete)
  static Future<int> clearAllTags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    int removed = 0;

    // Find all tag keys
    final tagKeys = keys.where((key) => key.startsWith('tags_')).toList();

    // Remove them all
    for (final key in tagKeys) {
      await prefs.remove(key);
      removed++;
    }

    return removed;
  }

  /// Save multiple tags at once (faster than individual saves)
  static Future<void> saveLocalTagsBatch(
    Map<String, List<String>> photoIDsToTags,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // Write all keys in parallel for maximum speed
    final futures = photoIDsToTags.entries.map((entry) {
      return prefs.setString(_keyFor(entry.key), json.encode(entry.value));
    }).toList();
    await Future.wait(futures);
  }

  /// Check which photos have tags (bulk check for performance)
  /// Returns a Set of photoIDs that have tags
  static Future<Set<String>> getPhotoIDsWithTags(List<String> photoIDs) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String>{};

    for (final photoID in photoIDs) {
      if (prefs.containsKey(_keyFor(photoID))) {
        result.add(photoID);
      }
    }

    return result;
  }

  /// Get total number of stored tag entries (for diagnostics)
  static Future<int> getStoredTagCount() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    return keys.where((key) => key.startsWith('tags_')).length;
  }

  /// Remove orphaned tags (tags for photos that no longer exist)
  /// Returns number of orphaned tags removed
  static Future<int> cleanOrphanedTags(Set<String> validPhotoIDs) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    int removed = 0;

    final tagKeys = keys.where((key) => key.startsWith('tags_')).toList();

    for (final key in tagKeys) {
      final photoID = key.substring('tags_'.length);
      if (!validPhotoIDs.contains(photoID)) {
        await prefs.remove(key);
        removed++;
      }
    }

    return removed;
  }

  /// Load all tags at once for multiple photos (batch loading)
  /// Returns a Map of photoID -> tags
  /// Much faster than calling loadLocalTags() for each photo individually
  static Future<Map<String, List<String>>> loadAllTagsMap(
    List<String> photoIDs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, List<String>>{};

    for (final photoID in photoIDs) {
      final raw = prefs.getString(_keyFor(photoID));
      if (raw != null) {
        try {
          final list = json.decode(raw) as List;
          result[photoID] = list.cast<String>();
        } catch (_) {
          // Skip invalid entries
        }
      }
    }

    return result;
  }
}
