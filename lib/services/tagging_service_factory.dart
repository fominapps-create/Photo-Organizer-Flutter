import 'dart:typed_data';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'local_tagging_service.dart';
import 'api_service.dart';
import 'dart:convert';

/// Factory that decides whether to use local (ML Kit) or cloud (API) tagging.
/// Free tier = local on-device processing
/// Premium tier / Server configured = cloud processing
class TaggingServiceFactory {
  /// Cached device concurrency level
  static int? _cachedConcurrency;

  /// Get optimal concurrency for ML Kit based on device capabilities
  static Future<int> _getOptimalConcurrency() async {
    if (_cachedConcurrency != null) return _cachedConcurrency!;

    int cpuCores = 4;
    int ramGB = 4;

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isLinux)) {
        // Read CPU cores
        try {
          final cpuInfo = await File('/proc/cpuinfo').readAsString();
          final processors = cpuInfo
              .split('\n')
              .where((line) => line.startsWith('processor'))
              .length;
          if (processors > 0) cpuCores = processors;
        } catch (_) {}

        // Read RAM
        try {
          final memInfo = await File('/proc/meminfo').readAsString();
          final memTotalLine = memInfo
              .split('\n')
              .firstWhere(
                (line) => line.startsWith('MemTotal:'),
                orElse: () => '',
              );
          if (memTotalLine.isNotEmpty) {
            final memKB = int.tryParse(
              memTotalLine.replaceAll(RegExp(r'[^0-9]'), ''),
            );
            if (memKB != null) {
              ramGB = (memKB / 1024 / 1024).ceil();
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    // Determine concurrency based on device tier
    // Higher concurrency = more parallel ML Kit operations = faster scanning
    int concurrency;
    if (ramGB <= 3 || cpuCores <= 4) {
      concurrency = 8; // Low-end: 8 parallel operations
    } else if (ramGB <= 6 || cpuCores <= 6) {
      concurrency = 12; // Mid-range: 12 parallel operations
    } else if (ramGB <= 8 || cpuCores <= 8) {
      concurrency = 16; // Mid-high: 16 parallel operations
    } else {
      concurrency = 20; // High-end: 20 parallel operations
    }

    developer.log(
      '📱 Device: $cpuCores cores, ${ramGB}GB RAM → concurrency: $concurrency',
    );
    _cachedConcurrency = concurrency;
    return concurrency;
  }

  /// Check if server is available and configured
  static Future<bool> isServerAvailable() async {
    final baseUrl = ApiService.baseUrl;
    if (baseUrl.isEmpty) return false;

    try {
      return await ApiService.pingServer(timeout: const Duration(seconds: 2));
    } catch (e) {
      return false;
    }
  }

  /// Tag a batch of images using the appropriate service
  /// Returns: Map of photoID -> tags
  static Future<Map<String, TagResult>> tagImageBatch({
    required List<TaggingInput> items,
    bool preferLocal = false,
  }) async {
    // If preferLocal is true or server is not available, use local ML Kit
    final useLocal = preferLocal || !(await isServerAvailable());

    if (useLocal) {
      return await _tagWithLocalService(items);
    } else {
      return await _tagWithCloudService(items);
    }
  }

  /// Tag images using on-device ML Kit - PARALLEL processing for speed
  static Future<Map<String, TagResult>> _tagWithLocalService(
    List<TaggingInput> items,
  ) async {
    final results = <String, TagResult>{};

    // Get temp directory for files
    final tempDir = await getTemporaryDirectory();
    final tempDirPath = tempDir.path;
    final tempFilesToDelete = <String>[];

    // Dynamic concurrency based on device capabilities
    // Higher concurrency = faster processing, but more memory/CPU
    // ML Kit is well-optimized and can handle high concurrency on modern devices
    final concurrencyLimit = await _getOptimalConcurrency();
    developer.log(
      '🚀 Local ML Kit processing with concurrency: $concurrencyLimit',
    );

    try {
      // Process items in chunks for controlled parallelism
      for (var i = 0; i < items.length; i += concurrencyLimit) {
        final chunk = items.skip(i).take(concurrencyLimit).toList();
        final chunkTempFiles = <String>[];

        // Process chunk in parallel
        final futures = chunk.map((item) async {
          try {
            String? tempPath;

            // ML Kit needs a file path, so write bytes to temp file if needed
            if (item.bytes != null) {
              final tempFile = File(
                '$tempDirPath/tag_${DateTime.now().microsecondsSinceEpoch}_${item.photoID.hashCode}.jpg',
              );
              await tempFile.writeAsBytes(item.bytes!, flush: false);
              tempPath = tempFile.path;
              chunkTempFiles.add(tempPath);
            } else if (item.filePath != null) {
              tempPath = item.filePath;
            }

            if (tempPath == null) {
              return MapEntry(
                item.photoID,
                TagResult(tags: ['other'], allDetections: [], source: 'local'),
              );
            }

            // Use the new method that returns both tags and detections
            final localResult =
                await LocalTaggingService.classifyImageWithDetections(tempPath);

            return MapEntry(
              item.photoID,
              TagResult(
                tags: localResult.tags,
                allDetections: localResult.allDetections,
                source: 'local',
              ),
            );
          } catch (e) {
            developer.log('LocalTagging error for ${item.photoID}: $e');
            return MapEntry(
              item.photoID,
              TagResult(
                tags: ['other'],
                allDetections: [],
                source: 'local',
                error: e.toString(),
              ),
            );
          }
        });

        // Wait for chunk to complete
        final chunkResults = await Future.wait(futures);
        for (final entry in chunkResults) {
          results[entry.key] = entry.value;
        }

        // Delete chunk temp files immediately after chunk completes
        for (final path in chunkTempFiles) {
          try {
            await File(path).delete();
          } catch (_) {
            tempFilesToDelete.add(path); // Track for final cleanup
          }
        }
      }
    } finally {
      // Final cleanup pass for any files that failed to delete
      for (final path in tempFilesToDelete) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }

    return results;
  }

  /// Tag images using cloud API
  static Future<Map<String, TagResult>> _tagWithCloudService(
    List<TaggingInput> items,
  ) async {
    final results = <String, TagResult>{};

    try {
      // Prepare batch items for API
      final batchItems = items
          .where((item) => item.bytes != null)
          .map((item) => {'file': item.bytes, 'photoID': item.photoID})
          .toList();

      if (batchItems.isEmpty) {
        return results;
      }

      final res = await ApiService.uploadImagesBatch(batchItems);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = json.decode(res.body);

        if (body is Map && body['results'] is List) {
          final apiResults = body['results'] as List;

          for (var i = 0; i < apiResults.length && i < items.length; i++) {
            final result = apiResults[i];
            final item = items[i];

            List<String> tags = [];
            List<String> allDetections = [];

            if (result is Map && result['tags'] is List) {
              tags = (result['tags'] as List).cast<String>();
            }
            if (result is Map && result['all_detections'] is List) {
              allDetections = (result['all_detections'] as List).cast<String>();
            } else {
              allDetections = List.from(tags);
            }

            results[item.photoID] = TagResult(
              tags: tags,
              allDetections: allDetections,
              source: 'cloud',
            );
          }
        }
      } else {
        // Server error - fall back to local
        developer.log(
          'Cloud tagging failed (${res.statusCode}), falling back to local',
        );
        return await _tagWithLocalService(items);
      }
    } catch (e) {
      developer.log('Cloud tagging error: $e, falling back to local');
      return await _tagWithLocalService(items);
    }

    return results;
  }
}

/// Input for tagging a single image
class TaggingInput {
  final String photoID;
  final Uint8List? bytes;
  final String? filePath;

  TaggingInput({required this.photoID, this.bytes, this.filePath});
}

/// Result from tagging
class TagResult {
  final List<String> tags;
  final List<String> allDetections;
  final String source; // 'local' or 'cloud'
  final String? error;

  TagResult({
    required this.tags,
    required this.allDetections,
    required this.source,
    this.error,
  });
}
