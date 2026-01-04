import 'dart:typed_data';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
// ML Kit disabled - using MobileCLIP ONNX
// import 'local_tagging_service.dart';
import 'mobile_clip_service.dart';
import 'semantic_tag_service.dart';
import 'hybrid_tagging_service.dart';
import 'api_service.dart';
import 'dart:convert';

/// Use Hybrid tagging (Face + YOLO + Text) - fast and accurate
const bool _useHybridTags = true;

/// Use MobileCLIP for classification (more accurate than ML Kit)
const bool _useMobileCLIP = false;

/// Use semantic tags (descriptive) instead of just category labels
const bool _useSemanticTags = false;

/// Factory that decides whether to use local (ML Kit) or cloud (API) tagging.
/// Free tier = local on-device processing
/// Premium tier / Server configured = cloud processing
class TaggingServiceFactory {
  /// Cached device concurrency level for foreground scanning
  static int? _cachedConcurrency;

  /// Cached device concurrency level for background scanning (25% slower)
  static int? _cachedBackgroundConcurrency;

  /// Cached optimal thread count for ONNX intra-op
  static int? _cachedIntraOpThreads;

  /// Cached device info
  static int? _cachedCpuCores;
  static int? _cachedRamGB;

  /// Get optimal intra-op thread count for ONNX based on device capabilities
  /// Returns 2-6 depending on device tier
  static Future<int> getOptimalIntraOpThreads() async {
    if (_cachedIntraOpThreads != null) return _cachedIntraOpThreads!;

    await _detectDeviceSpecs();
    final cpuCores = _cachedCpuCores ?? 4;
    final ramGB = _cachedRamGB ?? 4;

    // Thread count based on device tier
    // More cores + RAM = can use more threads effectively
    int threads;
    if (cpuCores >= 8 && ramGB >= 8) {
      // Flagship (S24+, Pixel 8 Pro, etc.)
      threads = 6;
    } else if (cpuCores >= 6 && ramGB >= 6) {
      // Upper mid-range
      threads = 5;
    } else if (cpuCores >= 4 && ramGB >= 4) {
      // Mid-range
      threads = 4;
    } else {
      // Low-end - be conservative
      threads = 2;
    }

    _cachedIntraOpThreads = threads;
    developer.log(
      '📱 Device: $cpuCores cores, ${ramGB}GB RAM → ONNX intra-op threads: $threads',
    );
    return threads;
  }

  /// Detect device specs (CPU cores and RAM)
  static Future<void> _detectDeviceSpecs() async {
    if (_cachedCpuCores != null && _cachedRamGB != null) return;

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

    _cachedCpuCores = cpuCores;
    _cachedRamGB = ramGB;
  }

  /// Cached NNAPI availability
  static bool? _cachedHasNNAPI;

  /// Check if NNAPI is available (for smarter concurrency decisions)
  static Future<bool> hasNNAPISupport() async {
    if (_cachedHasNNAPI != null) return _cachedHasNNAPI!;

    try {
      final ort = OnnxRuntime();
      final providers = await ort.getAvailableProviders();
      _cachedHasNNAPI = providers.contains(OrtProvider.NNAPI);
      developer.log('📱 NNAPI available: $_cachedHasNNAPI');
    } catch (_) {
      _cachedHasNNAPI = false;
    }
    return _cachedHasNNAPI!;
  }

