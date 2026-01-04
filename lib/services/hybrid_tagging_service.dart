import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Hybrid tagging service combining:
/// 1. ML Kit Face Detection (fast, accurate for people)
/// 2. YOLO object detection (with size/priority logic)
/// 3. ML Kit Text Recognition (for documents)
class HybridTaggingService {
  // YOLO ONNX
  static OrtSession? _yoloSession;
  static bool _yoloReady = false;

  // ML Kit detectors
  static FaceDetector? _faceDetector;
  static TextRecognizer? _textRecognizer;

  static String? lastError;

  // YOLO input size
  static const int _yoloInputSize = 640;

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

  // Confidence thresholds
  static const double _faceMinSize = 0.02; // 2% of image = valid face
  static const double _yoloConfidence = 0.5;
  static const double _animalConfidence = 0.45;
  static const double _foodConfidence = 0.6;
  static const double _minBoxPercent = 0.02; // 2% of image minimum
  static const double _textMinChars = 50; // Minimum chars to be "document"

  static bool get isReady => _yoloReady;

  /// Initialize all models
  static Future<void> initialize() async {
    if (_yoloReady) return;

    final start = DateTime.now();
    try {
      // Initialize YOLO ONNX
      final ort = OnnxRuntime();
      final providers = await ort.getAvailableProviders();
      final sessionOptions = OrtSessionOptions(
        providers: [
          if (providers.contains(OrtProvider.XNNPACK)) OrtProvider.XNNPACK,
          OrtProvider.CPU,
        ],
        intraOpNumThreads: 4,
      );

      _yoloSession = await ort.createSessionFromAsset(
        'assets/models/yolov8n.onnx',
        options: sessionOptions,
      );

      // Initialize ML Kit detectors
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableLandmarks: false,
          enableClassification: false,
          enableTracking: false,
          minFaceSize: 0.1,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      _textRecognizer = TextRecognizer();

      _yoloReady = true;
      developer.log(
        '[Hybrid] Ready in ${DateTime.now().difference(start).inMilliseconds}ms',
      );
    } catch (e) {
      lastError = e.toString();
      developer.log('[Hybrid] Init failed: $e');
      rethrow;
    }
  }

  /// Main classification method
  static Future<HybridTagResult?> classifyImage(String imagePath) async {
    if (!_yoloReady) {
      await initialize();
      if (!_yoloReady) return null;
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    final timings = <String, int>{};
    final stopwatch = Stopwatch();

    try {
      // Step 1: Face Detection (fastest path to "people")
      stopwatch.start();
      final faces = await _faceDetector!.processImage(inputImage);
      stopwatch.stop();
      timings['face'] = stopwatch.elapsedMilliseconds;

      if (faces.isNotEmpty) {
        // Check if any face is significant size
        final imageFile = File(imagePath);
        final bytes = await imageFile.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image != null) {
          final imageArea = image.width * image.height;
          for (final face in faces) {
            final faceArea = face.boundingBox.width * face.boundingBox.height;
            final facePercent = faceArea / imageArea;
            if (facePercent >= _faceMinSize) {
              developer.log(
                '[Hybrid] Face detected (${(facePercent * 100).toStringAsFixed(1)}%) → people',
              );
              return HybridTagResult(
                category: 'people',
                confidence: 0.95,
                method: 'face',
                timings: timings,
              );
            }
          }
        }
      }

      // Step 2: YOLO Object Detection
      stopwatch.reset();
      stopwatch.start();
      final yoloResult = await _runYolo(imagePath);
      stopwatch.stop();
      timings['yolo'] = stopwatch.elapsedMilliseconds;

      if (yoloResult != null) {
        developer.log(
          '[Hybrid] YOLO detected ${yoloResult.category} (${(yoloResult.confidence * 100).toStringAsFixed(0)}%)',
        );
        return HybridTagResult(
          category: yoloResult.category,
          confidence: yoloResult.confidence,
          method: 'yolo',
          timings: timings,
          allDetections: yoloResult.allDetections,
        );
      }

      // Step 3: Text Recognition (for documents)
      stopwatch.reset();
      stopwatch.start();
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      stopwatch.stop();
      timings['text'] = stopwatch.elapsedMilliseconds;

      if (recognizedText.text.length >= _textMinChars) {
        developer.log(
          '[Hybrid] Text detected (${recognizedText.text.length} chars) → documents',
        );
        return HybridTagResult(
          category: 'documents',
          confidence: 0.85,
          method: 'text',
          timings: timings,
        );
      }

      // Step 4: Nothing matched → other
      developer.log('[Hybrid] No match → other');
      return HybridTagResult(
        category: 'other',
        confidence: 0.5,
        method: 'fallback',
        timings: timings,
      );
    } catch (e) {
      lastError = e.toString();
      developer.log('[Hybrid] Error: $e');
      return null;
    }
  }

