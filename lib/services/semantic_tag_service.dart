import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'dart:ui' as ui;

/// Result containing semantic descriptions of what's in the image
class SemanticTagResult {
  final String category; // Main category (people, animals, food, etc.)
  final double categoryConfidence;
  final List<SemanticMatch> topMatches; // Top semantic descriptions

  SemanticTagResult({
    required this.category,
    required this.categoryConfidence,
    required this.topMatches,
  });
}

/// A single semantic description match
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

/// On-device AI that provides semantic descriptions of images using MobileCLIP.
/// Instead of just "food", it can tell you "a plate of cooked food" or "breakfast food".
class SemanticTagService {
  static OnnxRuntime? _ort;
  static OrtSession? _session;
  static Float32List? _semanticEmbeddings;
  static List<String>? _descriptions;
  static List<String>? _categoryForDesc;
  static bool _initialized = false;

  /// ImageNet normalization constants (used by CLIP)
  static const List<double> _mean = [0.48145466, 0.4578275, 0.40821073];
  static const List<double> _std = [0.26862954, 0.26130258, 0.27577711];

  /// Initialize the ONNX runtime and load semantic embeddings
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      developer.log('[SemanticTag] Initializing...');

      // Create ONNX Runtime instance
      _ort = OnnxRuntime();

      // Create session from asset
      _session = await _ort!.createSessionFromAsset(
        'assets/models/mobileclip_image_encoder.onnx',
      );

      // Load semantic embeddings and metadata
      await _loadSemanticEmbeddings();

      _initialized = true;
      developer.log(
        '[SemanticTag] ✓ Initialized with ${_descriptions!.length} semantic descriptions',
      );
    } catch (e, st) {
      developer.log('[SemanticTag] ✗ Initialization failed: $e\n$st');
      rethrow;
    }
  }

  /// Load semantic embeddings and metadata
  static Future<void> _loadSemanticEmbeddings() async {
    // Load embeddings
    final embBytes = await rootBundle.load(
      'assets/models/semantic_embeddings.npy',
    );
    final embData = embBytes.buffer.asUint8List();

    // Parse numpy .npy format
    if (embData[0] != 0x93 ||
        embData[1] != 0x4E ||
        embData[2] != 0x55 ||
        embData[3] != 0x4D ||
        embData[4] != 0x50 ||
        embData[5] != 0x59) {
      throw Exception('Invalid numpy file format');
    }

    final headerLen = embData[8] + (embData[9] << 8);
    final dataOffset = 10 + headerLen;
    final floatData = embData.sublist(dataOffset);

    // 43 descriptions x 512 dimensions = 21,974 floats
    _semanticEmbeddings = Float32List.view(
      floatData.buffer,
      floatData.offsetInBytes,
      43 * 512,
    );

    // Load metadata
    final metaString = await rootBundle.loadString(
      'assets/models/semantic_metadata.json',
    );
    final metadata = json.decode(metaString) as Map<String, dynamic>;
    _descriptions = List<String>.from(metadata['descriptions'] as List);
    _categoryForDesc = List<String>.from(metadata['categories'] as List);

    developer.log(
      '[SemanticTag] ✓ Loaded ${_descriptions!.length} descriptions',
    );
  }

  /// Check if service is ready
  static bool get isReady => _initialized && _session != null;

  /// Analyze an image and return semantic descriptions
  static Future<SemanticTagResult?> analyzeImage(String imagePath) async {
    if (!isReady) {
      developer.log('[SemanticTag] Not initialized, initializing now...');
      await initialize();
    }

    try {
      // Load and preprocess image
      final inputData = await _preprocessImage(imagePath);

      // Create OrtValue from the preprocessed data
      final inputValue = await OrtValue.fromList(inputData, [1, 3, 224, 224]);

      // Run inference
      final inputs = {'image': inputValue};
      final outputs = await _session!.run(inputs);

      // Get embedding output
      final embeddingValue = outputs.values.first;
      final embedding = await embeddingValue.asList();
      final imageEmbedding = Float32List.fromList(
        embedding.map((e) => (e as num).toDouble()).toList(),
      );

      // Calculate similarities with all semantic embeddings
      final similarities = _calculateSimilarities(imageEmbedding);

      // Get top matches
      final matches = <SemanticMatch>[];
      for (int i = 0; i < _descriptions!.length; i++) {
        matches.add(
          SemanticMatch(
            description: _descriptions![i],
            category: _categoryForDesc![i],
            score: similarities[i],
          ),
        );
      }

      // Sort by score descending
      matches.sort((a, b) => b.score.compareTo(a.score));

      // Calculate category scores by averaging top matches per category
      final categoryScores = <String, List<double>>{};
      for (final match in matches) {
        categoryScores.putIfAbsent(match.category, () => []);
        categoryScores[match.category]!.add(match.score);
      }

      // Find best category (highest average of top 2 scores)
      String bestCategory = 'other';
      double bestCategoryScore = 0.0;
      categoryScores.forEach((cat, scores) {
        scores.sort((a, b) => b.compareTo(a));
        final avgTop2 = scores.take(2).reduce((a, b) => a + b) / 2;
        if (avgTop2 > bestCategoryScore) {
          bestCategoryScore = avgTop2;
          bestCategory = cat;
        }
      });

      // Clean up
      inputValue.dispose();
      for (final output in outputs.values) {
        output.dispose();
      }

      return SemanticTagResult(
        category: bestCategory,
        categoryConfidence: bestCategoryScore,
        topMatches: matches.take(7).toList(),
      );
    } catch (e, st) {
      developer.log('[SemanticTag] Analysis error: $e\n$st');
      return null;
    }
  }

  /// Preprocess image to NCHW tensor format with CLIP normalization
  static Future<List<double>> _preprocessImage(String imagePath) async {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Resize to 224x224
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const ui.Rect.fromLTWH(0, 0, 224, 224),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final resizedImage = await picture.toImage(224, 224);

    final byteData = await resizedImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final pixels = byteData!.buffer.asUint8List();

    // Convert to NCHW format with normalization
    final tensor = List<double>.filled(1 * 3 * 224 * 224, 0.0);

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixelIndex = (y * 224 + x) * 4;
        final r = pixels[pixelIndex] / 255.0;
        final g = pixels[pixelIndex + 1] / 255.0;
        final b = pixels[pixelIndex + 2] / 255.0;

        final rNorm = (r - _mean[0]) / _std[0];
        final gNorm = (g - _mean[1]) / _std[1];
        final bNorm = (b - _mean[2]) / _std[2];

        tensor[0 * 224 * 224 + y * 224 + x] = rNorm;
        tensor[1 * 224 * 224 + y * 224 + x] = gNorm;
        tensor[2 * 224 * 224 + y * 224 + x] = bNorm;
      }
    }

    image.dispose();
    resizedImage.dispose();

    return tensor;
  }

  /// Calculate cosine similarities
  static List<double> _calculateSimilarities(Float32List imageEmbedding) {
    final similarities = <double>[];
    const embeddingDim = 512;
    final numDescriptions = _descriptions!.length;

    for (int i = 0; i < numDescriptions; i++) {
      double dotProduct = 0.0;
      for (int j = 0; j < embeddingDim; j++) {
        dotProduct +=
            imageEmbedding[j] * _semanticEmbeddings![i * embeddingDim + j];
      }
      similarities.add(dotProduct);
    }

    return similarities;
  }

  /// Clean up resources
  static Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _semanticEmbeddings = null;
    _descriptions = null;
    _categoryForDesc = null;
    _initialized = false;
    _ort = null;
    developer.log('[SemanticTag] Disposed');
  }
}
