import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'tagging_service_factory.dart';

/// Optimized hybrid tagging service:
/// 1. YOLO object detection (people, animals, food) - always runs
/// 2. ML Kit ImageLabeler (scenery only) - lazy-loaded fallback when YOLO finds nothing
///
/// Removed for performance:
/// - Face detection: YOLO already detects people reliably
/// - Text recognition: Too aggressive, tags screenshots as documents
class HybridTaggingService {
  // YOLO ONNX
  static OrtSession? _yoloSession;
  static bool _yoloReady = false;

  // ML Kit ImageLabeler - lazy loaded only when needed for scenery
  static ImageLabeler? _imageLabeler;
  static bool _labelerInitialized = false;

  static String? lastError;
  static String? lastYoloError; // Detailed YOLO-specific error for debugging

  // Debug: Log first inference details
  static bool _firstInferenceLogged = false;

  // YOLO input size - matches the exported ONNX model (320x320)
  static const int _yoloInputSize = 320;
  // Output shape is [1, 84, 2100] for 320x320 input
  static const int _yoloNumDetections = 2100;

  // YOLO COCO class mapping to our categories
  static const Map<int, String> _yoloToCategory = {
    // PEOPLE
    0: 'people', // person
    // ANIMALS
    14: 'animals', // bird
    15: 'animals', // cat
    16: 'animals', // dog
    17: 'animals', // horse
    18: 'animals', // sheep
    19: 'animals', // cow
    20: 'animals', // elephant
    21: 'animals', // bear
    22: 'animals', // zebra
    23: 'animals', // giraffe
    // FOOD (actual food items only)
    46: 'food', // banana
    47: 'food', // apple
    48: 'food', // sandwich
    49: 'food', // orange
    50: 'food', // broccoli
    51: 'food', // carrot
    52: 'food', // hot dog
    53: 'food', // pizza
    54: 'food', // donut
    55: 'food', // cake
  };

  // Priority for tie-breaking (higher = wins)
  static const Map<String, int> _categoryPriority = {
    'people': 4,
    'animals': 3,
    'food': 2,
    'documents': 1,
    'scenery': 0,
    'other': 0,
  };

  // Confidence thresholds - lowered for better detection on thumbnails
  static const double _yoloConfidence = 0.35; // Was 0.5
  static const double _animalConfidence = 0.30; // Was 0.45
  static const double _foodConfidence = 0.45; // Was 0.6
  static const double _minBoxPercent = 0.01; // 1% of image minimum (was 2%)

  // Scenery keywords for ML Kit ImageLabeler fallback
  static const Set<String> _sceneryKeywords = {
    'landscape',
    'scenery',
    'nature',
    'outdoor',
    'sky',
    'cloud',
    'mountain',
    'hill',
    'valley',
    'forest',
    'tree',
    'garden',
    'park',
    'beach',
    'ocean',
    'sea',
    'lake',
    'river',
    'waterfall',
    'sunset',
    'sunrise',
    'dawn',
    'dusk',
    'night',
    'star',
    'moon',
    'city',
    'street',
    'road',
    'bridge',
    'castle',
    'church',
    'temple',
    'monument',
    'field',
    'meadow',
    'desert',
    'snow',
    'ice',
    'horizon',
    'view',
    'panorama',
    'aerial',
  };

  // Weak scenery labels that shouldn't trigger scenery category alone
  static const Set<String> _weakSceneryKeywords = {
    'building',
    'architecture',
    'room',
    'interior',
    'shelf',
    'store',
    'shop',
    'furniture',
    'wall',
    'floor',
    'ceiling',
    'window',
    'door',
  };

  static bool get isReady => _yoloReady;

