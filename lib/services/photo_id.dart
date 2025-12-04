import 'dart:io';
import 'package:photo_manager/photo_manager.dart';

/// Helper functions to derive a canonical photoID for different asset/file types.
class PhotoId {
  /// Return a canonical photoID for an [assetOrFile].
  /// - AssetEntity -> asset.id
  /// - File -> Uri.file(path).toString()
  /// - String url (local:$id or file:...) -> normalized form
  static String canonicalId(dynamic assetOrFile) {
    if (assetOrFile is AssetEntity) return assetOrFile.id;
    if (assetOrFile is File) return Uri.file(assetOrFile.path).toString();
    if (assetOrFile is String) {
      final s = assetOrFile;
      if (s.startsWith('local:')) return s.substring('local:'.length);
      if (s.startsWith('file:')) {
        try {
          final parsed = Uri.parse(s);
          final path = parsed.toFilePath();
          return Uri.file(path).toString();
        } catch (_) {
          var raw = s.substring('file:'.length);
          while (raw.startsWith('//')) raw = raw.substring(1);
          return Uri.file(raw).toString();
        }
      }
      return s;
    }
    throw ArgumentError('Cannot derive photoID for $assetOrFile');
  }
}
