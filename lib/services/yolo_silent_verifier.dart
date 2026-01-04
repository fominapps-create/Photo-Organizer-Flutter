import 'dart:io';
import 'dart:developer' as developer;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'tag_store.dart';

/// YOLO verification status for photos classified as "Other"
/// Stored in SharedPreferences for persistence across app restarts
enum YoloStatus {
  pending, // Not yet verified by YOLO
  verified, // YOLO ran and confirmed "other" (no people/animals found)
  reclassified, // YOLO found something and reclassified
  notNeeded, // Photo category doesn't need YOLO verification
}

/// Silent background YOLO verifier
///
/// Runs YOLO on photos classified as "Other" or "Scenery" by ML Kit.
/// Completely non-blocking:
/// - Lazy loads YOLO model only when verification starts
/// - Runs with long delays between photos (1.5s+) to be invisible
/// - Never affects startup or main scan performance
/// - Stores verification status per photo
class YoloSilentVerifier {
  // YOLO ONNX session
  static OrtSession? _yoloSession;
  static bool _yoloReady = false;
  static bool _yoloLoading = false;

  // Background verification state
  static final List<_VerificationItem> _queue = [];
  static bool _running = false;
  static int _totalProcessed = 0;
  static int _totalReclassified = 0;

  // Callbacks
  static void Function(
    String photoId,
    String oldCategory,
    String newCategory,
    double confidence,
  )?
  onReclassified;
  static void Function(String photoId, String category)? onVerified;
  static void Function(int processed, int total, int reclassified)? onProgress;

  // Configuration
  static const int _inputSize = 320;
  static const int _delayBetweenPhotosMs =
      1500; // Very slow = completely silent
  static const double _confidenceThreshold = 0.25;
  static const double _animalConfidence = 0.20;

  // YOLO COCO class mapping
  static const Map<int, String> _yoloToCategory = {
    0: 'people', // person
    14: 'animals',
    15: 'animals',
    16: 'animals',
    17: 'animals', // bird, cat, dog, horse
    18: 'animals',
    19: 'animals',
    20: 'animals',
    21: 'animals', // sheep, cow, elephant, bear
    22: 'animals', 23: 'animals', // zebra, giraffe
  };

  /// Queue a photo for background YOLO verification
  static void queueForVerification({
    required String photoId,
    required String imagePath,
    required String mlKitCategory,
  }) {
    // Only queue "other" and "scenery" categories
    if (mlKitCategory != 'other' && mlKitCategory != 'scenery') {
      return;
    }

    _queue.add(
      _VerificationItem(
        photoId: photoId,
        imagePath: imagePath,
        mlKitCategory: mlKitCategory,
      ),
    );

    developer.log(
      '[YOLO Silent] Queued: $photoId ($mlKitCategory) - queue size: ${_queue.length}',
    );
  }

  /// Get number of photos pending verification
  static int get pendingCount => _queue.length;

  /// Check if verification is running
  static bool get isRunning => _running;

  /// Get verification stats
  static int get totalProcessed => _totalProcessed;
  static int get totalReclassified => _totalReclassified;

  /// Start background verification
  /// Call this after the main scan completes
  static Future<void> startVerification() async {
    if (_running) {
      developer.log('[YOLO Silent] Already running');
      return;
    }

    if (_queue.isEmpty) {
      developer.log('[YOLO Silent] Nothing to verify');
      return;
    }

    _running = true;
    _totalProcessed = 0;
    _totalReclassified = 0;
    final totalToProcess = _queue.length;

    developer.log(
      '[YOLO Silent] Starting verification of $totalToProcess photos...',
    );

    // Lazy load YOLO model with extra delays
    if (!_yoloReady && !_yoloLoading) {
      developer.log('[YOLO Silent] Lazy loading YOLO model...');
      await Future.delayed(const Duration(seconds: 3)); // Wait for UI to settle

      try {
        _yoloLoading = true;
        await _initializeYolo();
        _yoloLoading = false;

        await Future.delayed(
          const Duration(seconds: 1),
        ); // Cool down after load
      } catch (e) {
        developer.log('[YOLO Silent] Failed to load YOLO: $e');
        _yoloLoading = false;
        _running = false;
        return;
      }
    }

    // Wait for loading if another call started it
    while (_yoloLoading) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!_yoloReady) {
      developer.log('[YOLO Silent] YOLO not available, aborting');
      _running = false;
      return;
    }

