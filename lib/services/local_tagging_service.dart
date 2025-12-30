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
      // Lower threshold = faster inference, catches more objects
      // 0.6 provides good balance of speed and accuracy
      options: ImageLabelerOptions(confidenceThreshold: 0.6),
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
    bool hasScreenshot = false;

    // Track confidence scores for conflict resolution
    double bestPeopleConfidence = 0.0;
    double bestAnimalConfidence = 0.0;
    String? bestPeopleLabel;
    String? bestAnimalLabel;

    // First pass: collect ALL category matches (not else-if, so people always detected)
    for (final label in labels) {
      final text = label.label.toLowerCase();
      final confidence = label.confidence;
      // Store original label for display (no percentage needed)
      allDetections.add(label.label);

      // Check ALL categories independently (not else-if)
      if (_isPeopleLabel(text)) {
        categories.add('people');
        developer.log('👤 People label matched: "$text"');
        if (confidence > bestPeopleConfidence) {
          bestPeopleConfidence = confidence;
          bestPeopleLabel = text;
        }
      }
      if (_isAnimalLabel(text)) {
        categories.add('animals');
        if (confidence > bestAnimalConfidence) {
          bestAnimalConfidence = confidence;
          bestAnimalLabel = text;
        }
      }
      if (_isFoodLabel(text)) {
        categories.add('food');
      }
      if (_isDocumentLabel(text)) {
        categories.add('document');
      }
      if (_isSceneryLabel(text)) {
        categories.add('scenery');
      }
      // Track screenshot detection for subtag
      if (text.contains('screenshot') || text.contains('screen')) {
        hasScreenshot = true;
      }
    }

    // CONFLICT RESOLUTION: When both people AND animals detected, check confidence
    // This prevents animal photos being tagged as people due to weak body-part labels
    if (categories.contains('people') && categories.contains('animals')) {
      // If animal confidence is significantly higher, remove people
      // Or if people detection is based on weak/generic labels
      if (bestAnimalConfidence > bestPeopleConfidence + 0.1) {
        // Animal label is more confident - likely an animal photo
        categories.remove('people');
        developer.log(
          '🔄 Conflict: Removed people (${bestPeopleLabel ?? "?"}: ${(bestPeopleConfidence * 100).toInt()}%) in favor of animals (${bestAnimalLabel ?? "?"}: ${(bestAnimalConfidence * 100).toInt()}%)',
        );
      } else if (_isWeakPeopleLabel(bestPeopleLabel ?? '')) {
        // People detection based on generic label that animals share
        categories.remove('people');
        developer.log(
          '🔄 Conflict: Removed weak people label "$bestPeopleLabel" - animal detected',
        );
      }
    }

    // Priority order: people > animals > food > document > scenery
    // If person is detected, that MUST be the main category (even if document/screenshot also detected)
    final prioritized = <String>[];
    if (categories.contains('people')) prioritized.add('people');
    if (categories.contains('animals')) prioritized.add('animals');
    if (categories.contains('food')) prioritized.add('food');
    if (categories.contains('document')) prioritized.add('document');
    if (categories.contains('scenery')) prioritized.add('scenery');

    // Build final tags: main category first
    final resultTags = <String>[];
    if (prioritized.isNotEmpty) {
      resultTags.add(prioritized.first);
      // Add screenshot as secondary tag if detected and main category is people
      if (hasScreenshot && prioritized.first == 'people') {
        resultTags.add('screenshot');
      }
    } else {
      // Log when no category matched - helps debug misses
      developer.log(
        '⚠️ No category matched for labels: ${allDetections.join(", ")}',
      );
    }

    // Return result with both tags and raw detections
    return LocalTagResult(
      tags: resultTags.isNotEmpty ? resultTags : [],
      allDetections: allDetections,
    );
  }

  // ============ Label Mapping Functions ============

  /// Strong people labels - definitely indicate humans
  static bool _isPeopleLabel(String label) {
    const peopleKeywords = [
      // Strong human-specific labels
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
      // Events/gatherings (typically involve people)
      'event',
      'party',
      'wedding',
      'ceremony',
      'celebration',
      'gathering',
      'audience',
      'concert',
      'festival',
      'parade',
      'meeting',
      'conference',
      'graduation',
      'birthday',
      'team',
      'sport',
      'player',
      'athlete',
      'spectator',
      'social',
      'recreation',
      // Performance/theater (always involves people)
      'performance',
      'theater',
      'theatre',
      'stage',
      'actor',
      'actress',
      'performer',
      'show',
      'drama',
      'play',
      'musical',
      'opera',
      'ballet',
      'dance',
      'dancer',
      // Clothing/fashion (strongly indicates person - animals don't wear these)
      'fashion',
      'dress',
      'clothing',
      'shirt',
      'pants',
      'jeans',
      'jacket',
      'coat',
      'sweater',
      'skirt',
      'shoe',
      'sneaker',
      'boot',
      'hat',
      'cap',
      'glasses',
      'sunglasses',
      'goggle', // goggles, swimming goggles, ski goggles
      'eyewear',
      'watch',
      'jewelry',
      'necklace',
      'bracelet',
      'suit',
      'tie',
      'scarf',
      'glove',
      'sock',
      'belt',
      // Actions/poses/emotions specific to humans
      'smiling',
      'laughing',
      'posing',
      'dancing',
      'singing',
      'clapping',
      'waving',
      'fun', // typically implies human activity
      'cool', // often describes person/style
      'happy',
      'joy',
      'playing',
      'leisure', // leisure activities involve people
      'walking', // person walking
      'jogging',
      'hiking',
      'cycling',
      'swimming',
      'exercising',
      'workout',
      'fitness',
    ];
    return peopleKeywords.any((k) => label.contains(k));
  }

  /// Weak people labels - could match animals or other objects
  /// Used for conflict resolution when both people and animals detected
  static bool _isWeakPeopleLabel(String label) {
    const weakLabels = [
      // Body parts that animals/mascots can also have
      'finger',
      'hand',
      'thumb',
      'nail',
      'arm',
      'eye',
      'ear',
      'nose',
      'mouth',
      'lip',
      'hair',
      'skin',
      'body',
      'leg',
      'foot',
      'feet',
      'toe',
      // Generic actions animals can do too
      'sitting',
      'standing',
      'walking',
      'running',
      // Items that can appear without people
      'bag',
      'handbag',
      'backpack',
    ];
    return weakLabels.any((k) => label.contains(k));
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