  /// Get optimal concurrency for ML Kit based on device capabilities
  static Future<int> _getOptimalConcurrency({bool isBackground = false}) async {
    // For background scanning, use cached background value if available
    if (isBackground && _cachedBackgroundConcurrency != null) {
      return _cachedBackgroundConcurrency!;
    }
    // For foreground scanning, use cached foreground value if available
    if (!isBackground && _cachedConcurrency != null) {
      return _cachedConcurrency!;
    }

    // Detect device specs (reuses cached values if available)
    await _detectDeviceSpecs();
    final cpuCores = _cachedCpuCores ?? 4;
    final ramGB = _cachedRamGB ?? 4;

    // Determine concurrency based on device tier and tagging mode
    int concurrency;
    if (_useHybridTags) {
      // Hybrid mode uses ONNX YOLO
      // Allow concurrency=2 on decent devices - preprocessing is isolated
      // and ONNX has proper UI yields between images
      if (ramGB >= 6 && cpuCores >= 6) {
        concurrency = isBackground ? 1 : 2;
      } else {
        concurrency = 1;
      }
    } else if (_useSemanticTags || _useMobileCLIP) {
      // ONNX mode: Only allow concurrency=2 on flagship devices with NNAPI
      // - RAM >= 8GB (enough headroom for 2 concurrent inferences)
      // - NNAPI available (GPU/NPU handles memory more efficiently)
      // - 6+ cores
      final hasNNAPI = await hasNNAPISupport();
      if (ramGB >= 8 && cpuCores >= 6 && hasNNAPI) {
        concurrency = isBackground ? 1 : 2; // 2 foreground, 1 background
      } else {
        concurrency = 1; // Serial for safety on other devices
      }
    } else {
      // ML Kit mode: Higher concurrency is fine
      if (ramGB <= 3 || cpuCores <= 4) {
        concurrency = isBackground ? 6 : 8;
      } else if (ramGB <= 6 || cpuCores <= 6) {
        concurrency = isBackground ? 9 : 12;
      } else if (ramGB <= 8 || cpuCores <= 8) {
        concurrency = isBackground ? 12 : 16;
      } else {
        concurrency = isBackground ? 15 : 20;
      }
    }

    final mode = isBackground ? 'background' : 'foreground';
    developer.log(
      '📱 Device: $cpuCores cores, ${ramGB}GB RAM → $mode concurrency: $concurrency',
    );

    if (isBackground) {
      _cachedBackgroundConcurrency = concurrency;
    } else {
      _cachedConcurrency = concurrency;
    }
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

  /// Pre-initialize the tagging service (call during app startup or before scanning)
  /// This loads ONNX models ahead of time to avoid delays during first scan
  static Future<void> warmup() async {
    if (_useHybridTags) {
      developer.log('🔥 Pre-warming HybridTaggingService...');
      final start = DateTime.now();
      try {
        await HybridTaggingService.initialize();
        developer.log(
          '✅ HybridTaggingService ready in ${DateTime.now().difference(start).inMilliseconds}ms',
        );
      } catch (e) {
        developer.log('⚠️ HybridTaggingService warmup error: $e');
      }
    } else if (_useSemanticTags) {
      developer.log('🔥 Pre-warming SemanticTagService...');
      final start = DateTime.now();
      try {
        await SemanticTagService.initialize();
        developer.log(
          '✅ SemanticTagService ready in ${DateTime.now().difference(start).inMilliseconds}ms',
        );
      } catch (e) {
        developer.log('⚠️ SemanticTagService warmup error: $e');
      }
    } else if (_useMobileCLIP) {
      developer.log('🔥 Pre-warming MobileClipService...');
      final start = DateTime.now();
      try {
        await MobileClipService.initialize();
        developer.log(
          '✅ MobileClipService ready in ${DateTime.now().difference(start).inMilliseconds}ms',
        );
      } catch (e) {
        developer.log('⚠️ MobileClipService warmup error: $e');
      }
    }
  }

  /// Tag a batch of images using the appropriate service
  /// Returns: Map of photoID -> tags
  /// [isBackground] - If true, uses reduced concurrency to prevent heating
  static Future<Map<String, TagResult>> tagImageBatch({
    required List<TaggingInput> items,
    bool preferLocal = false,
    bool isBackground = false,
  }) async {
    // If preferLocal is true or server is not available, use local ML Kit
    final useLocal = preferLocal || !(await isServerAvailable());

    if (useLocal) {
      return await _tagWithLocalService(items, isBackground: isBackground);
    } else {
      return await _tagWithCloudService(items);
    }
  }

  /// Process a single image through the appropriate tagging service
  static Future<TagResult> _processSingleImage(
    String photoID,
    String imagePath,
  ) async {
    try {
      // Use Hybrid tagging (Face + YOLO + Text)
      if (_useHybridTags) {
        final hybridResult = await HybridTaggingService.classifyImage(
          imagePath,
        );
        if (hybridResult != null) {
          final confidence = (hybridResult.confidence * 100).toStringAsFixed(0);

          // Build detection list with error info if present
          final detections = <String>[
            '${hybridResult.category} ($confidence%) [${hybridResult.method}]',
            ...hybridResult.allDetections,
          ];

          // Include YOLO error for debugging if category is 'other' or 'error'
          if (hybridResult.error != null) {
            detections.add('⚠️ ${hybridResult.error}');
          }

          return TagResult(
            tags: [hybridResult.category],
            allDetections: detections,
            source: hybridResult.hasError ? 'error' : 'hybrid',
          );
        } else {
          final errorMsg = HybridTaggingService.lastError ?? 'Unknown error';
          final yoloError = HybridTaggingService.lastYoloError;
          developer.log(
            '[Tagging] Hybrid failed for $photoID: $errorMsg (YOLO: $yoloError)',
          );
          return TagResult(
            tags: ['unscanned'],
            allDetections: [
              'Error: $errorMsg',
              if (yoloError != null) '⚠️ YOLO: $yoloError',
            ],
            source: 'error',
          );
        }
      }

      // Use Semantic Tags for descriptive labels
      if (_useSemanticTags) {
        final semanticResult = await SemanticTagService.analyzeImage(imagePath);
        if (semanticResult != null) {
          final topCategory = semanticResult.category;
          final confidence = (semanticResult.categoryConfidence * 100)
              .toStringAsFixed(0);
          return TagResult(
            tags: [topCategory],
            allDetections: ['$topCategory ($confidence%)'],
            source: 'semantic',
          );
        } else {
          final errorMsg = SemanticTagService.lastError ?? 'Unknown error';
          developer.log('[Tagging] SemanticTag failed for $photoID: $errorMsg');
          return TagResult(
            tags: ['unscanned'],
            allDetections: ['Error: $errorMsg'],
            source: 'error',
          );
        }
      }

      // MobileCLIP category-only mode (not semantic)
      if (_useMobileCLIP) {
        final clipResult = await MobileClipService.classifyImage(imagePath);
        if (clipResult != null) {
          return TagResult(
            tags: [clipResult.category],
            allDetections: clipResult.allScores.entries
                .map((e) => '${e.key}:${(e.value * 100).toStringAsFixed(1)}%')
                .toList(),
            source: 'mobileclip',
          );
        } else {
          developer.log('[Tagging] MobileCLIP returned null for $photoID');
          return TagResult(
            tags: ['other'],
            allDetections: ['MobileCLIP failed'],
            source: 'error',
          );
        }
      }

      // No tagging method available
      return TagResult(
        tags: ['other'],
        allDetections: ['No tagger configured'],
        source: 'none',
      );
    } catch (e) {
      developer.log('LocalTagging error for $photoID: $e');
      return TagResult(
        tags: ['other'],
        allDetections: [],
        source: 'local',
        error: e.toString(),
      );
    }
  }

  /// Tag images using on-device ML Kit - PARALLEL processing for speed
  static Future<Map<String, TagResult>> _tagWithLocalService(
    List<TaggingInput> items, {
    bool isBackground = false,
  }) async {
    final results = <String, TagResult>{};

    // Get temp directory for files
    final tempDir = await getTemporaryDirectory();
    final tempDirPath = tempDir.path;
    final tempFilesToDelete = <String>[];

    // For ONNX-based modes (Hybrid/Semantic/CLIP), process SEQUENTIALLY
    // because ONNX blocks main thread - parallel futures just queue up blocking calls.
    // For ML Kit mode, use parallel processing since it's truly async.
    final useSequential = _useHybridTags || _useSemanticTags || _useMobileCLIP;

    if (useSequential) {
      developer.log(
        '🚀 ONNX mode - processing ${items.length} items SEQUENTIALLY for UI responsiveness',
      );
    } else {
      final concurrencyLimit = await _getOptimalConcurrency(
        isBackground: isBackground,
      );
      developer.log(
        '🚀 ML Kit mode - processing with concurrency: $concurrencyLimit',
      );
    }

    try {
      if (useSequential) {
        // SEQUENTIAL PROCESSING for ONNX modes - better UI responsiveness
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          String? tempPath;

          // Write temp file if needed
          if (item.bytes != null) {
            final tempFile = File(
              '$tempDirPath/tag_${DateTime.now().microsecondsSinceEpoch}_${item.photoID.hashCode}.jpg',
            );
            await tempFile.writeAsBytes(item.bytes!, flush: true);
            tempPath = tempFile.path;
            tempFilesToDelete.add(tempPath);
          } else if (item.filePath != null) {
            tempPath = item.filePath;
          }

          if (tempPath == null) {
            results[item.photoID] = TagResult(
              tags: ['other'],
              allDetections: [],
              source: 'local',
            );
            continue;
          }

          // Process single image
          final result = await _processSingleImage(item.photoID, tempPath);
          results[item.photoID] = result;

          // Delete temp file immediately
          if (item.bytes != null && tempPath != null) {
            try {
              await File(tempPath).delete();
              tempFilesToDelete.remove(tempPath);
            } catch (_) {}
          }

          // Yield between items - critical for UI responsiveness with ONNX
          // 50ms gives UI time for ~3 frames at 60fps
          if (i < items.length - 1) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
      } else {
        // PARALLEL PROCESSING for ML Kit mode (truly async)
        final concurrencyLimit = await _getOptimalConcurrency(
          isBackground: isBackground,
        );

        for (var i = 0; i < items.length; i += concurrencyLimit) {
          final chunk = items.skip(i).take(concurrencyLimit).toList();
          final chunkTempFiles = <String>[];

          // Process chunk in parallel
          final futures = chunk.map((item) async {
            try {
              String? tempPath;

              // ML Kit/MobileCLIP needs a file path, so write bytes to temp file if needed
              if (item.bytes != null) {
                final tempFile = File(
                  '$tempDirPath/tag_${DateTime.now().microsecondsSinceEpoch}_${item.photoID.hashCode}.jpg',
                );
                await tempFile.writeAsBytes(item.bytes!, flush: true);
                tempPath = tempFile.path;
                chunkTempFiles.add(tempPath);

                // Debug: Log temp file size on first write
                if (chunkTempFiles.length == 1) {
                  final size = await tempFile.length();
                  developer.log(
                    '[Tagging] Temp file: ${item.bytes!.length} bytes in memory, $size bytes on disk',
                  );
                }
              } else if (item.filePath != null) {
                tempPath = item.filePath;
              }

              if (tempPath == null) {
                return MapEntry(
                  item.photoID,
                  TagResult(
                    tags: ['other'],
                    allDetections: [],
                    source: 'local',
                  ),
                );
              }

              return MapEntry(
                item.photoID,
                await _processSingleImage(item.photoID, tempPath),
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

          // Let UI breathe between chunks
          await Future.delayed(const Duration(milliseconds: 50));

          // Delete chunk temp files immediately after chunk completes
          for (final path in chunkTempFiles) {
            try {
              await File(path).delete();
            } catch (_) {
              tempFilesToDelete.add(path);
            }
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