  /// Run YOLO inference with size-based priority logic
  static Future<_YoloDetection?> _runYolo(String imagePath) async {
    OrtValue? input;
    Map<String, OrtValue>? outputs;

    try {
      // Load and preprocess image
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final imageWidth = image.width;
      final imageHeight = image.height;
      final imageArea = imageWidth * imageHeight;

      // Resize to 640x640 (YOLO input)
      final resized = img.copyResize(
        image,
        width: _yoloInputSize,
        height: _yoloInputSize,
      );

      // Create tensor [1, 3, 640, 640] normalized to 0-1
      final tensor = Float32List(3 * _yoloInputSize * _yoloInputSize);
      for (int y = 0; y < _yoloInputSize; y++) {
        for (int x = 0; x < _yoloInputSize; x++) {
          final p = resized.getPixel(x, y);
          tensor[0 * _yoloInputSize * _yoloInputSize + y * _yoloInputSize + x] =
              p.rNormalized.toDouble();
          tensor[1 * _yoloInputSize * _yoloInputSize + y * _yoloInputSize + x] =
              p.gNormalized.toDouble();
          tensor[2 * _yoloInputSize * _yoloInputSize + y * _yoloInputSize + x] =
              p.bNormalized.toDouble();
        }
      }

      // Run inference
      input = await OrtValue.fromList(tensor, [
        1,
        3,
        _yoloInputSize,
        _yoloInputSize,
      ]);
      outputs = await _yoloSession!.run({'images': input});

      // Parse YOLO output [1, 84, 8400] -> 8400 detections, 84 values each
      // Values: x, y, w, h, class_scores[80]
      final outputList = await outputs.values.first.asList();

      // Handle nested list structure
      List<dynamic> flatOutput;
      if (outputList.isNotEmpty && outputList[0] is List) {
        flatOutput = outputList[0] as List;
      } else {
        flatOutput = outputList;
      }

      // Category scores with weighted scoring
      final categoryScores = <String, double>{};
      final allDetections = <String>[];

      // YOLOv8 output is [1, 84, 8400] - need to transpose
      // Each of 84 rows contains 8400 values
      final numDetections = 8400;
      final numClasses = 80;

      for (int i = 0; i < numDetections; i++) {
        // Get box coordinates (first 4 values for this detection)
        double cx = 0, cy = 0, w = 0, h = 0;
        double maxClassScore = 0;
        int maxClassId = -1;

        // For YOLOv8, output shape is [1, 84, 8400]
        // flatOutput[j] is the j-th row (84 rows), each with 8400 values
        if (flatOutput.length == 84) {
          // Transposed format
          cx = (flatOutput[0] as List)[i].toDouble();
          cy = (flatOutput[1] as List)[i].toDouble();
          w = (flatOutput[2] as List)[i].toDouble();
          h = (flatOutput[3] as List)[i].toDouble();

          // Find max class score
          for (int c = 0; c < numClasses; c++) {
            final score = (flatOutput[4 + c] as List)[i].toDouble();
            if (score > maxClassScore) {
              maxClassScore = score;
              maxClassId = c;
            }
          }
        } else {
          continue; // Unknown format
        }

        // Check confidence threshold
        final category = _yoloToCategory[maxClassId];
        if (category == null) continue;

        double minConf = _yoloConfidence;
        if (maxClassId >= 14 && maxClassId <= 23) {
          minConf = _animalConfidence;
        } else if (maxClassId >= 46 && maxClassId <= 55) {
          minConf = _foodConfidence;
        }

        if (maxClassScore < minConf) continue;

        // Calculate box size as percentage of original image
        // Scale from 640 back to original
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

      if (categoryScores.isEmpty) return null;

      // Pick winner with priority tie-breaking
      String? winner;
      double winnerScore = 0;
      int winnerPriority = -1;

      for (final entry in categoryScores.entries) {
        final priority = _categoryPriority[entry.key] ?? 0;
        // If higher priority, or same priority with higher score
        if (priority > winnerPriority ||
            (priority == winnerPriority && entry.value > winnerScore)) {
          winner = entry.key;
          winnerScore = entry.value;
          winnerPriority = priority;
        }
      }

      if (winner == null) return null;

      return _YoloDetection(
        category: winner,
        confidence: math.min(winnerScore * 10, 0.99), // Scale for display
        allDetections: allDetections,
      );
    } catch (e) {
      input?.dispose();
      outputs?.values.forEach((o) => o.dispose());
      developer.log('[Hybrid] YOLO error: $e');
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
    await _faceDetector?.close();
    await _textRecognizer?.close();
    _yoloSession = null;
    _faceDetector = null;
    _textRecognizer = null;
    _yoloReady = false;
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
  final String method; // face, yolo, text, labels, fallback
  final Map<String, int> timings;
  final List<String> allDetections;

  HybridTagResult({
    required this.category,
    required this.confidence,
    required this.method,
    required this.timings,
    this.allDetections = const [],
  });

  int get totalTimeMs => timings.values.fold(0, (a, b) => a + b);
}