    // Process queue
    while (_queue.isNotEmpty && _running) {
      final item = _queue.removeAt(0);
      _totalProcessed++;

      try {
        // Long delay before inference - completely silent
        await Future.delayed(
          const Duration(milliseconds: _delayBetweenPhotosMs),
        );

        // Check file exists
        final file = File(item.imagePath);
        if (!await file.exists()) {
          developer.log('[YOLO Silent] File missing: ${item.imagePath}');
          continue;
        }

        // Run YOLO
        final result = await _runYolo(item.imagePath);

        // Long delay after inference
        await Future.delayed(
          const Duration(milliseconds: _delayBetweenPhotosMs ~/ 2),
        );

        if (result != null && result.category != item.mlKitCategory) {
          // Reclassified!
          _totalReclassified++;

          developer.log(
            '[YOLO Silent] ✨ Reclassified: ${item.mlKitCategory} → ${result.category} '
            '(${(result.confidence * 100).toInt()}%) - ${item.photoId}',
          );

          // Save new tags
          await TagStore.saveLocalTags(item.photoId, [result.category]);
          await _saveYoloStatus(item.photoId, YoloStatus.reclassified);

          // Callback
          onReclassified?.call(
            item.photoId,
            item.mlKitCategory,
            result.category,
            result.confidence,
          );
        } else {
          // Verified as "other" (YOLO found nothing)
          await _saveYoloStatus(item.photoId, YoloStatus.verified);
          onVerified?.call(item.photoId, item.mlKitCategory);
        }

        // Progress callback
        onProgress?.call(_totalProcessed, totalToProcess, _totalReclassified);

        // Log progress every 10 photos
        if (_totalProcessed % 10 == 0) {
          developer.log(
            '[YOLO Silent] Progress: $_totalProcessed/$totalToProcess '
            '(reclassified: $_totalReclassified)',
          );
        }
      } catch (e) {
        developer.log('[YOLO Silent] Error: $e');
      }
    }

