import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'dart:ui' as ui;

/// Result containing category prediction with confidence
class MobileClipResult {
  final String category;
  final double confidence;
  final Map<String, double> allScores;

  MobileClipResult({
    required this.category,
    required this.confidence,
    required this.allScores,
  });
}

/// On-device AI classification using MobileCLIP (ONNX).
/// Uses CLIP's zero-shot classification to categorize images into:
/// people, animals, food, scenery, documents, other
class MobileClipService {
  static OnnxRuntime? _ort;
  static OrtSession? _session;
  static Float32List? _categoryEmbeddings;
  static bool _initialized = false;

  /// The 6 categories we classify into
  static const List<String> categories = [
    'people',
    'animals',
    'food',
    'scenery',
    'documents',
    'other',
  ];

  /// ImageNet normalization constants (used by CLIP)
  static const List<double> _mean = [0.48145466, 0.4578275, 0.40821073];
  static const List<double> _std = [0.26862954, 0.26130258, 0.27577711];

  /// Temperature for softmax (higher = sharper distribution)
  static const double _temperature = 100.0;

  /// Initialize the ONNX runtime and load model
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      developer.log('[MobileCLIP] Initializing ONNX Runtime...');

      // Create ONNX Runtime instance
      _ort = OnnxRuntime();

      // Create session from asset
      _session = await _ort!.createSessionFromAsset(
        'assets/models/mobileclip_image_encoder.onnx',
      );

      // Load category embeddings
      await _loadCategoryEmbeddings();

      _initialized = true;
      developer.log('[MobileCLIP] ✓ Initialized successfully');
    } catch (e, st) {
      developer.log('[MobileCLIP] ✗ Initialization failed: $e\n$st');
      rethrow;
    }
  }

  /// Load pre-computed category embeddings from numpy file
  static Future<void> _loadCategoryEmbeddings() async {
    final bytes = await rootBundle.load(
      'assets/models/category_embeddings.npy',
    );
    final data = bytes.buffer.asUint8List();

    // Parse numpy .npy format
    // Header: magic (6 bytes) + version (2 bytes) + header_len (2 bytes) + header
    // Data: raw float32 values

    // Check magic number
    if (data[0] != 0x93 ||
        data[1] != 0x4E ||
        data[2] != 0x55 ||
        data[3] != 0x4D ||
        data[4] != 0x50 ||
        data[5] != 0x59) {
      throw Exception('Invalid numpy file format');
    }

    // Get header length (little-endian 16-bit at offset 8)
    final headerLen = data[8] + (data[9] << 8);
    final dataOffset = 10 + headerLen;

    // Extract float32 data (shape is 6x512 = 3072 floats)
    final floatData = data.sublist(dataOffset);
    _categoryEmbeddings = Float32List.view(
      floatData.buffer,
      floatData.offsetInBytes,
      3072, // 6 categories x 512 dimensions
    );

    developer.log(
      '[MobileCLIP] ✓ Loaded ${_categoryEmbeddings!.length} embedding values',
    );
  }

  /// Check if service is ready
  static bool get isReady => _initialized && _session != null;

  /// Classify an image file and return the predicted category
  static Future<MobileClipResult?> classifyImage(String imagePath) async {
    if (!isReady) {
      developer.log('[MobileCLIP] Not initialized, initializing now...');
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

      // Calculate cosine similarities with category embeddings
      final scores = _calculateSimilarities(imageEmbedding);

      // Apply softmax to get probabilities
      final probs = _softmax(scores, _temperature);

      // Find best match
      int bestIdx = 0;
      double bestProb = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > bestProb) {
          bestProb = probs[i];
          bestIdx = i;
        }
      }

      // Build scores map
      final allScores = <String, double>{};
      for (int i = 0; i < categories.length; i++) {
        allScores[categories[i]] = probs[i];
      }

      // Clean up
      inputValue.dispose();
      for (final output in outputs.values) {
        output.dispose();
      }

      return MobileClipResult(
        category: categories[bestIdx],
        confidence: bestProb,
        allScores: allScores,
      );
    } catch (e, st) {
      developer.log('[MobileCLIP] Classification error: $e\n$st');
      return null;
    }
  }

  /// Preprocess image to NCHW tensor format with CLIP normalization
  static Future<List<double>> _preprocessImage(String imagePath) async {
    // Read image file
    final file = File(imagePath);
    final bytes = await file.readAsBytes();

    // Decode image using dart:ui
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

    // Get pixel data
    final byteData = await resizedImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final pixels = byteData!.buffer.asUint8List();

    // Convert to NCHW format with normalization
    // Shape: [1, 3, 224, 224]
    final tensor = List<double>.filled(1 * 3 * 224 * 224, 0.0);

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixelIndex = (y * 224 + x) * 4; // RGBA
        final r = pixels[pixelIndex] / 255.0;
        final g = pixels[pixelIndex + 1] / 255.0;
        final b = pixels[pixelIndex + 2] / 255.0;

        // Normalize with ImageNet stats
        final rNorm = (r - _mean[0]) / _std[0];
        final gNorm = (g - _mean[1]) / _std[1];
        final bNorm = (b - _mean[2]) / _std[2];

        // NCHW layout: batch=0, channel, height, width
        tensor[0 * 224 * 224 + y * 224 + x] = rNorm; // R channel
        tensor[1 * 224 * 224 + y * 224 + x] = gNorm; // G channel
        tensor[2 * 224 * 224 + y * 224 + x] = bNorm; // B channel
      }
    }

    // Clean up
    image.dispose();
    resizedImage.dispose();

    return tensor;
  }

  /// Calculate cosine similarities between image embedding and category embeddings
  static List<double> _calculateSimilarities(Float32List imageEmbedding) {
    final similarities = <double>[];
    const embeddingDim = 512;

    for (int i = 0; i < categories.length; i++) {
      double dotProduct = 0.0;
      for (int j = 0; j < embeddingDim; j++) {
        dotProduct +=
            imageEmbedding[j] * _categoryEmbeddings![i * embeddingDim + j];
      }
      similarities.add(dotProduct);
    }

    return similarities;
  }

  /// Apply softmax with temperature scaling
  static List<double> _softmax(List<double> scores, double temperature) {
    final expScores = scores.map((s) => math.exp(s * temperature)).toList();
    final sumExp = expScores.reduce((a, b) => a + b);
    return expScores.map((e) => e / sumExp).toList();
  }

  /// Clean up resources
  static Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _categoryEmbeddings = null;
    _initialized = false;
    _ort = null;
    developer.log('[MobileCLIP] Disposed');
  }
}