  /// Initialize YOLO only - ML Kit ImageLabeler is lazy-loaded when needed
  static Future<void> initialize() async {
    if (_yoloReady) return;

    final start = DateTime.now();
    try {
      final ort = OnnxRuntime();
      final providers = await ort.getAvailableProviders();

      // Get optimal thread count based on device capabilities (2-6 threads)
      final intraOpThreads =
          await TaggingServiceFactory.getOptimalIntraOpThreads();

      final sessionOptions = OrtSessionOptions(
        providers: [
          if (providers.contains(OrtProvider.XNNPACK)) OrtProvider.XNNPACK,
          OrtProvider.CPU,
        ],
        intraOpNumThreads: intraOpThreads,
        useArena: true, // Memory arena for faster allocation
      );

      _yoloSession = await ort.createSessionFromAsset(
        'assets/models/yolov8n.onnx',
        options: sessionOptions,
      );

      _yoloReady = true;
      developer.log(
        '[Hybrid] YOLO ready in ${DateTime.now().difference(start).inMilliseconds}ms',
      );
    } catch (e) {
      lastError = e.toString();
      developer.log('[Hybrid] Init failed: $e');
      rethrow;
    }
  }

  /// Lazy-initialize ML Kit ImageLabeler (only when YOLO finds nothing)
  static Future<void> _initializeLabeler() async {
    if (_labelerInitialized) return;

    try {
      _imageLabeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.5),
      );
      _labelerInitialized = true;
    } catch (e) {
      developer.log('[Hybrid] ImageLabeler init failed: $e');
    }
  }

  /// Main classification method
  static Future<HybridTagResult?> classifyImage(String imagePath) async {
    if (!_yoloReady) {
      await initialize();
      if (!_yoloReady) {
        return HybridTagResult(
          category: 'error',
          confidence: 0.0,
          method: 'error',
          timings: {},
          error: 'YOLO init failed: ${lastError ?? "Unknown"}',
        );
      }
    }

    // Double-check session is valid
    if (_yoloSession == null) {
      return HybridTagResult(
        category: 'error',
        confidence: 0.0,
        method: 'error',
        timings: {},
        error: 'YOLO session is null after init',
      );
    }

    final timings = <String, int>{};
    final stopwatch = Stopwatch();

    try {
      // Step 1: YOLO Object Detection (people, animals, food)
      stopwatch.start();
      final yoloResult = await _runYolo(imagePath);
      stopwatch.stop();
      timings['yolo'] = stopwatch.elapsedMilliseconds;

      if (yoloResult != null) {
        return HybridTagResult(
          category: yoloResult.category,
          confidence: yoloResult.confidence,
          method: 'yolo',
          timings: timings,
          allDetections: yoloResult.allDetections,
        );
      }

      // Step 2: YOLO found nothing → try ML Kit ImageLabeler for scenery
      stopwatch.reset();
      stopwatch.start();

      await _initializeLabeler();
      if (_imageLabeler != null) {
        // Yield to let UI render before ML Kit processing
        await Future.delayed(const Duration(milliseconds: 16));

        final inputImage = InputImage.fromFilePath(imagePath);
        final labels = await _imageLabeler!.processImage(inputImage);

        // Yield to let UI render after ML Kit processing
        await Future.delayed(const Duration(milliseconds: 16));
        stopwatch.stop();
        timings['labeler'] = stopwatch.elapsedMilliseconds;

        // Check for scenery keywords
        int strongSceneryCount = 0;
        final allDetections = <String>[];

        for (final label in labels) {
          final text = label.label.toLowerCase();
          final conf = (label.confidence * 100).toInt();
          allDetections.add('$text:$conf%');

          if (_sceneryKeywords.contains(text) &&
              !_weakSceneryKeywords.contains(text) &&
              label.confidence >= 0.5) {
            strongSceneryCount++;
          }
        }

        // Need 2+ strong scenery labels to classify as scenery
        if (strongSceneryCount >= 2) {
          return HybridTagResult(
            category: 'scenery',
            confidence: 0.75,
            method: 'labeler',
            timings: timings,
            allDetections: allDetections,
          );
        }

        // ML Kit ran but didn't find scenery - pass detections for debugging
        // and return 'other' with ML Kit's findings
        return HybridTagResult(
          category: 'other',
          confidence: 0.5,
          method: 'fallback',
          timings: timings,
          allDetections: allDetections,
          error: lastYoloError, // Include YOLO error for debugging
        );
      } else {
        stopwatch.stop();
        timings['labeler'] = stopwatch.elapsedMilliseconds;
      }

      // Step 3: Nothing matched and no ML Kit → other
      // Include YOLO error info if available for debugging
      return HybridTagResult(
        category: 'other',
        confidence: 0.5,
        method: 'fallback',
        timings: timings,
        error: lastYoloError, // Pass YOLO error for debugging
      );
    } catch (e, st) {
      lastError = e.toString();
      developer.log('[Hybrid] Error: $e\n$st');
      // Return error result instead of null so UI can display it
      return HybridTagResult(
        category: 'error',
        confidence: 0.0,
        method: 'error',
        timings: timings,
        error: 'Hybrid error: $e',
      );
    }
  }

  /// Run YOLO inference with size-based priority logic
  static Future<_YoloDetection?> _runYolo(String imagePath) async {
    OrtValue? input;
    Map<String, OrtValue>? outputs;

    try {
      // Check if file exists first
      final file = File(imagePath);
      if (!await file.exists()) {
        lastYoloError = 'YOLO: File not found at $imagePath';
        developer.log('[YOLO] $lastYoloError');
        return null;
      }

      // Check file size
      final fileSize = await file.length();
      if (fileSize == 0) {
        lastYoloError = 'YOLO: File is empty (0 bytes) at $imagePath';
        developer.log('[YOLO] $lastYoloError');
        return null;
      }

      // Step 1: Preprocess image in separate isolate (won't block UI)
      final prepResult = await compute(_preprocessImageIsolate, imagePath);
      if (prepResult == null) {
        lastYoloError =
            'YOLO preprocess failed: Could not decode image ($fileSize bytes) at $imagePath';
        developer.log('[YOLO] $lastYoloError');
        return null;
      }

      final tensor = prepResult.tensor;
      final imageWidth = prepResult.width;
      final imageHeight = prepResult.height;
      final imageArea = imageWidth * imageHeight;

      // Yield to let UI render a frame before inference
      // Longer delay to give UI time for multiple frames
      await Future.delayed(const Duration(milliseconds: 16));

      // Step 2: Run ONNX inference (this is the heavy part that blocks main thread)
      input = await OrtValue.fromList(tensor, [
        1,
        3,
        _yoloInputSize,
        _yoloInputSize,
      ]);
      outputs = await _yoloSession!.run({'images': input});

      // Yield to let UI render after inference
      await Future.delayed(const Duration(milliseconds: 16));

      // Step 3: Parse YOLO output
      // Expected shape: [1, 84, 2100] where 84 = 4 (box) + 80 (classes)
      final outputList = await outputs.values.first.asList();

      // Unwrap the batch dimension: outputList is [batch] -> [84 rows] -> [2100 values each]
      List<dynamic> rows;
      if (outputList.isNotEmpty && outputList[0] is List) {
        rows = outputList[0] as List;
      } else {
        rows = outputList;
      }

      // Validate we have 84 rows
      if (rows.length != 84) {
        developer.log(
          '[YOLO] Unexpected output shape: rows.length=${rows.length}, expected 84',
        );
        input.dispose();
        for (final o in outputs.values) o.dispose();
        return null;
      }

      // Get the number of detections from the first row
      final firstRow = rows[0] as List;
      final numDetections = firstRow.length;

      // Debug: Log first inference details
      if (!_firstInferenceLogged) {
        _firstInferenceLogged = true;
        developer.log(
          '[YOLO] First inference - numDetections: $numDetections, imageSize: ${imageWidth}x$imageHeight',
        );
        // Sample some raw values to verify model output
        if (numDetections > 0) {
          final sampleScores = <String>[];
          for (int c = 0; c < 80 && c < 10; c++) {
            final score = (rows[4 + c] as List)[0].toDouble();
            if (score > 0.1) {
              sampleScores.add('class$c:${(score * 100).toStringAsFixed(1)}%');
            }
          }
          developer.log(
            '[YOLO] Sample scores (first detection): $sampleScores',
          );
        }
      }

      // Debug: Track what YOLO actually sees (top 5 scores across all classes)
      final debugTopScores = <String>[];
      double maxScoreFound = 0;
      int maxClassIdFound = -1;

      // Category scores with weighted scoring
      final categoryScores = <String, double>{};
      final allDetections = <String>[];

      for (int i = 0; i < numDetections; i++) {
        // Get box coordinates (first 4 rows)
        final cx = (rows[0] as List)[i].toDouble();
        final cy = (rows[1] as List)[i].toDouble();
        final w = (rows[2] as List)[i].toDouble();
        final h = (rows[3] as List)[i].toDouble();

        // Find max class score (rows 4-83 = 80 classes)
        double maxClassScore = 0;
        int maxClassId = -1;
        for (int c = 0; c < 80; c++) {
          final score = (rows[4 + c] as List)[i].toDouble();
          if (score > maxClassScore) {
            maxClassScore = score;
            maxClassId = c;
          }
        }

        // Track overall highest score for debugging
        if (maxClassScore > maxScoreFound) {
          maxScoreFound = maxClassScore;
          maxClassIdFound = maxClassId;
        }

        // Check if this class maps to our categories
        final category = _yoloToCategory[maxClassId];
        if (category == null) continue;

        // Apply category-specific confidence thresholds
        double minConf = _yoloConfidence;
        if (maxClassId >= 14 && maxClassId <= 23) {
          minConf = _animalConfidence;
        } else if (maxClassId >= 46 && maxClassId <= 55) {
          minConf = _foodConfidence;
        }

        if (maxClassScore < minConf) continue;

        // Calculate box size as percentage of original image
        final scaleX = imageWidth / _yoloInputSize;
        final scaleY = imageHeight / _yoloInputSize;
        final boxW = w * scaleX;
        final boxH = h * scaleY;
        final boxArea = boxW * boxH;
        final boxPercent = boxArea / imageArea;

        if (boxPercent < _minBoxPercent) continue;

        // Weighted score = confidence * size
        final weightedScore = maxClassScore * boxPercent;

        if (!categoryScores.containsKey(category)) {
          categoryScores[category] = 0;
        }
        categoryScores[category] = categoryScores[category]! + weightedScore;

        // Track detection
        final className = _getClassName(maxClassId);
        if (!allDetections.contains(className)) {
          allDetections.add(className);
        }
      }

      // Cleanup
      input.dispose();
      for (final o in outputs.values) o.dispose();

      if (categoryScores.isEmpty) {
        // YOLO found objects but none match our categories (people/animals/food)
        final topClass = maxClassIdFound >= 0
            ? _getClassName(maxClassIdFound)
            : 'none';
        final topScore = (maxScoreFound * 100).toStringAsFixed(1);
        lastYoloError =
            'YOLO: No people/animals/food. Top detection: $topClass ($topScore%) from $numDetections boxes';
        developer.log('[YOLO] $lastYoloError');
        return null;
      }

      // Pick winner with priority tie-breaking
      String? winner;
      double winnerScore = 0;
      int winnerPriority = -1;

      for (final entry in categoryScores.entries) {
        final priority = _categoryPriority[entry.key] ?? 0;
        if (priority > winnerPriority ||
            (priority == winnerPriority && entry.value > winnerScore)) {
          winner = entry.key;
          winnerScore = entry.value;
          winnerPriority = priority;
        }
      }

      if (winner == null) {
        lastYoloError =
            'YOLO found no matching categories (scores: $categoryScores)';
        return null;
      }

      // Clear error on success
      lastYoloError = null;
      return _YoloDetection(
        category: winner,
        confidence: math.min(winnerScore * 10, 0.99),
        allDetections: allDetections,
      );
    } catch (e, st) {
      input?.dispose();
      outputs?.values.forEach((o) => o.dispose());
      lastYoloError = 'YOLO inference error: $e';
      developer.log('[YOLO] $lastYoloError\n$st');
      return null;
    }
  }

  static String _getClassName(int classId) {
    const cocoNames = [
      'person',
      'bicycle',
      'car',
      'motorcycle',
      'airplane',
      'bus',
      'train',
      'truck',
      'boat',
      'traffic light',
      'fire hydrant',
      'stop sign',
      'parking meter',
      'bench',
      'bird',
      'cat',
      'dog',
      'horse',
      'sheep',
      'cow',
      'elephant',
      'bear',
      'zebra',
      'giraffe',
      'backpack',
      'umbrella',
      'handbag',
      'tie',
      'suitcase',
      'frisbee',
      'skis',
      'snowboard',
      'sports ball',
      'kite',
      'baseball bat',
      'baseball glove',
      'skateboard',
      'surfboard',
      'tennis racket',
      'bottle',
      'wine glass',
      'cup',
      'fork',
      'knife',
      'spoon',
      'bowl',
      'banana',
      'apple',
      'sandwich',
      'orange',
      'broccoli',
      'carrot',
      'hot dog',
      'pizza',
      'donut',
      'cake',
      'chair',
      'couch',
      'potted plant',
      'bed',
      'dining table',
      'toilet',
      'tv',
      'laptop',
      'mouse',
      'remote',
      'keyboard',
      'cell phone',
      'microwave',
      'oven',
      'toaster',
      'sink',
      'refrigerator',
      'book',
      'clock',
      'vase',
      'scissors',
      'teddy bear',
      'hair drier',
      'toothbrush',
    ];
    if (classId >= 0 && classId < cocoNames.length) {
      return cocoNames[classId];
    }
    return 'unknown';
  }

  static Future<void> dispose() async {
    await _yoloSession?.close();
    await _imageLabeler?.close();
    _yoloSession = null;
    _imageLabeler = null;
    _yoloReady = false;
    _labelerInitialized = false;
  }
}