    _running = false;
    developer.log(
      '[YOLO Silent] Complete! Processed $_totalProcessed, reclassified $_totalReclassified',
    );
  }

  /// Stop verification
  static void stopVerification() {
    _queue.clear();
    _running = false;
    developer.log('[YOLO Silent] Stopped');
  }

  /// Clear queue without stopping (for new scan)
  static void clearQueue() {
    _queue.clear();
    _statusCache.clear();
    developer.log('[YOLO Silent] Queue cleared');
  }

  // ============ YOLO Status Persistence ============

  /// In-memory cache for fast synchronous access during scan
  static final Map<String, YoloStatus> _statusCache = {};

  /// Pending status saves (batched for efficiency)
  static final Map<String, YoloStatus> _pendingStatusSaves = {};
  static bool _saveScheduled = false;

  static String _yoloStatusKey(String photoId) => 'yolo_status_$photoId';

  /// Save YOLO status synchronously (caches in memory, persists in batch)
  /// Use this during scan for performance
  static void saveYoloStatusSync(String photoId, YoloStatus status) {
    _statusCache[photoId] = status;
    _pendingStatusSaves[photoId] = status;

    // Schedule batch save if not already scheduled
    if (!_saveScheduled) {
      _saveScheduled = true;
      Future.delayed(const Duration(milliseconds: 500), _flushPendingSaves);
    }
  }

  /// Flush pending status saves to disk
  static Future<void> _flushPendingSaves() async {
    if (_pendingStatusSaves.isEmpty) {
      _saveScheduled = false;
      return;
    }

    final toSave = Map<String, YoloStatus>.from(_pendingStatusSaves);
    _pendingStatusSaves.clear();
    _saveScheduled = false;

    final prefs = await TagStore.getPrefs();
    for (final entry in toSave.entries) {
      await prefs.setInt(_yoloStatusKey(entry.key), entry.value.index);
    }
  }

  /// Ensure all pending status saves are persisted (call after scan completes)
  static Future<void> flushStatusCache() async {
    await _flushPendingSaves();
    developer.log('[YOLO Silent] Status cache flushed to disk');
  }

  static Future<void> _saveYoloStatus(String photoId, YoloStatus status) async {
    _statusCache[photoId] = status;
    final prefs = await TagStore.getPrefs();
    await prefs.setInt(_yoloStatusKey(photoId), status.index);
  }

  /// Load YOLO status for a photo (checks cache first)
  static Future<YoloStatus> loadYoloStatus(String photoId) async {
    // Check cache first
    if (_statusCache.containsKey(photoId)) {
      return _statusCache[photoId]!;
    }

    final prefs = await TagStore.getPrefs();
    final index = prefs.getInt(_yoloStatusKey(photoId));
    if (index == null || index < 0 || index >= YoloStatus.values.length) {
      return YoloStatus.pending;
    }
    final status = YoloStatus.values[index];
    _statusCache[photoId] = status;
    return status;
  }

  /// Load YOLO status for multiple photos
  static Future<Map<String, YoloStatus>> loadYoloStatusBatch(
    List<String> photoIds,
  ) async {
    final prefs = await TagStore.getPrefs();
    final result = <String, YoloStatus>{};

    for (final photoId in photoIds) {
      // Check cache first
      if (_statusCache.containsKey(photoId)) {
        result[photoId] = _statusCache[photoId]!;
        continue;
      }

      final index = prefs.getInt(_yoloStatusKey(photoId));
      if (index != null && index >= 0 && index < YoloStatus.values.length) {
        result[photoId] = YoloStatus.values[index];
        _statusCache[photoId] = result[photoId]!;
      }
    }

    return result;
  }

  /// Get human-readable status text for UI
  static String getStatusText(YoloStatus status) {
    switch (status) {
      case YoloStatus.pending:
        return '⏳ pending yolo';
      case YoloStatus.verified:
        return '✓ yolo verified';
      case YoloStatus.reclassified:
        return '✨ yolo fixed';
      case YoloStatus.notNeeded:
        return '';
    }
  }

  // ============ YOLO Initialization ============

  static Future<void> _initializeYolo() async {
    if (_yoloReady) return;

    final start = DateTime.now();
    try {
      final ort = OnnxRuntime();
      final providers = await ort.getAvailableProviders();

      final sessionOptions = OrtSessionOptions(
        providers: [
          if (providers.contains(OrtProvider.XNNPACK)) OrtProvider.XNNPACK,
          OrtProvider.CPU,
        ],
        intraOpNumThreads: 2, // Low thread count for background work
        useArena: true,
      );

      // Extra yield for UI
      await Future.delayed(const Duration(milliseconds: 50));

      _yoloSession = await ort.createSessionFromAsset(
        'assets/models/yolov8n.onnx',
        options: sessionOptions,
      );

      await Future.delayed(const Duration(milliseconds: 50));

      _yoloReady = true;
      developer.log(
        '[YOLO Silent] Model loaded in ${DateTime.now().difference(start).inMilliseconds}ms',
      );
    } catch (e) {
      developer.log('[YOLO Silent] Failed to initialize: $e');
      rethrow;
    }
  }

  // ============ YOLO Inference ============

  static Future<_YoloResult?> _runYolo(String imagePath) async {
    if (!_yoloReady || _yoloSession == null) return null;

    OrtValue? input;
    Map<String, OrtValue>? outputs;

    try {
      // Preprocess in isolate
      final prepResult = await compute(_preprocessImage, imagePath);
      if (prepResult == null) return null;

      // Yield for UI
      await Future.delayed(const Duration(milliseconds: 16));

      // Run inference
      input = await OrtValue.fromList(prepResult.tensor, [
        1,
        3,
        _inputSize,
        _inputSize,
      ]);
      outputs = await _yoloSession!.run({'images': input});

      // Yield for UI
      await Future.delayed(const Duration(milliseconds: 16));

      // Parse output
      final outputList = await outputs.values.first.asList();
      List<dynamic> rows;
      if (outputList.isNotEmpty && outputList[0] is List) {
        rows = outputList[0] as List;
      } else {
        rows = outputList;
      }

      if (rows.length != 84) {
        input.dispose();
        for (final o in outputs.values) o.dispose();
        return null;
      }

      final numDetections = (rows[0] as List).length;
      final imageArea = prepResult.width * prepResult.height;

      // Find best detection
      String? bestCategory;
      double bestScore = 0;

      for (int i = 0; i < numDetections; i++) {
        final w = (rows[2] as List)[i].toDouble();
        final h = (rows[3] as List)[i].toDouble();

        // Find max class
        double maxClassScore = 0;
        int maxClassId = -1;
        for (int c = 0; c < 80; c++) {
          final score = (rows[4 + c] as List)[i].toDouble();
          if (score > maxClassScore) {
            maxClassScore = score;
            maxClassId = c;
          }
        }

        // Check if mapped to our categories
        final category = _yoloToCategory[maxClassId];
        if (category == null) continue;

        // Check confidence threshold
        final minConf = (maxClassId >= 14 && maxClassId <= 23)
            ? _animalConfidence
            : _confidenceThreshold;
        if (maxClassScore < minConf) continue;

        // Check box size
        final scaleX = prepResult.width / _inputSize;
        final scaleY = prepResult.height / _inputSize;
        final boxArea = w * scaleX * h * scaleY;
        final boxPercent = boxArea / imageArea;
        if (boxPercent < 0.005) continue; // 0.5% minimum

        // Weighted score
        final weightedScore = maxClassScore * boxPercent;
        if (weightedScore > bestScore) {
          bestScore = weightedScore;
          bestCategory = category;
        }
      }

      input.dispose();
      for (final o in outputs.values) o.dispose();

      if (bestCategory != null) {
        return _YoloResult(category: bestCategory, confidence: bestScore);
      }

      return null;
    } catch (e) {
      developer.log('[YOLO Silent] Inference error: $e');
      input?.dispose();
      if (outputs != null) {
        for (final o in outputs.values) o.dispose();
      }
      return null;
    }
  }

  /// Dispose YOLO session
  static Future<void> dispose() async {
    stopVerification();
    _yoloSession?.close();
    _yoloSession = null;
    _yoloReady = false;
  }
}

