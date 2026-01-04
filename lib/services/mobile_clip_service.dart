import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'tagging_service_factory.dart';

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
  static bool _initializing = false;

  /// Simple mutex for ONNX inference
  static Completer<void>? _mutex;

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

    // Prevent concurrent initialization
    if (_initializing) {
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }
    _initializing = true;

    try {
      developer.log('[MobileCLIP] Initializing ONNX Runtime...');

      // Create ONNX Runtime instance
      _ort = OnnxRuntime();

      // Check available providers for hardware acceleration
      final availableProviders = await _ort!.getAvailableProviders();
      developer.log('[MobileCLIP] Available providers: $availableProviders');

      // Build provider list: XNNPACK/CPU only (NNAPI can cause issues)
      final providers = <OrtProvider>[];
      // Skip NNAPI for now - can cause issues on some devices
      // if (availableProviders.contains(OrtProvider.NNAPI)) {
      //   providers.add(OrtProvider.NNAPI);
      // }
      if (availableProviders.contains(OrtProvider.XNNPACK)) {
        providers.add(OrtProvider.XNNPACK);
      }
      providers.add(OrtProvider.CPU); // Always fallback to CPU

      // Get optimal thread count based on device capabilities
      final intraOpThreads =
          await TaggingServiceFactory.getOptimalIntraOpThreads();

      // Optimized session options
      final sessionOptions = OrtSessionOptions(
        intraOpNumThreads: intraOpThreads, // Dynamic: 2-6 based on device
        interOpNumThreads: 1, // Sequential execution between ops
        providers: providers,
        useArena: true, // Memory arena for faster allocation
      );

      // Create session from asset with optimized options
      developer.log('[MobileCLIP] Loading model with providers: $providers...');
      _session = await _ort!.createSessionFromAsset(
        'assets/models/mobileclip_image_encoder.onnx',
        options: sessionOptions,
      );

      // Load category embeddings
      await _loadCategoryEmbeddings();

      _initialized = true;
      _initializing = false;
      developer.log('[MobileCLIP] ✓ Initialized successfully');
    } catch (e, st) {
      _initializing = false;
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

  static Future<void> _acquireLock() async {
    while (_mutex != null) {
      await _mutex!.future;
    }
    _mutex = Completer<void>();
  }

  static void _releaseLock() {
    final m = _mutex;
    _mutex = null;
    m?.complete();
  }

  /// Classify an image file and return the predicted category
  static Future<MobileClipResult?> classifyImage(String imagePath) async {
    if (!isReady) {
      developer.log('[MobileCLIP] Not initialized, initializing now...');
      await initialize();
    }

    // Serialize ONNX calls to prevent memory issues
    await _acquireLock();

    OrtValue? inputValue;
    Map<String, OrtValue>? outputs;

    try {
      // Load and preprocess image (in isolate)
      final inputData = await _preprocessImage(imagePath);

      // Create OrtValue from the preprocessed data
      inputValue = await OrtValue.fromList(inputData, [1, 3, 224, 224]);

      // Run inference with timeout
      final inputs = {'image': inputValue};
      outputs = await _session!
          .run(inputs)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('ONNX inference timeout'),
          );

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

      _releaseLock();

      return MobileClipResult(
        category: categories[bestIdx],
        confidence: bestProb,
        allScores: allScores,
      );
    } catch (e, st) {
      // Clean up on error
      inputValue?.dispose();
      if (outputs != null) {
        for (final output in outputs.values) {
          output.dispose();
        }
      }
      _releaseLock();
      developer.log('[MobileCLIP] Classification error: $e\n$st');
      return null;
    }
  }

  /// Preprocess image to NCHW tensor format with CLIP normalization
  /// Runs in a separate isolate to avoid blocking the UI thread
  static Future<Float64List> _preprocessImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    return compute(
      _preprocessImageIsolate,
      _ClipPreprocessInput(bytes, _mean, _std),
    );
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

/// Input data for the preprocessing isolate
class _ClipPreprocessInput {
  final Uint8List bytes;
  final List<double> mean;
  final List<double> std;
  _ClipPreprocessInput(this.bytes, this.mean, this.std);
}

/// Runs on a separate isolate - decodes, resizes, and normalizes image
Float64List _preprocessImageIsolate(_ClipPreprocessInput input) {
  // Decode image
  final image = img.decodeImage(input.bytes);
  if (image == null) {
    throw Exception('Failed to decode image');
  }

  // Resize to 224x224 using bilinear interpolation
  final resized = img.copyResize(
    image,
    width: 224,
    height: 224,
    interpolation: img.Interpolation.linear,
  );

  // Convert to NCHW format with CLIP normalization
  final tensor = Float64List(1 * 3 * 224 * 224);

  for (int y = 0; y < 224; y++) {
    for (int x = 0; x < 224; x++) {
      final pixel = resized.getPixel(x, y);
      final r = pixel.r / 255.0;
      final g = pixel.g / 255.0;
      final b = pixel.b / 255.0;

      final rNorm = (r - input.mean[0]) / input.std[0];
      final gNorm = (g - input.mean[1]) / input.std[1];
      final bNorm = (b - input.mean[2]) / input.std[2];

      tensor[0 * 224 * 224 + y * 224 + x] = rNorm;
      tensor[1 * 224 * 224 + y * 224 + x] = gNorm;
      tensor[2 * 224 * 224 + y * 224 + x] = bNorm;
    }
  }

  return tensor;
}
