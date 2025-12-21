import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TagStore {
  static String _keyFor(String photoID) => 'tags_$photoID';
  static String _detectionsKeyFor(String photoID) => 'detections_$photoID';

  /// Save tags locally under canonical `photoID`.
  static Future<void> saveLocalTags(String photoID, List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(photoID), json.encode(tags));
  }

  /// Save all detections (detailed object list for search)
  static Future<void> saveLocalDetections(
    String photoID,
    List<String> detections,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detectionsKeyFor(photoID), json.encode(detections));
  }

  /// Load detections saved locally for `photoID`. Returns null if none stored.
  static Future<List<String>?> loadLocalDetections(String photoID) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_detectionsKeyFor(photoID));
    if (raw == null) return null;
    try {
      final list = json.decode(raw) as List;
      return list.cast<String>();
    } catch (_) {
      return null;
    }
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

  /// Clear all tags and detections (bulk delete)
  static Future<int> clearAllTags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    int removed = 0;

    // Find all tag and detection keys
    final tagKeys = keys
        .where(
          (key) => key.startsWith('tags_') || key.startsWith('detections_'),
        )
        .toList();

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

  /// Save multiple detections at once (faster than individual saves)
  static Future<void> saveLocalDetectionsBatch(
    Map<String, List<String>> photoIDsToDetections,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final futures = photoIDsToDetections.entries.map((entry) {
      return prefs.setString(
        _detectionsKeyFor(entry.key),
        json.encode(entry.value),
      );
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

  /// Check which photos have NON-EMPTY tags (excludes photos with empty [] tags)
  /// Returns a Set of photoIDs that have actual tags
  static Future<Set<String>> getPhotoIDsWithNonEmptyTags(
    List<String> photoIDs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String>{};

    for (final photoID in photoIDs) {
      final raw = prefs.getString(_keyFor(photoID));
      if (raw != null) {
        try {
          final list = json.decode(raw) as List;
          if (list.isNotEmpty) {
            result.add(photoID);
          }
        } catch (_) {
          // Invalid entry, don't include
        }
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

  /// Remove all entries that have empty tag arrays
  /// Returns number of empty entries removed
  static Future<int> cleanEmptyTags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    int removed = 0;

    final tagKeys = keys.where((key) => key.startsWith('tags_')).toList();

    for (final key in tagKeys) {
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          final list = json.decode(raw) as List;
          if (list.isEmpty) {
            await prefs.remove(key);
            removed++;
          }
        } catch (_) {
          // Remove invalid entries too
          await prefs.remove(key);
          removed++;
        }
      }
    }

    return removed;
  }

  /// Load all tags at once for multiple photos (batch loading)
  /// Returns a Map of photoID -> tags (excludes empty tag arrays)
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
          // Only include non-empty tag lists
          if (list.isNotEmpty) {
            result[photoID] = list.cast<String>();
          }
        } catch (_) {
          // Skip invalid entries
        }
      }
    }

    return result;
  }

  /// Load all detections at once for multiple photos (batch loading)
  static Future<Map<String, List<String>>> loadAllDetectionsMap(
    List<String> photoIDs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, List<String>>{};

    for (final photoID in photoIDs) {
      final raw = prefs.getString(_detectionsKeyFor(photoID));
      if (raw != null) {
        try {
          final list = json.decode(raw) as List;
          if (list.isNotEmpty) {
            result[photoID] = list.cast<String>();
          }
        } catch (_) {
          // Skip invalid entries
        }
      }
    }

    return result;
  }
}
