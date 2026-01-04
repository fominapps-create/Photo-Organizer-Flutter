import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class TagStore {
  static String _keyFor(String photoID) => 'tags_$photoID';
  static String _detectionsKeyFor(String photoID) => 'detections_$photoID';
  static String _scanVersionKeyFor(String photoID) => 'scanver_$photoID';

  /// Save tags locally under canonical `photoID`.
  static Future<void> saveLocalTags(String photoID, List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(photoID), json.encode(tags));
    // Also save the current scan version when tags are saved
    await prefs.setInt(_scanVersionKeyFor(photoID), scanLogicVersion);
  }

  /// Save all detections (detailed object list for search)
  static Future<void> saveLocalDetections(
    String photoID,
    List<String> detections,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detectionsKeyFor(photoID), json.encode(detections));
  }

  /// Load the scan version that was used when this photo was scanned
  static Future<int> loadPhotoScanVersion(String photoID) async {
    final prefs = await SharedPreferences.getInstance();
    // Try new int format first
    final intVersion = prefs.getInt(_scanVersionKeyFor(photoID));
    if (intVersion != null) return intVersion;
    // Migrate from old string format
    final oldVersion = prefs.getString(_scanVersionKeyFor(photoID));
    if (oldVersion != null && oldVersion.isNotEmpty) {
      final parts = oldVersion
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      final major = parts.isNotEmpty ? parts[0] : 0;
      final minor = parts.length > 1 ? parts[1] : 0;
      return major * 10 + minor;
    }
    return 0;
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
  /// Optimized to remove all keys as fast as possible
  static Future<int> clearAllTags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    // Find all tag and detection keys
    final tagKeys = keys
        .where(
          (key) => key.startsWith('tags_') || key.startsWith('detections_'),
        )
        .toList();

    final count = tagKeys.length;

    if (count == 0) return 0;

    // Remove ALL keys in parallel for maximum speed
    // SharedPreferences handles this efficiently
    await Future.wait(tagKeys.map((key) => prefs.remove(key)));

    return count;
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
  /// OPTIMIZED: Avoids JSON parsing - just checks if value is more than "[]"
  static Future<Set<String>> getPhotoIDsWithNonEmptyTags(
    List<String> photoIDs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String>{};

    // Get all keys once - much faster than individual getString calls
    final allKeys = prefs.getKeys();
    final tagKeys = allKeys.where((k) => k.startsWith('tags_')).toSet();

    for (final photoID in photoIDs) {
      final key = _keyFor(photoID);
      if (!tagKeys.contains(key)) continue;

      final raw = prefs.getString(key);
      // FAST CHECK: Skip JSON parsing - just check if it's non-empty and not "[]"
      if (raw != null && raw.length > 2) {
        // Length > 2 means it's not just "[]"
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

  /// Load all scan versions at once for multiple photos (batch loading)
  /// Returns a Map of photoID -> scanVersion (int)
  static Future<Map<String, int>> loadAllScanVersionsMap(
    List<String> photoIDs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, int>{};

    for (final photoID in photoIDs) {
      // Try new int format first
      final intVer = prefs.getInt(_scanVersionKeyFor(photoID));
      if (intVer != null) {
        result[photoID] = intVer;
        continue;
      }
      // Migrate from old string format
      final ver = prefs.getString(_scanVersionKeyFor(photoID));
      if (ver != null && ver.isNotEmpty) {
        final parts = ver.split('.').map((s) => int.tryParse(s) ?? 0).toList();
        final major = parts.isNotEmpty ? parts[0] : 0;
        final minor = parts.length > 1 ? parts[1] : 0;
        result[photoID] = major * 10 + minor;
      }
    }

    return result;
  }

  // ============ Scan Version Tracking (Hybrid Approach) ============
  //
  // See RELEASE_GUIDE.md for full versioning documentation and flows.
  //
  // VERSIONING CONVENTION:
  // - Scan logic version is a simple INTEGER, independent from app version
  // - Increment when classification logic changes (triggers rescan dialog)
  //
  // WHEN TO INCREMENT scanLogicVersion:
  // - Changed ML Kit confidence thresholds
  // - Added/removed keywords from detection lists
  // - Modified tier-based logic (people/animals/food)
  // - Changed category mapping rules
  //
  // WHEN NOT TO INCREMENT:
  // - UI changes, bug fixes unrelated to scanning
  // - Performance optimizations that don't change results
  // - New features that don't affect existing photo tags
  //
  // VERSION HISTORY:
  // 1 - Initial ML Kit implementation
  // 2 - Tier-based people detection, animal deduplication, 280 animal keywords
  // 3 - Fixed gallery loading on fresh install, improved mounted checks
  // 4 - Stricter tier2 logic (needs body parts), eyelash moved to ambiguous,
  //     reduced concurrency for less heating, per-photo scan version tracking
  // 5 - Improved classification: event/party/pattern exclusions, body part detection,
  //     animal exclusions (vehicle/room/screenshot/instruments), cat+dog deduplication
  // 6 - Room/furniture not documents, baby in costume → people, UI fixes
  // 7 - Dog requires 0.85+ confidence (massive over-detection fix)
  // 8 - Detections now store confidence (Label:0.72 format), search filters
  //     low-confidence tags (<65%) so false positives like "flower" on food don't match
  // 9 - Pedestrian/walker/jogger → People, 2+ clothing items → People,
  //     Screenshots with text → Other (not Scenery), search threshold 0.72
  // 10 - Objects need 86%+ confidence to be searchable, cached tag counts,
  //      Food is category-only (derived from food items)

  /// Current scan logic version - defined in AppConfig
  /// Increment AppConfig.scanLogicVersion when classification logic changes
  static int get scanLogicVersion => AppConfig.scanLogicVersion;

  static const String _scanVersionKey = 'scan_logic_version';

  /// Get the saved scan logic version (returns 0 if never scanned)
  static Future<int> getSavedScanVersion() async {
    final prefs = await SharedPreferences.getInstance();
    // Try new int key first, then migrate from old string format
    final intVersion = prefs.getInt(_scanVersionKey);
    if (intVersion != null) return intVersion;

    // Migration: convert old "0.9" or "1.0" format to int
    final oldVersion = prefs.getString('scan_minor_version');
    if (oldVersion != null && oldVersion.isNotEmpty) {
      // "0.9" → 9, "1.0" → 10, etc.
      final parts = oldVersion
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      final major = parts.isNotEmpty ? parts[0] : 0;
      final minor = parts.length > 1 ? parts[1] : 0;
      return major * 10 + minor; // "1.0" = 10, "0.9" = 9
    }
    return 0; // Never scanned
  }

  /// Save the current scan logic version after a scan completes
  static Future<void> saveScanVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scanVersionKey, scanLogicVersion);
  }

  /// Check if a rescan is needed due to logic changes
  static Future<bool> needsRescanForNewLogic() async {
    final savedVersion = await getSavedScanVersion();
    if (savedVersion == 0) return false; // First time user, no rescan needed
    return scanLogicVersion > savedVersion;
  }

  /// Get description of what changed between versions
  static String getScanVersionChanges(int fromVersion) {
    final changes = <String>[];

    // Add changes for each version upgrade
    if (fromVersion < 2) {
      changes.add('• Improved people detection (tier-based system)');
      changes.add('• Smarter animal identification');
      changes.add('• Better food/flower classification');
    }
    if (fromVersion < 4) {
      changes.add('• Stricter people detection (requires body evidence)');
      changes.add('• Fixed false positives for eyelash/clothing photos');
    }
    if (fromVersion < 5) {
      changes.add('• Events/parties no longer auto-tag as people');
      changes.add('• Better animal detection');
    }
    if (fromVersion < 7) {
      changes.add('• Fixed dog over-detection (requires 85%+ confidence)');
    }
    if (fromVersion < 10) {
      changes.add('• Objects need 86%+ confidence to be searchable');
      changes.add('• Improved category accuracy');
    }

    return changes.isEmpty ? 'Bug fixes and improvements' : changes.join('\n');
  }
}
