import 'dart:io';
import 'dart:developer' as developer;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

/// Result containing both category tags and raw ML Kit labels
class LocalTagResult {
  final List<String> tags;
  final List<String> allDetections;

  LocalTagResult({required this.tags, required this.allDetections});
}

/// On-device AI tagging service using Google ML Kit.
/// Maps ML Kit's 400+ labels to our 5 main categories.
class LocalTaggingService {
  static ImageLabeler? _labeler;

  /// Initialize the ML Kit labeler (lazy singleton)
  static ImageLabeler get labeler {
    _labeler ??= ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.7),
    );
    return _labeler!;
  }

  /// Clean up resources
  static Future<void> dispose() async {
    await _labeler?.close();
    _labeler = null;
  }

  /// Classify a single image and return our category tags
  static Future<List<String>> classifyImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final labels = await labeler.processImage(inputImage);

      // Debug: log all detected labels
      if (labels.isNotEmpty) {
        final labelInfo = labels
            .map(
              (l) => '${l.label}(${(l.confidence * 100).toStringAsFixed(0)}%)',
            )
            .join(', ');
        developer.log('ML Kit labels for $imagePath: $labelInfo');
      } else {
        developer.log('ML Kit: No labels detected for $imagePath');
      }

      if (labels.isEmpty) {
        return ['other'];
      }

      // Map ML Kit labels to our categories
      final result = _mapLabelsToCategories(labels);

      developer.log('ML Kit mapped to categories: ${result.tags}');

      if (result.tags.isEmpty) {
        return ['other'];
      }

      return result.tags;
    } catch (e) {
      developer.log('LocalTaggingService error: $e');
      return ['other'];
    }
  }

  /// Classify a single image and return both categories AND raw labels
  static Future<LocalTagResult> classifyImageWithDetections(
    String imagePath,
  ) async {
    try {
      final startTime = DateTime.now();

      final inputImage = InputImage.fromFilePath(imagePath);
      final labels = await labeler.processImage(inputImage);

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      developer.log(
        'ML Kit processed image in ${elapsed}ms, found ${labels.length} labels',
      );

      if (labels.isEmpty) {
        return LocalTagResult(tags: ['other'], allDetections: []);
      }

      final result = _mapLabelsToCategories(labels);

      if (result.tags.isEmpty) {
        return LocalTagResult(
          tags: ['other'],
          allDetections: result.allDetections,
        );
      }

      return result;
    } catch (e) {
      developer.log('LocalTaggingService error: $e');
      return LocalTagResult(tags: ['other'], allDetections: []);
    }
  }

  /// Classify image from bytes (for in-memory processing)
  static Future<List<String>> classifyImageBytes(
    List<int> bytes,
    int width,
    int height,
  ) async {
    try {
      // ML Kit needs a file path, so we'll write to temp
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/ml_temp_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(bytes);

      final result = await classifyImage(tempFile.path);

      // Cleanup
      try {
        await tempFile.delete();
      } catch (_) {}

      return result;
    } catch (e) {
      developer.log('LocalTaggingService classifyImageBytes error: $e');
      return ['other'];
    }
  }

  /// Map Google ML Kit labels to our 5 categories
  static LocalTagResult _mapLabelsToCategories(List<ImageLabel> labels) {
    final Set<String> categories = {};
    final List<String> allDetections = [];

    for (final label in labels) {
      final text = label.label.toLowerCase();
      // Store original label for display (no percentage needed)
      allDetections.add(label.label);

      // PEOPLE - highest priority
      if (_isPeopleLabel(text)) {
        categories.add('people');
      }
      // ANIMALS
      else if (_isAnimalLabel(text)) {
        categories.add('animals');
      }
      // FOOD
      else if (_isFoodLabel(text)) {
        categories.add('food');
      }
      // DOCUMENT
      else if (_isDocumentLabel(text)) {
        categories.add('document');
      }
      // SCENERY
      else if (_isSceneryLabel(text)) {
        categories.add('scenery');
      }
    }

    // Priority order: people > animals > food > document > scenery
    final prioritized = <String>[];
    if (categories.contains('people')) prioritized.add('people');
    if (categories.contains('animals')) prioritized.add('animals');
    if (categories.contains('food')) prioritized.add('food');
    if (categories.contains('document')) prioritized.add('document');
    if (categories.contains('scenery')) prioritized.add('scenery');

    // Return result with both tags and raw detections
    return LocalTagResult(
      tags: prioritized.isNotEmpty ? [prioritized.first] : [],
      allDetections: allDetections,
    );
  }

  // ============ Label Mapping Functions ============

  static bool _isPeopleLabel(String label) {
    const peopleKeywords = [
      'person',
      'people',
      'human',
      'man',
      'woman',
      'child',
      'kid',
      'baby',
      'face',
      'selfie',
      'portrait',
      'crowd',
      'group',
      'family',
      'couple',
      'boy',
      'girl',
      'adult',
      'teenager',
      'elder',
      'senior',
      // Body parts
      'finger',
      'hand',
      'nail',
      'arm',
      'leg',
      'foot',
      'feet',
      'eye',
      'ear',
      'nose',
      'mouth',
      'lip',
      'hair',
      'skin',
      'body',
      'thumb',
      'toe',
    ];
    return peopleKeywords.any((k) => label.contains(k));
  }

  static bool _isAnimalLabel(String label) {
    const animalKeywords = [
      'animal',
      'pet',
      'dog',
      'cat',
      'bird',
      'fish',
      'horse',
      'cow',
      'sheep',
      'goat',
      'pig',
      'chicken',
      'duck',
      'rabbit',
      'hamster',
      'turtle',
      'snake',
      'lizard',
      'frog',
      'insect',
      'butterfly',
      'bee',
      'elephant',
      'lion',
      'tiger',
      'bear',
      'monkey',
      'zebra',
      'giraffe',
      'deer',
      'wolf',
      'fox',
      'squirrel',
      'mouse',
      'rat',
      'parrot',
      'puppy',
      'kitten',
      'wildlife',
      'mammal',
      'reptile',
    ];
    return animalKeywords.any((k) => label.contains(k));
  }

  static bool _isFoodLabel(String label) {
    const foodKeywords = [
      'food',
      'meal',
      'dish',
      'cuisine',
      'breakfast',
      'lunch',
      'dinner',
      'snack',
      'dessert',
      'fruit',
      'vegetable',
      'meat',
      'fish',
      'seafood',
      'bread',
      'pasta',
      'rice',
      'pizza',
      'burger',
      'sandwich',
      'salad',
      'soup',
      'cake',
      'cookie',
      'ice cream',
      'chocolate',
      'candy',
      'drink',
      'beverage',
      'coffee',
      'tea',
      'juice',
      'wine',
      'beer',
      'apple',
      'banana',
      'orange',
      'grape',
      'strawberry',
      'watermelon',
      'tomato',
      'potato',
      'carrot',
      'broccoli',
      'egg',
      'cheese',
      'milk',
      'restaurant',
      'cooking',
      'baking',
      'kitchen',
      'plate',
      'bowl',
    ];
    return foodKeywords.any((k) => label.contains(k));
  }

  static bool _isDocumentLabel(String label) {
    // Only match actual documents with text/writing - IDs, papers, receipts, etc.
    const docKeywords = [
      'text',
      'document',
      'paper',
      'book',
      'newspaper',
      'magazine',
      'letter',
      'note',
      'receipt',
      'invoice',
      'form',
      'contract',
      'writing',
      'handwriting',
      'printed',
      'page',
      'article',
      'card',
      'poster',
      'sign',
      'banner',
      'menu',
      'ticket',
      'certificate',
      'diploma',
      'envelope',
      'mail',
      'calendar',
      'chart',
      'diagram',
      'map',
      // ID documents
      'license',
      'passport',
      'identification',
      'badge',
    ];
    return docKeywords.any((k) => label.contains(k));
  }

  static bool _isSceneryLabel(String label) {
    const sceneryKeywords = [
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
      'flower',
      'plant',
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
      'building',
      'architecture',
      'city',
      'street',
      'road',
      'bridge',
      'tower',
      'castle',
      'church',
      'temple',
      'monument',
      'statue',
      'field',
      'meadow',
      'desert',
      'snow',
      'ice',
      'rain',
      'storm',
      'horizon',
      'view',
      'panorama',
      'aerial',
    ];
    return sceneryKeywords.any((k) => label.contains(k));
  }
}