class _YoloDetection {
  final String category;
  final double confidence;
  final List<String> allDetections;

  _YoloDetection({
    required this.category,
    required this.confidence,
    required this.allDetections,
  });
}

class HybridTagResult {
  final String category;
  final double confidence;
  final String method;
  final Map<String, int> timings;
  final List<String> allDetections;
  final String? error; // Detailed error info for debugging

  HybridTagResult({
    required this.category,
    required this.confidence,
    required this.method,
    required this.timings,
    this.allDetections = const [],
    this.error,
  });

  int get totalTimeMs => timings.values.fold(0, (a, b) => a + b);
  bool get hasError => error != null;
}

/// Result from preprocessing isolate
class _PreprocessResult {
  final Float32List tensor;
  final int width;
  final int height;

  _PreprocessResult(this.tensor, this.width, this.height);
}

/// Runs on a separate isolate - decodes, resizes, and normalizes image
/// This prevents UI freezing during the expensive image processing
_PreprocessResult? _preprocessImageIsolate(String imagePath) {
  try {
    final bytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final imageWidth = image.width;
    final imageHeight = image.height;

    // Resize to 320x320 (YOLO input size)
    final resized = img.copyResize(image, width: 320, height: 320);

    // Create tensor [1, 3, 320, 320] normalized to 0-1
    const inputSize = 320;
    final tensor = Float32List(3 * inputSize * inputSize);
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        tensor[0 * inputSize * inputSize + y * inputSize + x] = p.rNormalized
            .toDouble();
        tensor[1 * inputSize * inputSize + y * inputSize + x] = p.gNormalized
            .toDouble();
        tensor[2 * inputSize * inputSize + y * inputSize + x] = p.bNormalized
            .toDouble();
      }
    }

    return _PreprocessResult(tensor, imageWidth, imageHeight);
  } catch (e) {
    return null;
  }
}