// ============ Helper Classes ============

class _VerificationItem {
  final String photoId;
  final String imagePath;
  final String mlKitCategory;

  _VerificationItem({
    required this.photoId,
    required this.imagePath,
    required this.mlKitCategory,
  });
}

class _YoloResult {
  final String category;
  final double confidence;

  _YoloResult({required this.category, required this.confidence});
}

class _PreprocessResult {
  final Float32List tensor;
  final int width;
  final int height;

  _PreprocessResult(this.tensor, this.width, this.height);
}

/// Runs on separate isolate - decodes, resizes, normalizes image
_PreprocessResult? _preprocessImage(String imagePath) {
  try {
    final bytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final resized = img.copyResize(image, width: 320, height: 320);

    final tensor = Float32List(3 * 320 * 320);
    for (int y = 0; y < 320; y++) {
      for (int x = 0; x < 320; x++) {
        final p = resized.getPixel(x, y);
        tensor[0 * 320 * 320 + y * 320 + x] = p.rNormalized.toDouble();
        tensor[1 * 320 * 320 + y * 320 + x] = p.gNormalized.toDouble();
        tensor[2 * 320 * 320 + y * 320 + x] = p.bNormalized.toDouble();
      }
    }

    return _PreprocessResult(tensor, image.width, image.height);
  } catch (e) {
    return null;
  }
}
