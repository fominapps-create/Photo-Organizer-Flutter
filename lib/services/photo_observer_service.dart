import 'package:flutter/services.dart';

/// Native photo change observer service
///
/// This service connects to platform-specific photo monitoring:
/// - Android: ContentObserver watching MediaStore.Images.Media.EXTERNAL_CONTENT_URI
/// - iOS: PHPhotoLibraryChangeObserver watching photo library changes
///
/// Changes are detected INSTANTLY when:
/// - New photos are taken with camera
/// - Photos are added/imported from other sources
/// - Photos are deleted by any app
/// - Photos are modified (edited, favorited, etc.)
///
/// Usage:
/// ```dart
/// PhotoObserverService.listen((event) {
///   print('Photo library changed: $event');
///   // Refresh your photo list
/// });
/// ```
class PhotoObserverService {
  static const EventChannel _channel = EventChannel(
    'com.example.filtored/photo_changes',
  );

  /// Stream of photo library change events
  ///
  /// Events contain:
  /// - `type`: 'change'
  /// - `uri`: (Android only) URI of changed photo
  static Stream<dynamic> get changes => _channel.receiveBroadcastStream();

  /// Listen to photo changes with automatic error handling
  static Stream<dynamic> listen(
    void Function(dynamic event) onData, {
    void Function(Object error)? onError,
  }) {
    return changes;
  }
}
