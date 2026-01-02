import 'dart:io';
import 'dart:developer' as developer;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

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
  static FaceDetector? _faceDetector;

  /// Initialize the ML Kit labeler (lazy singleton)
  static ImageLabeler get labeler {
    _labeler ??= ImageLabeler(
      // Lower threshold = catches more objects including body parts
      // 0.5 helps detect people in complex scenes (person with phone, etc.)
      options: ImageLabelerOptions(confidenceThreshold: 0.5),
    );
    return _labeler!;
  }

  /// Initialize the ML Kit face detector (lazy singleton)
  /// Only used when image labeling returns "other" to catch missed people
  static FaceDetector get faceDetector {
    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false, // Don't need contours, just detection
        enableLandmarks: false, // Don't need landmarks
        enableClassification: false, // Don't need smile/eyes classification
        enableTracking: false, // Don't need tracking across frames
        minFaceSize:
            0.1, // Detect faces as small as 10% of image (for group photos)
        performanceMode: FaceDetectorMode.fast, // Speed over accuracy
      ),
    );
    return _faceDetector!;
  }

  /// Clean up resources
  static Future<void> dispose() async {
    await _labeler?.close();
    _labeler = null;
    await _faceDetector?.close();
    _faceDetector = null;
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
  /// OPTIMIZATION: Face detection first (fast ~25ms), then labeling if no faces (~100ms)
  /// This speeds up scanning by ~16-30% since many photos contain visible faces
  static Future<LocalTagResult> classifyImageWithDetections(
    String imagePath,
  ) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);

      // STEP 1: Fast face detection first (~25ms)
      final faceStartTime = DateTime.now();
      final faces = await faceDetector.processImage(inputImage);
      final faceElapsed = DateTime.now()
          .difference(faceStartTime)
          .inMilliseconds;

      if (faces.isNotEmpty) {
        // Found faces - immediate "people" result, skip expensive labeling
        developer.log(
          '👥 Face detection found ${faces.length} face(s) in ${faceElapsed}ms → people (skipped labeling)',
        );
        return LocalTagResult(
          tags: ['people'],
          allDetections: ['Faces detected:${faces.length}'],
        );
      }

      developer.log(
        '👤 No faces found in ${faceElapsed}ms, running image labeling...',
      );

      // STEP 2: No faces found - run full image labeling (~100ms)
      final labelStartTime = DateTime.now();
      final labels = await labeler.processImage(inputImage);
      final labelElapsed = DateTime.now()
          .difference(labelStartTime)
          .inMilliseconds;

      developer.log(
        'ML Kit labeling completed in ${labelElapsed}ms, found ${labels.length} labels',
      );

      if (labels.isEmpty) {
        return LocalTagResult(tags: ['other'], allDetections: []);
      }

      return _mapLabelsToCategories(labels);
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
    bool hasTextLabel =
        false; // Track if text/writing detected (screenshot indicator)

    // Track confidence scores for conflict resolution
    double bestPeopleConfidence = 0.0;
    double bestAnimalConfidence = 0.0;
    double bestDocumentConfidence = 0.0;
    String? bestAnimalLabel;

    // FIX #4: Track highest confidence across ALL labels for global threshold
    double highestConfidence = 0.0;

    // Track detected animal types (cat, dog, bird, etc.) for deduplication
    // When multiple animals are detected but there's likely only 1, keep the best
    final Set<String> detectedAnimalTypes = {};
    // Track all animal confidences for smart deduplication
    final Map<String, double> animalConfidences = {};

    // Track strong scenery labels - need 2+ for real scenery (sky+water, buildings+sky, etc.)
    // Single label like just "statue" or just "outdoor" = not enough for scenery
    int strongSceneryCount = 0;

    // Track if we have STRONG person indicators (face, person, human - not just clothing)
    bool hasStrongPersonLabel = false;

    // Track if we have STRONG food indicators (actual food items, not just context)
    bool hasStrongFoodLabel = false;

    // SIMPLIFIED PEOPLE DETECTION (v16)
    // Direct labels: body parts + human terms (child, person, face, hand, hair, etc.)
    // Clothing labels: shirt, pants, dress, etc. (need body evidence to count)
    // Rule: 2+ direct at moderate conf (≥50%), OR 3+ direct at any conf, OR 1+ direct + 2+ clothing
    int directPeopleCount = 0; // Body parts + human terms
    int directPeopleModerateCount = 0; // Direct labels at ≥50% confidence
    int clothingCount = 0; // Clothing items (supporting evidence)
    bool hasIllustrationIndicator = false; // Cartoon, toy, logo, etc.
    bool hasFurOrAnimalIndicator = false; // fur, paw, tail - indicates animal

    // Minimum confidence threshold for simple category decisions (scenery, animals, food, document)
    // People uses a tiered system that can combine multiple lower-confidence labels
    const double minCategoryConfidence = 0.86;

    // First pass: collect ALL category matches (not else-if, so people always detected)
    for (final label in labels) {
      final text = label.label.toLowerCase();
      final confidence = label.confidence;

      // FIX #4: Track highest confidence for global threshold check
      if (confidence > highestConfidence) {
        highestConfidence = confidence;
      }

      // FIX #4: Only add labels with 86%+ confidence to searchable detections
      // Low-confidence labels are usually false positives and shouldn't clutter search
      // Also exclude category names - they appear as the main category, not as objects
      const categoryNames = [
        'food',
        'people',
        'animals',
        'document',
        'scenery',
        'other',
      ];
      // Hide cat/dog from visible labels - ML Kit often confuses them
      // They still trigger "animals" category but aren't searchable individually
      const hiddenLabels = ['cat', 'dog'];
      final isCatOrDog =
          hiddenLabels.any((h) => text.contains(h)) &&
          !text.contains('hot dog'); // hot dog is food, not animal

      if (confidence >= 0.86 && !categoryNames.contains(text) && !isCatOrDog) {
        allDetections.add('${label.label}:${confidence.toStringAsFixed(2)}');
      }

      // Fix #3, #9, #10: Detect illustration indicators first
      if (_isIllustrationLabel(text)) {
        hasIllustrationIndicator = true;
        developer.log('🎨 Illustration indicator: "$text"');
      }

      // Check ALL categories independently (not else-if)
      if (_isPeopleLabel(text)) {
        // Track best people confidence for conflict resolution
        if (confidence > bestPeopleConfidence) {
          bestPeopleConfidence = confidence;
        }
        // Check if this is a STRONG person label (not just clothing/accessories)
        if (_isStrongPersonLabel(text) && confidence >= 0.55) {
          hasStrongPersonLabel = true;
        }

        // SIMPLIFIED PEOPLE DETECTION (v16)
        // Skip known false positives
        if (_isLowConfidenceFalsePeople(text)) {
          developer.log(
            '  🚫 Skipped false people match "$text" - known false positive',
          );
        } else if (_isDirectPeopleLabel(text)) {
          // Direct labels: body parts + human terms
          directPeopleCount++;
          if (confidence >= 0.50) {
            directPeopleModerateCount++;
          }
          developer.log(
            '  → Direct people label: "$text" (${(confidence * 100).toInt()}%) [count: $directPeopleCount, moderate: $directPeopleModerateCount]',
          );
        } else if (_isClothingLabel(text) && confidence >= 0.50) {
          // Clothing labels: supporting evidence only
          clothingCount++;
          developer.log(
            '  → Clothing label: "$text" (${(confidence * 100).toInt()}%) [count: $clothingCount]',
          );
        }
      }
      if (_isAnimalLabel(text)) {
        // Track animal labels at any confidence for count-based detection
        if (!_isNonAnimalPattern(text)) {
          detectedAnimalTypes.add(text);
          animalConfidences[text] = confidence;
          developer.log(
            '🐾 Animal "$text" (${(confidence * 100).toInt()}%) - tracking for count-based',
          );
        }
        // Animal threshold 75% for single high-confidence detection
        if (confidence < 0.75) {
          // Will be handled by count-based logic below
        } else if (_isNonAnimalPattern(text)) {
          // FIX: Skip animal detection for pattern/texture labels
          developer.log('🎨 Skipping animal for pattern/texture: "$text"');
        } else {
          categories.add('animals');
          if (confidence > bestAnimalConfidence) {
            bestAnimalConfidence = confidence;
            bestAnimalLabel = text;
          }
        }
      }
      // Track animal indicators (fur, paw, tail, whisker) separately
      if (_isAnimalIndicator(text) && confidence >= 0.50) {
        hasFurOrAnimalIndicator = true;
        developer.log(
          '🐾 Animal indicator: "$text" (${(confidence * 100).toInt()}%)',
        );
      }
      // Food detection with confidence tracking
      // FIX #7: Only add food category if STRONG food label detected (actual food items)
      // Weak food labels (restaurant, cooking, bottle) alone should not categorize as food
      if (_isFoodLabel(text)) {
        // FIX #6: Flowers/plants are NEVER food
        // Skip food detection entirely for flower/plant labels
        if (text.contains('flower') ||
            text.contains('petal') ||
            text.contains('plant') ||
            text.contains('bloom') ||
            text.contains('blossom')) {
          developer.log('🌸 Skipping food for flower/plant: "$text"');
        } else if (confidence < 0.75) {
          // Food threshold slightly lower (75%) to catch more food photos
          developer.log(
            '🍕 Skipping food "$text" - below 75% threshold (${(confidence * 100).toInt()}%)',
          );
        } else {
          // Check if this is a STRONG food label (actual food item, not just context)
          if (_isStrongFoodLabel(text)) {
            hasStrongFoodLabel = true;
            categories.add('food');
          }
        }
      }
      // Document detection - require 86% confidence (same as visibility threshold)
      if (_isDocumentLabel(text) && confidence >= minCategoryConfidence) {
        categories.add('document');
        if (confidence > bestDocumentConfidence) {
          bestDocumentConfidence = confidence;
        }
      }
      // Scenery detection - count strong labels, need 2+ for real scenery
      // Scenery threshold slightly lower (75%) to catch more landscape photos
      if (_isSceneryLabel(text) && confidence >= 0.75) {
        if (!_isWeakSceneryLabel(text)) {
          strongSceneryCount++;
        }
        // Don't add scenery yet - we'll check for screenshot+text combo after the loop
        categories.add('scenery');
      }
      // Track screenshot detection for subtag
      if (text.contains('screenshot') || text.contains('screen')) {
        hasScreenshot = true;
      }
      // Track text detection (screenshots often have text with sky-like backgrounds)
      if (text.contains('text') ||
          text.contains('font') ||
          text.contains('writing') ||
          text.contains('letter') ||
          text.contains('number') ||
          text.contains('handwriting')) {
        hasTextLabel = true;
      }
    }

    // FIX #4: GLOBAL CONFIDENCE THRESHOLD
    // If no label reached 86% confidence AND no strong food detected, return "other"
    // Food is exempt because ML Kit is good at detecting food items
    // This filters out uncertain/blurry photos with only weak detections
    if (highestConfidence < 0.86 && !hasStrongFoodLabel) {
      developer.log(
        '📦 Global threshold not met - highest confidence ${(highestConfidence * 100).toInt()}% < 86%, no strong food → Other',
      );
      return LocalTagResult(tags: ['other'], allDetections: allDetections);
    }

    // FIX: Screenshots with text should NOT be scenery - classify as Other
    // Monochromatic screenshot backgrounds often get detected as "sky"
    if ((hasScreenshot || hasTextLabel) && categories.contains('scenery')) {
      categories.remove('scenery');
      categories.add('other');
      developer.log(
        '🖼️ Changed scenery → other - screenshot/text detected (sky-like background)',
      );
    }

    // SIMPLIFIED PEOPLE DETECTION (v16)
    // Rule: 2+ direct at moderate conf (≥50%), OR 3+ direct at any conf, OR 1+ direct + 2+ clothing
    bool shouldAddPeople = false;
    String peopleReason = '';

    if (hasIllustrationIndicator) {
      // Illustrations/cartoons/toys are NOT people (even with human-like features)
      shouldAddPeople = false;
      peopleReason = 'illustration detected';
      developer.log('🎨 Not adding people - $peopleReason');
    } else if (hasFurOrAnimalIndicator && directPeopleCount < 3) {
      // Animal indicators present - need strong people evidence
      shouldAddPeople = false;
      peopleReason = 'animal indicator with weak people evidence';
      developer.log('🐾 Not adding people - $peopleReason');
    } else if (directPeopleModerateCount >= 2) {
      // 2+ direct labels at moderate confidence (≥50%) = definitely people
      shouldAddPeople = true;
      peopleReason =
          '2+ direct labels at moderate confidence ($directPeopleModerateCount)';
    } else if (directPeopleCount >= 3) {
      // 3+ direct labels at any confidence = corroborating evidence = people
      shouldAddPeople = true;
      peopleReason = '3+ direct labels corroborating ($directPeopleCount)';
    } else if (directPeopleCount >= 1 && clothingCount >= 2) {
      // 1+ direct + 2+ clothing = body confirms clothes are worn = people
      shouldAddPeople = true;
      peopleReason =
          'direct label + clothing combo ($directPeopleCount direct, $clothingCount clothing)';
    }

    if (shouldAddPeople) {
      categories.add('people');
      developer.log('👤 Added people: $peopleReason');
    } else if (directPeopleCount > 0 || clothingCount > 0) {
      developer.log(
        '🚫 Not adding people - insufficient evidence (direct:$directPeopleCount, moderate:$directPeopleModerateCount, clothing:$clothingCount)',
      );
    }

    // SIMPLIFIED ANIMAL DETECTION (v16)
    // Same logic as people: multiple low-confidence detections = real animal
    // Rule: 2+ animal labels at ≥50% OR 3+ at any OR indicator + 1 label
    if (!categories.contains('animals')) {
      final animalCount = detectedAnimalTypes.length;
      // Count how many have moderate confidence (≥50%)
      final moderateAnimalCount = animalConfidences.values
          .where((c) => c >= 0.50)
          .length;

      // Pick best confidence label (used in logging)
      String? bestAnimal;
      double bestAnimalConf = 0;
      for (final entry in animalConfidences.entries) {
        if (entry.value > bestAnimalConf) {
          bestAnimalConf = entry.value;
          bestAnimal = entry.key;
        }
      }

      if (moderateAnimalCount >= 2) {
        // 2+ animal labels at ≥50% = definitely animals
        categories.add('animals');
        bestAnimalLabel = bestAnimal;
        bestAnimalConfidence = bestAnimalConf;
        developer.log(
          '🐾 Added animals: 2+ labels at ≥50% ($moderateAnimalCount moderate: ${detectedAnimalTypes.join(", ")})',
        );
      } else if (animalCount >= 3) {
        // 3+ animal labels at any confidence = corroborating evidence
        categories.add('animals');
        bestAnimalLabel = bestAnimal;
        bestAnimalConfidence = bestAnimalConf;
        developer.log(
          '🐾 Added animals: 3+ labels corroborating ($animalCount: ${detectedAnimalTypes.join(", ")})',
        );
      } else if (hasFurOrAnimalIndicator && animalCount >= 1) {
        // Fur/paw/tail + at least one animal label = animals
        categories.add('animals');
        bestAnimalLabel = bestAnimal;
        bestAnimalConfidence = bestAnimalConf;
        developer.log(
          '🐾 Added animals: indicator + label combo ($animalCount labels)',
        );
      }
    }

    // CONFLICT RESOLUTION: When both people AND animals detected, check evidence strength
    if (categories.contains('people') && categories.contains('animals')) {
      // If we have strong direct people evidence (2+ moderate OR 3+ any), keep people
      // Otherwise let animal win if its confidence is significantly higher
      if (directPeopleModerateCount >= 2 || directPeopleCount >= 3) {
        // Strong people evidence - keep both or remove animals
        developer.log(
          '🔄 Conflict: Keeping people (strong evidence: $directPeopleCount direct)',
        );
      } else if (bestAnimalConfidence > bestPeopleConfidence + 0.15) {
        categories.remove('people');
        developer.log(
          '🔄 Conflict: Removed people in favor of animals (${bestAnimalLabel ?? "?"}: ${(bestAnimalConfidence * 100).toInt()}%)',
        );
      }
    }

    // SCENERY FILTER: Require 2+ strong scenery labels for real scenery
    // Single labels like "statue", "outdoor", "sky" alone = not enough
    // Combos like sky+water, buildings+sky, forest+nature = real scenery
    if (categories.contains('scenery') && strongSceneryCount < 2) {
      categories.remove('scenery');
      developer.log(
        '🔄 Removed scenery - only $strongSceneryCount strong label(s), need 2+ (sky+water, etc.)',
      );
    }

    // SCENERY vs PEOPLE CONFLICT: People detection takes priority over scenery
    if (categories.contains('scenery') && categories.contains('people')) {
      categories.remove('scenery');
      developer.log(
        '🔄 Removed scenery - people detected, keeping people category',
      );
    }

    // DOCUMENT FILTER: Require strong document indicators
    // Just "text" or "writing" with a colorful/complex background is not a document
    if (categories.contains('document') && categories.length > 1) {
      // If we also detected people/animals/food, it's probably not a document
      if (categories.contains('people') ||
          categories.contains('animals') ||
          categories.contains('food')) {
        categories.remove('document');
        developer.log('🔄 Removed document - other primary content detected');
      }
    }

    // FIX #8: Room with furniture should be Other, not document
    // If we detect room/furniture/indoor labels, it's not a document
    final hasRoomOrFurniture = allDetections.any((d) {
      final lower = d.toLowerCase();
      return lower.contains('room') ||
          lower.contains('furniture') ||
          lower.contains('couch') ||
          lower.contains('sofa') ||
          lower.contains('chair') ||
          lower.contains('table') ||
          lower.contains('bed') ||
          lower.contains('living') ||
          lower.contains('bedroom') ||
          lower.contains('kitchen') ||
          lower.contains('interior');
    });
    if (categories.contains('document') && hasRoomOrFurniture) {
      categories.remove('document');
      developer.log(
        '🔄 Removed document - room/furniture detected (should be Other)',
      );
    }

    // Priority order: people > animals > food > document > scenery
    // If person is detected, that MUST be the main category (even if document/screenshot also detected)

    // FIX #9: Baby/child in plush/costume should be People, not Animals
    // If we detect baby/child/infant AND costume/plush/stuffed, prioritize people
    final hasBabyOrChild = allDetections.any((d) {
      final lower = d.toLowerCase();
      return lower.contains('baby') ||
          lower.contains('infant') ||
          lower.contains('toddler') ||
          lower.contains('child') ||
          lower.contains('kid');
    });
    final hasCostumeOrPlush = allDetections.any((d) {
      final lower = d.toLowerCase();
      return lower.contains('costume') ||
          lower.contains('plush') ||
          lower.contains('stuffed') ||
          lower.contains('toy') ||
          lower.contains('mascot') ||
          lower.contains('onesie');
    });
    if (hasBabyOrChild && hasCostumeOrPlush && categories.contains('animals')) {
      categories.remove('animals');
      if (!categories.contains('people')) {
        categories.add('people');
      }
      developer.log(
        '👶 Baby/child in costume - prioritizing People over Animals',
      );
    }

    // FIX #6: Flowers/plants should be Other, not Food
    // If we detect multiple flower/plant indicators, it's likely a floral photo, not food
    final flowerPlantIndicators = allDetections.where((d) {
      final lower = d.toLowerCase();
      return lower.contains('flower') ||
          lower.contains('petal') ||
          lower.contains('plant') ||
          lower.contains('bloom') ||
          lower.contains('blossom') ||
          lower.contains('floral') ||
          lower.contains('bouquet') ||
          lower.contains('vase');
    }).length;

    // If 2+ flower/plant indicators detected, this is flowers not food
    if (flowerPlantIndicators >= 2 && categories.contains('food')) {
      categories.remove('food');
      developer.log(
        '🌸 Removed food - $flowerPlantIndicators flower/plant indicators detected',
      );
    }

    // FIX: Flowers should be Other, not Scenery
    // A photo focused on flowers/plants is not landscape/scenery
    if (flowerPlantIndicators >= 1 && categories.contains('scenery')) {
      // Check if there are STRONG scenery indicators beyond just garden/tree
      final hasStrongScenery = allDetections.any((d) {
        final lower = d.toLowerCase();
        return lower.contains('landscape') ||
            lower.contains('mountain') ||
            lower.contains('beach') ||
            lower.contains('ocean') ||
            lower.contains('sunset') ||
            lower.contains('sunrise') ||
            lower.contains('panorama') ||
            lower.contains('horizon');
      });
      if (!hasStrongScenery) {
        categories.remove('scenery');
        developer.log(
          '🌸 Removed scenery - flower/plant photo without strong landscape indicators',
        );
      }
    }

    // NOTE: Food is a CATEGORY derived from detected food items (cake, pie, etc.)
    // It should NOT be added as an object or have confidence-based fallback

    // FIX #7: Check if ANY category has STRONG evidence
    // Only include categories that passed strong filters (not weak defaults)
    bool hasStrongCategory = false;

    if (categories.contains('people') &&
        (directPeopleModerateCount >= 2 ||
            directPeopleCount >= 3 ||
            hasStrongPersonLabel)) {
      hasStrongCategory = true;
    }
    if (categories.contains('animals') && detectedAnimalTypes.isNotEmpty) {
      hasStrongCategory = true;
    }
    if (categories.contains('food') && hasStrongFoodLabel) {
      // Already only added if hasStrongFoodLabel is true
      hasStrongCategory = true;
    }
    if (categories.contains('document') && bestDocumentConfidence >= 0.65) {
      hasStrongCategory = true;
    }
    if (categories.contains('scenery') && strongSceneryCount >= 2) {
      hasStrongCategory = true;
    }

    final prioritized = <String>[];
    if (categories.contains('people')) prioritized.add('people');
    if (categories.contains('animals')) prioritized.add('animals');
    if (categories.contains('food')) prioritized.add('food');
    if (categories.contains('document')) prioritized.add('document');
    if (categories.contains('scenery')) prioritized.add('scenery');

    // Build final tags: ONLY the main category (single tag for display)
    // Screenshot goes to allDetections, not as a category
    final resultTags = <String>[];
    if (prioritized.isNotEmpty && hasStrongCategory) {
      resultTags.add(prioritized.first);
      // Screenshot is added to allDetections, not as a tag
    } else {
      // FIX #7: Default to 'other' if NO STRONG category found
      // This prevents weak indicators from forcing incorrect categories
      // 'Other' is the default when no category has sufficient strong evidence
      resultTags.add('other');
      developer.log(
        '📦 Defaulting to Other - no strong category found (weak labels only): ${allDetections.join(", ")}',
      );
    }

    // Add screenshot to allDetections if detected (so it shows as an object)
    if (hasScreenshot && !allDetections.contains('Screenshot')) {
      allDetections.add('Screenshot');
    }

    // ANIMAL DEDUPLICATION: Smart logic for single vs multiple animals
    // - If illustration/cartoon → likely 1 animal, keep best only
    // - If confidence gap is large (>10%) → likely 1 animal, keep best only
    // - If only cat+dog detected (common misidentification) → keep best only
    // - If confidences are similar AND different species → likely multiple animals, keep all
    if (detectedAnimalTypes.length > 1) {
      bool shouldDeduplicate = false;
      String dedupeReason = '';

      // Case 1: Illustration/cartoon - ML Kit often confused (fox = cat + dog)
      if (hasIllustrationIndicator) {
        shouldDeduplicate = true;
        dedupeReason = 'illustration detected';
      }
      // Case 2: Only cat and dog detected - very common misidentification
      // FIX #13: If ONLY these two, keep best (ML Kit often sees both in single pet)
      else if (detectedAnimalTypes.length == 2 &&
          detectedAnimalTypes.contains('cat') &&
          detectedAnimalTypes.contains('dog')) {
        shouldDeduplicate = true;
        dedupeReason = 'cat+dog only (common misidentification)';
      }
      // Case 3: Large confidence gap - likely 1 animal misidentified
      else if (bestAnimalLabel != null) {
        // Find second-best confidence
        double secondBestConfidence = 0.0;
        String? secondBestLabel;
        for (final entry in animalConfidences.entries) {
          if (entry.key != bestAnimalLabel &&
              entry.value > secondBestConfidence) {
            secondBestConfidence = entry.value;
            secondBestLabel = entry.key;
          }
        }
        // If gap is >10%, likely 1 animal
        final confidenceGap = bestAnimalConfidence - secondBestConfidence;
        if (confidenceGap > 0.10) {
          shouldDeduplicate = true;
          dedupeReason =
              'confidence gap ${(confidenceGap * 100).toInt()}% ($bestAnimalLabel: ${(bestAnimalConfidence * 100).toInt()}% vs ${secondBestLabel ?? "?"}: ${(secondBestConfidence * 100).toInt()}%)';
        } else {
          developer.log(
            '🐾 Multiple animals detected with similar confidence - keeping all: ${animalConfidences.entries.map((e) => "${e.key}: ${(e.value * 100).toInt()}%").join(", ")}',
          );
        }
      }

      if (shouldDeduplicate) {
        // Keep only the best animal label in allDetections
        final animalLabelsToRemove = detectedAnimalTypes
            .where((a) => a != bestAnimalLabel)
            .toList();
        for (final animalType in animalLabelsToRemove) {
          // FIX #3: allDetections format is 'Label:0.72' so use startsWith to match
          // Also handle case where confidence suffix might not be present (legacy data)
          allDetections.removeWhere((d) {
            final dLower = d.toLowerCase();
            final animalLower = animalType.toLowerCase();
            // Match 'cat:0.72' against 'cat' - check if label part matches
            final colonIndex = dLower.lastIndexOf(':');
            if (colonIndex > 0) {
              final labelPart = dLower.substring(0, colonIndex);
              return labelPart == animalLower;
            }
            // Legacy format without confidence
            return dLower == animalLower;
          });
        }
        developer.log(
          '🦊 Deduplicated animals ($dedupeReason) - kept "$bestAnimalLabel", removed: $animalLabelsToRemove',
        );
      }
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
    // FIX #8: EXCLUSIONS - these falsely trigger people but aren't
    const peopleExclusions = [
      'bird', // Bird has nothing to do with people
      'flesh', // "flesh" detected on rocks, fruit, etc. - common false positive
    ];

    // Check exclusions first
    if (peopleExclusions.any((k) => label.contains(k))) {
      return false;
    }

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
      // Clothing worn by people (CRITICAL for people detection)
      'dress',
      'jacket',
      'coat',
      'sweater',
      'shirt',
      'blouse',
      'suit',
      'tuxedo',
      'gown',
      'outwear',
      'outerwear',
      'hoodie',
      'cardigan',
      'vest',
      'uniform',
      'costume',
      'attire',
      'apparel',
      'jeans',
      'pants',
      'trousers',
      'shorts',
      'skirt',
      'legging',
      // Body features unique to humans
      'hair',
      'skin',
      'beard',
      'mustache',
      'tattoo',
      'makeup',
      'hairstyle',
      // Drinking/eating contexts with people
      'cheers',
      'toast',
      // Actions/poses/emotions specific to humans
      'smile',
      'smil', // covers smiling, smiled
      'grin',
      'frown',
      'expression',
      'laughing',
      'posing',
      'dancing',
      'singing',
      'clapping',
      'waving',
      'happy',
      'joy',
      // Note: removed 'fun', 'cool', 'show', 'play', 'standing', 'sitting', 'drinking'
      // - these cause false positives (display, showcase, playful, function, cooling)
      'leisure', // leisure activities involve people
      'walking', // person walking
      'jogging',
      'hiking',
      'cycling',
      'swimming',
      'exercising',
      'workout',
      'fitness',
      // Headphones/earbuds (humans wear these, not animals)
      'headphone',
      'earphone',
      'earbud',
      'headset',
    ];
    return peopleKeywords.any((k) => label.contains(k));
  }

  /// STRONG person labels - definitely indicate a human is present
  /// Used to validate people category when weak labels are also detected
  static bool _isStrongPersonLabel(String label) {
    const strongLabels = [
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
      'beard',
      'mustache',
      'smiling',
      'laughing',
      'eyelash',
      'eyebrow',
      'forehead',
      'chin',
      'cheek',
      // Human-specific body features (animals have fur, not hair/skin)
      'hair',
      'skin',
      // Back-facing people (CRITICAL - don't delete photos of people from behind)
      'back',
      'shoulder',
      'torso',
      'silhouette',
      'posture',
      // Group/team context (CRITICAL for family photos)
      'crew',
      'team',
      'audience',
      // Poses/actions that indicate humans (CRITICAL - prevent Other categorization)
      // Note: removed 'sitting', 'standing' - too generic, can apply to objects/furniture
      'pose',
      'posing',
      // Facial expressions (CRITICAL - smile = person)
      'smile',
      'smil', // covers smiling, smiled, smile
      'grin',
      'frown',
      'expression',
      // NOTE: Clothing removed from strong labels - a single clothing item
      // could be on a rack, mannequin, or in a store. Use tier2 system instead
      // which requires 2+ clothing items for people classification.
    ];
    return strongLabels.any((k) => label.contains(k));
  }

  static bool _isAnimalLabel(String label) {
    // EXCLUSIONS: Plants are NOT animals
    const plantExclusions = [
      'plant',
      'flower',
      'petal',
      'leaf',
      'tree',
      'bush',
      'shrub',
      'grass',
      'fern',
      'moss',
      'vine',
      'bloom',
      'blossom',
      'flora',
      'garden',
      'botanical',
    ];

    // EXCLUSIONS: Objects/vehicles/rooms are NOT animals
    // FIX #11, #12: These were incorrectly triggering animal detection
    const objectExclusions = [
      'vehicle',
      'car',
      'truck',
      'bus',
      'motorcycle',
      'bicycle',
      'tire',
      'wheel',
      'desk',
      'room',
      'office',
      'building',
      'house',
      'screenshot',
      'screen',
      'paper',
      'document',
      'selfie',
      'portrait',
      'person',
      'human',
      'people',
      'man',
      'woman',
      'boy',
      'girl',
      'face',
      'furniture',
      'chair',
      'table',
      'couch',
      'bed',
      'cabinet',
      'shelf',
      'food',
      'meal',
      'dish',
      'plate',
      'clothing',
      'shirt',
      'dress',
      'poster',
      'art',
      'painting',
      'drawing',
      // FIX #15: Human body parts should NOT trigger animals
      'hand',
      'finger',
      'nail',
      'skin',
      'flesh',
      'arm',
      'leg',
      'foot',
      'toe',
      'body',
      'torso',
      'chest',
      'shoulder',
      'neck',
      'muscle',
      'hair',
      'beard',
      'eyelash',
      'eyebrow',
      'lip',
      'nose',
      'ear',
      'eye',
      // FIX #16: Objects/materials that are NOT animals
      'musical instrument',
      'instrument',
      'guitar',
      'piano',
      'drum',
      'violin',
      'metal',
      'steel',
      'iron',
      'aluminum',
      'plastic',
      'glass',
      'wood',
      'stone',
      'concrete',
      'brick',
    ];

    // Check exclusions first
    if (plantExclusions.any((k) => label.contains(k))) {
      return false;
    }
    if (objectExclusions.any((k) => label.contains(k))) {
      return false;
    }

    const animalKeywords = [
      // Generic
      'animal',
      'pet',
      'wildlife',
      'mammal',
      'reptile',
      'amphibian',
      'creature',
      'beast',
      // Pets / Domestic
      'dog',
      'cat',
      'puppy',
      'kitten',
      'hamster',
      'rabbit',
      'bunny',
      'guinea pig',
      'ferret',
      'gerbil',
      'chinchilla',
      'goldfish',
      'parrot',
      'parakeet',
      'canary',
      'cockatiel',
      'budgie',
      // Farm animals
      'horse',
      'pony',
      'donkey',
      'mule',
      'cow',
      'cattle',
      'bull',
      'calf',
      'sheep',
      'lamb',
      'goat',
      'pig',
      'hog',
      'boar',
      'chicken',
      'rooster',
      'hen',
      'chick',
      'duck',
      'goose',
      'turkey',
      'llama',
      'alpaca',
      // Wild mammals - Africa/Asia
      'elephant',
      'lion',
      'tiger',
      'leopard',
      'cheetah',
      'jaguar',
      'panther',
      'hyena',
      'zebra',
      'giraffe',
      'hippo',
      'hippopotamus',
      'rhino',
      'rhinoceros',
      'gorilla',
      'chimpanzee',
      'chimp',
      'orangutan',
      'baboon',
      'mandrill',
      'monkey',
      'ape',
      'primate',
      'camel',
      'buffalo',
      'bison',
      'antelope',
      'gazelle',
      'wildebeest',
      'warthog',
      'meerkat',
      // Wild mammals - Americas
      'bear',
      'grizzly',
      'panda',
      'wolf',
      'coyote',
      'fox',
      'deer',
      'elk',
      'moose',
      'caribou',
      'reindeer',
      'bison',
      'cougar',
      'puma',
      'mountain lion',
      'bobcat',
      'lynx',
      'raccoon',
      'skunk',
      'opossum',
      'armadillo',
      'porcupine',
      'beaver',
      'otter',
      'badger',
      'wolverine',
      'weasel',
      'mink',
      'ferret',
      // Wild mammals - Australia/Other
      'kangaroo',
      'koala',
      'wombat',
      'platypus',
      'wallaby',
      'tasmanian',
      'dingo',
      'sloth',
      'anteater',
      'tapir',
      'capybara',
      'lemur',
      'mongoose',
      // Small mammals
      'squirrel',
      'chipmunk',
      'mouse',
      'mice',
      'rat',
      'mole',
      'shrew',
      'hedgehog',
      'bat',
      'hare',
      // Marine mammals
      'dolphin',
      'whale',
      'orca',
      'porpoise',
      'seal',
      'sea lion',
      'walrus',
      'manatee',
      'dugong',
      // Birds - Common
      'bird',
      'sparrow',
      'robin',
      'cardinal',
      'bluejay',
      'finch',
      'crow',
      'raven',
      'magpie',
      'pigeon',
      'dove',
      'seagull',
      'gull',
      'pelican',
      'heron',
      'crane',
      'stork',
      'egret',
      'flamingo',
      'swan',
      'goose',
      // Birds - Raptors
      'owl',
      'eagle',
      'hawk',
      'falcon',
      'vulture',
      'condor',
      'kite',
      'osprey',
      // Birds - Tropical/Exotic
      'penguin',
      'toucan',
      'macaw',
      'cockatoo',
      'peacock',
      'peafowl',
      'pheasant',
      'quail',
      'ostrich',
      'emu',
      'kiwi',
      'hummingbird',
      'kingfisher',
      'woodpecker',
      'puffin',
      'albatross',
      // Reptiles
      'turtle',
      'tortoise',
      'snake',
      'python',
      'cobra',
      'viper',
      'boa',
      'lizard',
      'gecko',
      'iguana',
      'chameleon',
      'komodo',
      'monitor',
      'skink',
      'crocodile',
      'alligator',
      'caiman',
      'dinosaur',
      // Amphibians
      'frog',
      'toad',
      'salamander',
      'newt',
      'axolotl',
      // Fish
      'fish',
      'salmon',
      'trout',
      'tuna',
      'bass',
      'cod',
      'carp',
      'catfish',
      'goldfish',
      'koi',
      'betta',
      'guppy',
      'angelfish',
      'clownfish',
      'piranha',
      'barracuda',
      'swordfish',
      'marlin',
      'eel',
      'ray',
      'stingray',
      'manta',
      // Sharks
      'shark',
      // Invertebrates - Marine
      'crab',
      'lobster',
      'shrimp',
      'prawn',
      'crawfish',
      'crayfish',
      'octopus',
      'squid',
      'jellyfish',
      'starfish',
      'sea star',
      'seahorse',
      'sea urchin',
      'coral',
      'anemone',
      'clam',
      'oyster',
      'mussel',
      'scallop',
      'snail',
      'slug',
      'nautilus',
      // Insects
      'insect',
      'bug',
      'butterfly',
      'moth',
      'bee',
      'wasp',
      'hornet',
      'ant',
      'termite',
      'beetle',
      'ladybug',
      'ladybird',
      'firefly',
      'dragonfly',
      'damselfly',
      'grasshopper',
      'cricket',
      'locust',
      'mantis',
      'cockroach',
      'fly',
      'mosquito',
      'gnat',
      'flea',
      'tick',
      'caterpillar',
      'larva',
      'maggot',
      'cicada',
      // Arachnids
      'spider',
      'tarantula',
      'scorpion',
      // Other invertebrates
      'worm',
      'earthworm',
      'leech',
      'centipede',
      'millipede',
    ];
    // Simple contains check - fast and sufficient with 86% threshold
    return animalKeywords.any((k) => label.contains(k));
  }

  static bool _isFoodLabel(String label) {
    // EXCLUSIONS: Items that should NEVER trigger food category
    // Fix #2: Footwear (flipflops tagged as food)
    // Fix #4: Packaging/products (napkins, toys)
    // Fix #5: Accessories (hair accessories, tableware without food)
    // Fix #7: Hygiene products (tampax)
    const foodExclusions = [
      // Footwear
      'flipflop',
      'flip flop',
      'sandal',
      'shoe',
      'slipper',
      'sneaker',
      'boot',
      'heel',
      'loafer',
      'footwear',
      // Packaging/products (not actual food)
      'package',
      'packaging',
      'wrapper',
      'napkin',
      'tissue',
      'paper towel',
      'towel',
      'toy',
      'product',
      // Hygiene products
      'tampon',
      'pad',
      'hygiene',
      'sanitary',
      'diaper',
      'wipe',
      // Hair accessories (tableware without food)
      'hair clip',
      'hairclip',
      'hairband',
      'hair band',
      'scrunchie',
      'barrette',
      'headband',
      'hair tie',
      'bobby pin',
      'hair accessory',
      // Other non-food items
      'accessory',
      'decoration',
      'ornament',
    ];

    // Check exclusions first - if any exclusion matches, NOT food
    if (foodExclusions.any((k) => label.contains(k))) {
      return false;
    }

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
      // Fix #1: Add bottle/container for beverages
      'bottle',
      'cup',
      'glass',
      'mug',
      'can',
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
      // Note: kitchen, plate, bowl, sink removed - don't indicate actual food present
      // Only tag as food if actual food items are detected
      'hotdog',
      'hot dog',
      'drumstick',
      'chicken',
      'steak',
      'sushi',
      'noodle',
      'taco',
      'burrito',
      'fries',
      'donut',
      'doughnut',
      'croissant',
      'muffin',
      'pancake',
      'waffle',
    ];
    return foodKeywords.any((k) => label.contains(k));
  }

  /// STRONG food labels - actual food items (not context like restaurant/cooking)
  /// Used to prevent weak people context (celebration/party) from overriding food
  static bool _isStrongFoodLabel(String label) {
    // Actual food items that definitely indicate food is the subject
    const strongFoodKeywords = [
      // Generic food terms (high confidence = definitely food)
      'food',
      'meal',
      'cuisine',
      'dish',
      'recipe',
      'cooking',
      'baking',
      // Meal times
      'breakfast',
      'lunch',
      'dinner',
      'snack',
      'dessert',
      // Baked goods / desserts
      'cake',
      'cookie',
      'ice cream',
      'chocolate',
      'candy',
      'donut',
      'doughnut',
      'croissant',
      'muffin',
      'pancake',
      'waffle',
      'pie',
      'pastry',
      'bread',
      // Main dishes
      'pizza',
      'burger',
      'sandwich',
      'pasta',
      'rice',
      'sushi',
      'taco',
      'burrito',
      'hotdog',
      'hot dog',
      'steak',
      'chicken',
      'drumstick',
      'noodle',
      'fries',
      'soup',
      'salad',
      'meat',
      'fish',
      'seafood',
      // Fruits & vegetables
      'fruit',
      'vegetable',
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
      // Dairy & protein
      'egg',
      'cheese',
      'milk',
      // Drinks (actual beverages, not just containers)
      'coffee',
      'tea',
      'juice',
      'wine',
      'beer',
      'beverage',
      'drink',
    ];
    return strongFoodKeywords.any((k) => label.contains(k));
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
      // Note: 'poster' removed - often decorative/artistic, not a document
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
      // Strong outdoor/nature scenery
      'landscape',
      'scenery',
      'nature',
      'outdoor',
      // Sky/cloud - strong outdoor indicators (restored)
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
      // Urban outdoor scenery
      'city',
      'street',
      'road',
      'bridge',
      // Note: 'tower', 'skyscraper' removed - often falsely detected on electronic boards
      'castle',
      'church',
      'temple',
      'monument',
      // Note: 'statue' removed - often inside museums/buildings, not outdoor scenery
      // Natural landscapes
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
      // Note: 'building', 'architecture', 'flower', 'plant' removed
      // - building/architecture are too generic (appear in any photo with structures)
      // - flower/plant overlap with food and can misclassify
    ];
    return sceneryKeywords.any((k) => label.contains(k));
  }

  /// Weak scenery labels - indoor/product labels that shouldn't trigger scenery category
  /// These are often detected in shopping/indoor photos and don't represent actual scenery
  static bool _isWeakSceneryLabel(String label) {
    const weakLabels = [
      'building',
      'architecture',
      'room',
      'interior',
      'shelf',
      'shelving',
      'product',
      'products',
      'display',
      'store',
      'shop',
      'retail',
      'furniture',
      'wall',
      'floor',
      'ceiling',
      'window',
      'door',
      // Indoor furniture that doesn't indicate outdoor scenery
      'couch',
      'sofa',
      'chair',
      'table',
      'desk',
      'bed',
      // Art/sculptures are typically indoors in museums
      'statue',
      'sculpture',
      'art',
      'museum',
      'gallery',
      // Skyscraper often falsely detected on electronic boards/screens
      'skyscraper',
      'tower',
      // Mobile phone screenshots often have these
      'mobile phone',
      'phone',
    ];
    return weakLabels.any((k) => label.contains(k));
  }

  // ============ Fix #3, #9, #10: Tier-based People Detection ============

  /// Illustration indicators - if detected, suppress people classification
  /// Cartoons, drawings, toys should NOT be tagged as people
  static bool _isIllustrationLabel(String label) {
    const illustrationKeywords = [
      'cartoon',
      'illustration',
      'drawing',
      'animation',
      'artwork',
      'character',
      'anime',
      'comic',
      'sketch',
      'painting',
      'art',
      'graphic',
      'logo',
      'icon',
      'vector',
      'clipart',
      'doodle',
      'caricature',
      'puppet',
      'figurine',
      'toy',
      'doll',
      'statue',
      'sculpture',
      'mannequin',
    ];
    return illustrationKeywords.any((k) => label.contains(k));
  }

  /// ISSUE #3 FIX: Known false positives for people detection at low confidence
  /// These should NEVER trigger people classification regardless of confidence
  static bool _isLowConfidenceFalsePeople(String label) {
    const falsePeopleKeywords = [
      'flesh', // Detected on rocks, fruit, backgrounds - very unreliable
      'bird', // Definitely not people - animal indicator got confused
      'jacked', // Slang for muscular, too vague and false positives on objects
    ];
    return falsePeopleKeywords.any((k) => label.contains(k));
  }

  /// SIMPLIFIED v16: Direct people labels - body parts + human terms
  /// These directly indicate a person is present (not just clothing/accessories)
  static bool _isDirectPeopleLabel(String label) {
    const directKeywords = [
      // Human terms
      'person', 'human', 'people',
      'man', 'woman', 'child', 'kid', 'baby', 'toddler',
      'boy', 'girl', 'adult', 'teenager', 'elder', 'senior',
      'crowd', 'group', 'family', 'couple',
      // Face/head
      'face', 'selfie', 'portrait', 'headshot',
      'beard', 'mustache', 'moustache',
      'forehead', 'chin', 'cheek', 'jaw', 'eyebrow',
      // Body parts (human-specific)
      'hand', 'finger', 'thumb', 'palm', 'wrist',
      'arm', 'elbow', 'shoulder',
      'hair', 'hairstyle', 'haircut', 'skin',
      // Ambiguous but still direct (body parts)
      'ear', 'eye', 'eyelash', 'nose', 'mouth', 'lip', 'tongue',
      'head', 'neck', 'back', 'leg', 'foot', 'feet', 'toe', 'body',
      'torso', 'chest', 'waist', 'hip', 'thigh',
      // Actions that require a person
      'sleeping', 'smiling', 'laughing', 'crying',
      'sitting', 'standing', 'walking', 'running',
      'pedestrian', 'walker', 'jogger', 'runner', 'cyclist',
      'hiker', 'tourist', 'traveler',
    ];
    return directKeywords.any((k) => label.contains(k));
  }

  /// SIMPLIFIED v16: Clothing labels - supporting evidence only
  /// Need at least 1 direct label to confirm these belong to a real person
  static bool _isClothingLabel(String label) {
    const clothingKeywords = [
      // Clothing
      'shirt', 'blouse', 'dress', 'jacket', 'coat', 'sweater',
      'suit', 'tuxedo', 'gown', 'hoodie', 'cardigan', 'vest',
      'uniform', 'costume', 'jeans', 'pants', 'trousers',
      'shorts', 'skirt', 'legging',
      // Footwear
      'shoe', 'sneaker', 'boot', 'sandal', 'slipper',
      // Accessories
      'hat', 'cap', 'glasses', 'sunglasses',
      'watch', 'jewelry', 'necklace', 'bracelet',
      'tie', 'scarf', 'glove',
    ];
    return clothingKeywords.any((k) => label.contains(k));
  }

  /// Animal-specific indicators - if detected with ambiguous body parts, it's an animal
  static bool _isAnimalIndicator(String label) {
    const animalIndicators = [
      'fur',
      'paw',
      'snout',
      'muzzle',
      'tail',
      'whisker',
      'feather',
      'beak',
      'wing',
      'hoof',
      'claw',
      'fang',
      'mane',
      'antler',
      'horn',
      'scale',
      'fin',
      'gill',
      'shell',
      'tentacle',
      // FIX #4: Animal names should also prevent false people detection
      // If "dog" or "cat" is detected at ANY confidence, don't assume people
      'dog',
      'cat',
      'bird',
      'pet',
      'animal',
      'puppy',
      'kitten',
      'canine',
      'feline',
    ];
    return animalIndicators.any((k) => label.contains(k));
  }

  /// Labels that should NOT trigger animal detection (textures/patterns)
  /// FIX: Pattern/texture photos were incorrectly tagged as animals
  static bool _isNonAnimalPattern(String label) {
    const patternExclusions = [
      'pattern',
      'texture',
      'fabric',
      'textile',
      'material',
      'paper',
      'wallpaper',
      'carpet',
      'rug',
      'design',
      'print',
      'stripe',
      'polka',
      'plaid',
      'checkered',
      'abstract',
      'geometric',
      'mosaic',
      'tile',
    ];
    return patternExclusions.any((k) => label.contains(k));
  }
}
