import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

/// Manages the trash bin for deleted photos
/// Photos are soft-deleted and stored here for 30 days before permanent deletion
class TrashStore {
  static const String _trashKey = 'photo_trash';
  static const int _retentionDays = 30;

  /// Model for a trashed photo
  static Map<String, dynamic> _createTrashItem(String photoId) {
    return {'id': photoId, 'deletedAt': DateTime.now().toIso8601String()};
  }

  /// Add a photo to trash (by photo URL/ID like "local:assetId" or "file:path")
  static Future<void> moveToTrash(String photoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trashJson = prefs.getString(_trashKey);

      List<Map<String, dynamic>> trash = [];
      if (trashJson != null) {
        final List<dynamic> decoded = json.decode(trashJson);
        trash = decoded.cast<Map<String, dynamic>>();
      }

      developer.log('🗑️ Current trash before add: ${trash.length} items');

      // Add to trash
      trash.add(_createTrashItem(photoId));

      developer.log('🗑️ Trash after add: ${trash.length} items');

      final encoded = json.encode(trash);
      await prefs.setString(_trashKey, encoded);
      developer.log('🗑️ Saved to SharedPreferences: $photoId');

      // Verify it was saved
      final verify = prefs.getString(_trashKey);
      developer.log('🗑️ Verification read: ${verify?.length} chars');
    } catch (e) {
      developer.log('❌ Error moving to trash: $e');
    }
  }

  /// Get all trashed photos (not expired)
  static Future<List<Map<String, dynamic>>> getTrash() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trashJson = prefs.getString(_trashKey);

      if (trashJson == null) return [];

      final List<dynamic> decoded = json.decode(trashJson);
      final List<Map<String, dynamic>> trash = decoded
          .cast<Map<String, dynamic>>();

      // Filter out expired items (older than 30 days)
      final now = DateTime.now();
      final validTrash = trash.where((item) {
        final deletedAt = DateTime.parse(item['deletedAt'] as String);
        final daysInTrash = now.difference(deletedAt).inDays;
        return daysInTrash < _retentionDays;
      }).toList();

      // If we filtered anything out, save the cleaned list
      if (validTrash.length != trash.length) {
        await prefs.setString(_trashKey, json.encode(validTrash));
        developer.log(
          '🧹 Cleaned ${trash.length - validTrash.length} expired items from trash',
        );
      }

      return validTrash;
    } catch (e) {
      developer.log('❌ Error getting trash: $e');
      return [];
    }
  }

  /// Get count of items in trash
  static Future<int> getTrashCount() async {
    final trash = await getTrash();
    return trash.length;
  }

  /// Restore a photo from trash
  static Future<bool> restore(String photoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trashJson = prefs.getString(_trashKey);

      if (trashJson == null) return false;

      final List<dynamic> decoded = json.decode(trashJson);
      final List<Map<String, dynamic>> trash = decoded
          .cast<Map<String, dynamic>>();

      // Remove the item from trash
      trash.removeWhere((item) => item['id'] == photoId);

      await prefs.setString(_trashKey, json.encode(trash));
      developer.log('♻️ Restored from trash: $photoId');
      return true;
    } catch (e) {
      developer.log('❌ Error restoring from trash: $e');
      return false;
    }
  }

  /// Permanently delete a photo from trash
  static Future<bool> permanentlyDelete(String photoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trashJson = prefs.getString(_trashKey);

      if (trashJson == null) return false;

      final List<dynamic> decoded = json.decode(trashJson);
      final List<Map<String, dynamic>> trash = decoded
          .cast<Map<String, dynamic>>();

      // Remove the item from trash
      trash.removeWhere((item) => item['id'] == photoId);

      await prefs.setString(_trashKey, json.encode(trash));
      developer.log('🗑️ Permanently deleted from trash: $photoId');
      return true;
    } catch (e) {
      developer.log('❌ Error permanently deleting from trash: $e');
      return false;
    }
  }

  /// Empty entire trash (permanent delete all)
  static Future<bool> emptyTrash() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_trashKey);
      developer.log('🗑️ Emptied trash');
      return true;
    } catch (e) {
      developer.log('❌ Error emptying trash: $e');
      return false;
    }
  }

  /// Check if a photo is in trash (by photo URL/ID)
  static Future<bool> isInTrash(String photoId) async {
    final trash = await getTrash();
    return trash.any((item) => item['id'] == photoId);
  }

  /// Get set of trashed photo IDs for fast filtering
  static Future<Set<String>> getTrashedIds() async {
    final trash = await getTrash();
    return trash.map((item) => item['id'] as String).toSet();
  }

  /// Clean up expired items (called periodically)
  static Future<void> cleanupExpired() async {
    // getTrash() already filters out expired items and saves the cleaned list
    await getTrash();
  }
}
