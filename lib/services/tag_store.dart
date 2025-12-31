import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TagStore {
  static String _keyFor(String photoID) => 'tags_$photoID';
  static String _detectionsKeyFor(String photoID) => 'detections_$photoID';
  static String _scanVersionKeyFor(String photoID) => 'scanver_$photoID';

  /// Save tags locally under canonical `photoID`.
  static Future<void> saveLocalTags(String photoID, List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(photoID), json.encode(tags));
    // Also save the current scan version when tags are saved
    await prefs.setString(_scanVersionKeyFor(photoID), scanMinorVersion);
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
  static Future<String?> loadPhotoScanVersion(String photoID) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_scanVersionKeyFor(photoID));
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

  /// Load all scan versions at once for multiple photos (batch loading)
  /// Returns a Map of photoID -> scanVersion
  static Future<Map<String, String>> loadAllScanVersionsMap(
    List<String> photoIDs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String>{};

    for (final photoID in photoIDs) {
      final ver = prefs.getString(_scanVersionKeyFor(photoID));
      if (ver != null) {
        result[photoID] = ver;
      }
    }

    return result;
  }

  // ============ Scan Version Tracking (Hybrid Approach) ============
  //
  // VERSIONING CONVENTION:
  // - Uses MINOR version from app version (e.g., "0.2" from "0.2.8")
  // - Triggers rescan on MINOR version change (0.2.x → 0.3.x)
  // - Triggers rescan on MAJOR version change (0.x → 1.x, 1.x → 2.x)
  // - Patch versions (0.2.8 → 0.2.9) do NOT trigger rescan
  //
  // WHEN TO UPDATE scanMinorVersion:
  // - Changed ML Kit confidence thresholds
  // - Added/removed keywords from detection lists
  // - Modified tier-based logic (people/animals/food)
  // - Changed category mapping rules
  // - Major version releases (1.0, 2.0, etc.)
  //
  // WHEN NOT TO UPDATE:
  // - UI changes, bug fixes unrelated to scanning
  // - Performance optimizations that don't change results
  // - New features that don't affect existing photo tags
  //
  // VERSION HISTORY:
  // "0.1" - Initial ML Kit implementation
  // "0.2" - Tier-based people detection, animal deduplication, 280 animal keywords
  // "0.3" - Fixed gallery loading on fresh install, improved mounted checks
  // "0.4" - Stricter tier2 logic (needs body parts), eyelash moved to ambiguous,
  //         reduced concurrency for less heating, per-photo scan version tracking
  // "0.5" - Improved classification: event/party/pattern exclusions, body part detection,
  //         animal exclusions (vehicle/room/screenshot/instruments), cat+dog deduplication
  // "0.6" - Room/furniture not documents, baby in costume → people, UI fixes
  // "0.7" - Dog requires 0.85+ confidence (massive over-detection fix)

  /// Current scan logic version (minor version only)
  /// Update this when classification logic changes significantly
  static const String scanMinorVersion = '0.7';

  static const String _scanVersionKey = 'scan_minor_version';

  /// Get the scan version that was used for the last scan
  static Future<String> getSavedScanVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_scanVersionKey) ??
        ''; // empty = never scanned or pre-versioning
  }

  /// Save the current scan version after a scan completes
  static Future<void> saveScanVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scanVersionKey, scanMinorVersion);
  }

  /// Check if a rescan is needed due to logic changes
  /// Triggers rescan when:
  /// - Minor version changes (0.2 → 0.3)
  /// - Major version changes (0.x → 1.x, 1.x → 2.x)
  static Future<bool> needsRescanForNewLogic() async {
    final savedVersion = await getSavedScanVersion();
    if (savedVersion.isEmpty) return false; // First time user, no rescan needed

    // Parse versions
    final savedParts = savedVersion
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final currentParts = scanMinorVersion
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();

    final savedMajor = savedParts.isNotEmpty ? savedParts[0] : 0;
    final savedMinor = savedParts.length > 1 ? savedParts[1] : 0;
    final currentMajor = currentParts.isNotEmpty ? currentParts[0] : 0;
    final currentMinor = currentParts.length > 1 ? currentParts[1] : 0;

    // Rescan if major version changed (0.x → 1.x, 1.x → 2.x, etc.)
    if (currentMajor > savedMajor) return true;

    // Rescan if minor version changed within same major (0.2 → 0.3, 1.0 → 1.1)
    if (currentMajor == savedMajor && currentMinor > savedMinor) return true;

    return false;
  }

  /// Get description of what changed between versions
  static String getScanVersionChanges(String fromVersion) {
    final changes = <String>[];

    // Parse versions for comparison
    final fromParts = fromVersion
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final fromMajor = fromParts.isNotEmpty ? fromParts[0] : 0;
    final fromMinor = fromParts.length > 1 ? fromParts[1] : 0;

    final toParts = scanMinorVersion
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final toMajor = toParts.isNotEmpty ? toParts[0] : 0;

    // Major version upgrade gets special messaging
    if (toMajor > fromMajor) {
      changes.add('🎉 Major update with redesigned classification!');
      changes.add('• All-new scanning engine');
      changes.add('• Significantly improved accuracy');
    }

    // Add changes for each version upgrade
    if (fromMajor == 0 && fromMinor < 2) {
      changes.add('• Improved people detection (tier-based system)');
      changes.add('• Smarter animal identification');
      changes.add('• Better food/flower classification');
      changes.add('• Expanded animal keyword coverage (280+ animals)');
    }
    if (fromMajor == 0 && fromMinor < 4) {
      changes.add('• Stricter people detection (requires body evidence)');
      changes.add('• Fixed false positives for eyelash/clothing photos');
      changes.add('• Reduced phone heating during scans');
    }
    if (fromMajor == 0 && fromMinor < 5) {
      changes.add('• Events/parties no longer auto-tag as people');
      changes.add('• Better animal detection (excludes objects/body parts)');
      changes.add('• Fixed scan startup when updating app');
      changes.add('• Improved people detection for body parts');
    }
    // Future version changes go here:
    // if (fromMajor < 1) {
    //   changes.add('• [v1.0 major improvements]');
    // }

    return changes.isEmpty ? 'Bug fixes and improvements' : changes.join('\n');
  }
}
