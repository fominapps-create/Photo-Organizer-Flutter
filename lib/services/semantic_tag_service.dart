import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// Fast category-only tagging (6 categories instead of 43 descriptions)
class SemanticTagService {
  static OrtSession? _session;
  static Float32List? _categoryEmbeddings; // 6 x 512
  static bool _ready = false;
  static String? lastError;

  static const _categories = [
    'people',
    'animals',
    'food',
    'scenery',
    'documents',
    'other',
  ];

  static bool get isReady => _ready;

  /// Initialize with XNNPACK acceleration
  static Future<void> initialize() async {
    if (_ready) return;

    final start = DateTime.now();
    try {
      final ort = OnnxRuntime();

      // Use XNNPACK for hardware acceleration
      final providers = await ort.getAvailableProviders();
      final sessionOptions = OrtSessionOptions(
        providers: [
          if (providers.contains(OrtProvider.XNNPACK)) OrtProvider.XNNPACK,
          OrtProvider.CPU,
        ],
        intraOpNumThreads: 4,
        interOpNumThreads: 1,
      );

      _session = await ort.createSessionFromAsset(
        'assets/models/mobileclip_image_encoder.onnx',
        options: sessionOptions,
      );

      // Load 6 category embeddings (not 43 descriptions)
      final embBytes = await rootBundle.load(
        'assets/models/category_embeddings.npy',
      );
      final embData = embBytes.buffer.asUint8List();
      final headerLen = embData[8] + (embData[9] << 8);
      final floatData = embData.sublist(10 + headerLen);
      _categoryEmbeddings = Float32List.view(
        floatData.buffer,
        floatData.offsetInBytes,
        6 * 512,
      );

      _ready = true;
      developer.log(
        '[ST] Ready in ${DateTime.now().difference(start).inMilliseconds}ms',
      );
    } catch (e) {
      lastError = e.toString();
      developer.log('[ST] Init failed: $e');
      rethrow;
    }
  }

  /// Analyze image and return category
  static Future<CategoryResult?> analyzeImageCategory(String imagePath) async {
    if (!_ready) {
      await initialize();
      if (!_ready) return null;
    }

    OrtValue? input;
    Map<String, OrtValue>? outputs;

    try {
      // Preprocess in isolate (won't block UI)
      final tensor = await compute(_preprocessImage, imagePath);

      // Yield to let UI render a frame before inference
      await Future.delayed(Duration.zero);

      // Run inference
      input = await OrtValue.fromList(tensor, [1, 3, 256, 256]);
      outputs = await _session!.run({'image': input});

      // Get embedding
      final embList = await outputs.values.first.asList();
      final Float32List embedding;
      if (embList.isNotEmpty && embList[0] is List) {
        final inner = embList[0] as List;
        embedding = Float32List.fromList(
          inner.map((e) => (e as num).toDouble()).toList(),
        );
      } else if (embList is Float32List) {
        embedding = embList;
      } else {
        embedding = Float32List.fromList(
          embList.map((e) => (e as num).toDouble()).toList(),
        );
      }

      // Calculate 6 dot products (fast!)
      final scores = <double>[];
      for (int i = 0; i < 6; i++) {
        double dot = 0;
        for (int j = 0; j < 512; j++) {
          dot += embedding[j] * _categoryEmbeddings![i * 512 + j];
        }
        scores.add(dot);
      }

      // Find best category
      int bestIdx = 0;
      double bestScore = scores[0];
      for (int i = 1; i < 6; i++) {
        if (scores[i] > bestScore) {
          bestScore = scores[i];
          bestIdx = i;
        }
      }

      // Cleanup
      input.dispose();
      for (final o in outputs.values) o.dispose();

      lastError = null;
      return CategoryResult(
        category: _categories[bestIdx],
        confidence: bestScore,
        allScores: {for (int i = 0; i < 6; i++) _categories[i]: scores[i]},
      );
    } catch (e) {
      input?.dispose();
      outputs?.values.forEach((o) => o.dispose());
      lastError = e.toString();
      return null;
    }
  }

  static Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _ready = false;
  }

  /// Backward-compatible wrapper for factory
  static Future<SemanticTagResult?> analyzeImage(String imagePath) async {
    final cat = await analyzeImageCategory(imagePath);
    if (cat == null) return null;
    return SemanticTagResult.fromCategory(cat);
  }
}

/// Result with just category (not 43 descriptions)
class CategoryResult {
  final String category;
  final double confidence;
  final Map<String, double> allScores;

  CategoryResult({
    required this.category,
    required this.confidence,
    required this.allScores,
  });
}

/// Preprocessing in isolate - doesn't block UI
Float32List _preprocessImage(String imagePath) {
  final bytes = File(imagePath).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) throw Exception('Failed to decode image');

  final resized = img.copyResize(image, width: 256, height: 256);
  final tensor = Float32List(3 * 256 * 256);

  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 256; x++) {
      final p = resized.getPixel(x, y);
      tensor[0 * 256 * 256 + y * 256 + x] = p.rNormalized.toDouble();
      tensor[1 * 256 * 256 + y * 256 + x] = p.gNormalized.toDouble();
      tensor[2 * 256 * 256 + y * 256 + x] = p.bNormalized.toDouble();
    }
  }
  return tensor;
}

// Keep old classes for backward compatibility
class SemanticTagResult {
  final String category;
  final double categoryConfidence;
  final List<SemanticMatch> topMatches;

  SemanticTagResult({
    required this.category,
    required this.categoryConfidence,
    required this.topMatches,
  });

  /// Create from CategoryResult
  factory SemanticTagResult.fromCategory(CategoryResult cat) {
    return SemanticTagResult(
      category: cat.category,
      categoryConfidence: cat.confidence,
      topMatches:
          cat.allScores.entries
              .map(
                (e) => SemanticMatch(
                  description: e.key,
                  category: e.key,
                  score: e.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score)),
    );
  }
}

class SemanticMatch {
  final String description;
  final String category;
  final double score;

  SemanticMatch({
    required this.description,
    required this.category,
    required this.score,
  });
}
