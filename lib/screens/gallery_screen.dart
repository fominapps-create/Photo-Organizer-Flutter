import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/photo_id.dart';
import '../services/tag_store.dart';
import 'dart:io';
import 'album_screen.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';
import 'photo_viewer.dart';

class GalleryScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;
  final VoidCallback? onAlbumCreated;
  final VoidCallback? onSearchChanged;
  const GalleryScreen({
    super.key,
    this.onSettingsTap,
    this.onAlbumCreated,
    this.onSearchChanged,
  });
  @override
  GalleryScreenState createState() => GalleryScreenState();
}

class GalleryScreenState extends State<GalleryScreen> {
  List<String> imageUrls = [];
  Map<String, List<String>> photoTags = {};
  bool loading = true;
  // Device-local asset storage and thumbnail cache for local view
  final Map<String, AssetEntity> _localAssets = {};
  final Map<String, Uint8List> _thumbCache = {};
  Map<String, List<String>> albums = {};
  String searchQuery = '';
  bool showDebug = false;
  bool _showSearchBar = true;
  bool _sortNewestFirst = true; // true = newest first, false = oldest first
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  int _crossAxisCount = 4;
  bool _isSelectMode = false;
  final Set<String> _selectedKeys = {};
  final Map<String, double> _textWidthCache = {};
  // Auto-scan state
  bool _scanning = false;
  double _scanProgress = 0.0; // 0.0-1.0
  int _scanTotal = 0;
  bool _scanPaused = false;
  int _scanProcessed = 0;
  int _currentUnscannedCount = 0;
  double _lastScale = 1.0; // Track last scale for incremental pinch zoom

  // Performance monitoring
  bool _showPerformanceMonitor = false;
  double _currentRamUsageMB = 0;
  double _peakRamUsageMB = 0;
  int _currentBatchSize = 0;
  int _avgBatchTimeMs = 0;
  double _imagesPerSecond = 0;

  // Background CLIP validation state
  bool _validating = false;
  bool _validationCancelled = false;
  bool _validationPaused = false;
  int _validationTotal = 0;
  int _validationProcessed = 0;
  int _validationAgreements = 0;
  int _validationDisagreements = 0;
  int _validationOverrides = 0;

  // Track changed images for detailed view
  final List<Map<String, dynamic>> _validationChanges = [];
  // Track suggested changes (not yet applied)
  final List<Map<String, dynamic>> _validationSuggestions = [];
  // {url, photoID, oldTags, newTags, reason}

  double _measureTextWidth(String text, TextStyle style) {
    final key = text; // style is constant here, so text is fine as cache key
    if (_textWidthCache.containsKey(key)) return _textWidthCache[key]!;
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = textPainter.size.width;
    _textWidthCache[key] = w;
    return w;
  }

  Widget _buildPerfStat(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTagChipsForWidth(
    List<String> visibleTags,
    List<String> fullTags,
    double maxWidth,
  ) {
    const double horizontalPadding =
        6 * 2; // EdgeInsets.symmetric(horizontal: 6)
    const double chipSpacing = 4.0;
    final TextStyle style = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    );

    double used = 0.0;
    final List<Widget> chips = [];
    final List<double> chipWidths = [];

    for (var t in visibleTags) {
      final textWidth = _measureTextWidth(t, style);
      final w = textWidth + horizontalPadding;
      final nextUsed = chips.isEmpty ? used + w : used + chipSpacing + w;
      if (nextUsed <= maxWidth) {
        // add this chip
        used = nextUsed;
        chipWidths.add(w);
        chips.add(
          GestureDetector(
            onTap: () => _showTagMenu(t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _colorForTag(t),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(t, style: style),
            ),
          ),
        );
      } else {
        // stop trying to add tags that don't fit; we'll consider +N after the loop
        break;
      }
    }

    final hiddenCount = fullTags.length - chips.length;
    if (hiddenCount > 0) {
      final plusStr = '+$hiddenCount';
      final plusWidth = _measureTextWidth(plusStr, style) + horizontalPadding;
      final nextUsed = chips.isEmpty
          ? used + plusWidth
          : used + chipSpacing + plusWidth;
      if (nextUsed <= maxWidth) {
        // If +N fits in remaining width, just add it
        chips.add(
          GestureDetector(
            onTap: () => _showHiddenTagsMenu(fullTags, visibleTags),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(plusStr, style: style),
            ),
          ),
        );
      } else if (chips.isNotEmpty) {
        // If it doesn't fit, see if we can replace the last chip with +N
        final lastChipWidth = chipWidths.isNotEmpty ? chipWidths.last : 0.0;
        final usedWithoutLast = chips.length == 1
            ? 0.0
            : used - (chipSpacing + lastChipWidth);
        final testUsed =
            usedWithoutLast +
            (chips.isEmpty ? plusWidth : chipSpacing + plusWidth);
        if (testUsed <= maxWidth) {
          chips.removeLast();
          chipWidths.removeLast();
          chips.add(
            GestureDetector(
              onTap: () => _showHiddenTagsMenu(fullTags, visibleTags),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(plusStr, style: style),
              ),
            ),
          );
        }
      }
    }

    // If there are no chips (none fit or no short tags), show a 'None' chip
    if (chips.isEmpty && hiddenCount == 0) {
      chips.add(
        GestureDetector(
          onTap: () => searchByTag('None'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('None', style: style),
          ),
        ),
      );
    }

    return chips;
  }

  @override
  void initState() {
    super.initState();
    _updateSystemUI();
    _searchController = TextEditingController(text: searchQuery);
    _searchFocusNode = FocusNode();
    _searchController.addListener(() {
      // keep searchQuery in sync and refresh the suffixIcon
      if (searchQuery != _searchController.text) {
        setState(() {
          searchQuery = _searchController.text;
        });
      }
    });
    _loadAllImages();
    _loadAlbums();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update system UI when theme changes
    _updateSystemUI();
  }

  Future<void> _loadAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final albumsJson = prefs.getString('albums');
      if (albumsJson != null) {
        final Map<String, dynamic> map = json.decode(albumsJson);
        setState(() {
          albums = map.map((k, v) => MapEntry(k, List<String>.from(v)));
        });
        return;
      }
    } catch (_) {}
    setState(() => albums = {});
  }

  Future<void> _loadAllImages() async {
    developer.log('🚀 START: _loadAllImages called');
    setState(() => loading = true);
    developer.log('🔄 Calling _loadOrganizedImages...');
    await _loadOrganizedImages();
    developer.log(
      '✅ _loadOrganizedImages completed. Found ${imageUrls.length} photos',
    );
    await _loadTags();
    developer.log('Total photos in gallery: ${imageUrls.length}');
    setState(() => loading = false);
    // Start automatic scan of local images when appropriate
    developer.log('About to call _updateUnscannedCount()...');
    await _updateUnscannedCount();
    developer.log(
      'After _updateUnscannedCount(), _currentUnscannedCount = $_currentUnscannedCount',
    );
    _startAutoScanIfNeeded();
  }

  Future<void> _updateUnscannedCount() async {
    try {
      final localUrls = imageUrls
          .where((u) => u.startsWith('local:') || u.startsWith('file:'))
          .toList();
      developer.log(
        '📊 Checking unscanned count for ${localUrls.length} photos',
      );
      int unscanned = 0;
      for (final u in localUrls) {
        final photoID = PhotoId.canonicalId(u);
        final tags = await TagStore.loadLocalTags(photoID);
        if (tags == null) unscanned++;
      }
      developer.log('📊 Unscanned count: $unscanned');
      if (mounted) setState(() => _currentUnscannedCount = unscanned);
    } catch (e) {
      developer.log('❌ Error updating unscanned count: $e');
      if (mounted) setState(() => _currentUnscannedCount = 0);
    }
  }

  void reload() => _loadAllImages();

  void focusSearch() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (_showSearchBar) {
        // Small delay to ensure TextField is visible before focusing
        Future.delayed(const Duration(milliseconds: 100), () {
          _searchFocusNode.requestFocus();
        });
      }
    });
  }

  void searchByTag(String tag) {
    setState(() {
      _showSearchBar = true;
      searchQuery = tag;
      _searchController.text = tag;
    });
    widget.onSearchChanged?.call();
  }

  /// Get all unique tags from currently loaded photos
  Set<String> getAllCurrentTags() {
    final allTags = <String>{};
    // Only include tags from photos that actually exist in imageUrls
    for (final url in imageUrls) {
      final key = p.basename(url);
      final tags = photoTags[key] ?? [];
      allTags.addAll(tags);
    }
    return allTags;
  }

  Future<void> _startAutoScanIfNeeded() async {
    // Only scan if there are local images and we aren't already scanning
    if (_scanning) {
      developer.log('⏸️ Scan already in progress');
      return;
    }
    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();
    developer.log('📊 Total local photos: ${localUrls.length}');
    if (localUrls.isEmpty) return;

    // Check server connectivity before scanning
    final serverAvailable = await ApiService.pingServer(
      timeout: const Duration(seconds: 3),
      retries: 1,
    );
    if (!serverAvailable) {
      developer.log('⚠️ Server not available, skipping auto-scan');
      return;
    }

    // Only consider images that have no persisted scan entry.
    // Check using canonical photoID keys from TagStore (bulk check for speed)
    final photoIDs = localUrls.map((u) => PhotoId.canonicalId(u)).toList();
    final scannedIDs = await TagStore.getPhotoIDsWithTags(photoIDs);

    // Diagnostic: Check SharedPreferences size
    final storedTagCount = await TagStore.getStoredTagCount();
    developer.log('📊 Total tags in storage: $storedTagCount entries');
    if (storedTagCount > localUrls.length * 1.5) {
      developer.log(
        '⚠️ WARNING: Tag storage has ${storedTagCount - localUrls.length} potential orphaned entries',
      );
      developer.log(
        '   Consider using "Remove all persisted tags" to clean up',
      );
    }

    final missing = localUrls.where((u) {
      final photoID = PhotoId.canonicalId(u);
      return !scannedIDs.contains(photoID);
    }).toList();

    developer.log('🔍 Photos needing scan: ${missing.length}');
    if (missing.isEmpty) {
      developer.log('✅ All photos already scanned!');
      return;
    }

    // Scan all photos that need scanning
    final toScan = missing;
    _scanTotal = toScan.length;
    developer.log('🚀 Starting scan of ${toScan.length} photos...');
    setState(() {
      _scanning = true;
      // Don't reset _scanPaused - let user control pause/resume
      _scanProcessed = 0;
      _scanProgress = 0.0;
    });

    // Update unscanned count asynchronously without blocking
    _updateUnscannedCount();

    await _scanImages(toScan);

    // Update unscanned count after scanning completes
    await _updateUnscannedCount();

    setState(() {
      _scanning = false;
      _scanProgress = 0.0;
      _scanTotal = 0;
    });
  }

  // Manual scan helper restored: scans missing images by default,
  // or force-rescans all device images when `force` is true.
  Future<void> _manualScan({bool force = false}) async {
    if (_scanning) return;

    // Check server connectivity first
    final serverAvailable = await ApiService.pingServer(
      timeout: const Duration(seconds: 3),
      retries: 1,
    );
    if (!serverAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server is offline. Please start the server first.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();
    if (localUrls.isEmpty) return;

    // Use canonical photoID keys to check for scanned images
    final toScan = <String>[];
    if (force) {
      toScan.addAll(localUrls);
    } else {
      for (final u in localUrls) {
        final photoID = PhotoId.canonicalId(u);
        final tags = await TagStore.loadLocalTags(photoID);
        if (tags == null) toScan.add(u);
      }
    }
    if (toScan.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No images to scan')));
      return;
    }

    _scanTotal = toScan.length;
    setState(() {
      _scanning = true;
      // Don't reset _scanPaused - let user control pause/resume
      _scanProcessed = 0;
      _scanProgress = 0.0;
    });

    // Update unscanned count asynchronously without blocking
    _updateUnscannedCount();

    await _scanImages(toScan);

    // Reload all tags from storage to ensure UI reflects persisted data
    developer.log('🔄 Reloading tags from storage after scan completion');
    await _loadTags();

    // Update unscanned count after scanning completes
    await _updateUnscannedCount();

    setState(() {
      _scanning = false;
      _scanProgress = 0.0;
      _scanTotal = 0;
      _scanProcessed = 0;
    });
  }

  /// Validate all previously classified images with CLIP
  Future<void> _validateAllClassifications() async {
    developer.log('🔍 _validateAllClassifications called');

    if (_scanning || _validating) {
      developer.log('⚠️ Already scanning or validating, returning');
      return;
    }

    // Show loading indicator immediately
    setState(() {
      _validating = true;
      _validationTotal = 0;
      _validationProcessed = 0;
    });

    developer.log('📡 Checking server connectivity...');
    // Check server connectivity first
    final serverAvailable = await ApiService.pingServer(
      timeout: const Duration(seconds: 3),
      retries: 1,
    );
    if (!serverAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server is offline. Please start the server first.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();

    developer.log('📸 Found ${localUrls.length} local images');

    if (localUrls.isEmpty) {
      developer.log('⚠️ No local images found');
      return;
    }

    // Collect images that were likely classified by YOLO or are unknown
    final imagesToValidate = <Map<String, dynamic>>[];

    // YOLO can detect: people, animals, food
    // CLIP typically classifies: scenery, document (and fallback for others)
    // Unknown: empty tags
    const yoloCategories = {'people', 'animals', 'food'};

    developer.log(
      '🔍 Checking which images were YOLO-classified or unknown...',
    );

    for (final url in localUrls) {
      final photoID = PhotoId.canonicalId(url);
      final tags = await TagStore.loadLocalTags(photoID);

      if (tags == null) continue;

      // Include ONLY if image has YOLO-detectable categories (people/animals/food)
      // Don't validate unknown images - they already failed, nothing to validate
      // Don't validate scenery/document - those are CLIP-only, not YOLO
      final hasYoloTags = tags.any((tag) => yoloCategories.contains(tag));

      if (hasYoloTags) {
        // Load the file bytes (photo_manager assets need to be read as bytes)
        Uint8List? fileBytes;
        if (url.startsWith('local:')) {
          final id = url.substring('local:'.length);
          final asset = _localAssets[id];
          if (asset != null) {
            // Get bytes directly from asset - more reliable than File
            fileBytes = await asset.originBytes;
          }
        } else if (url.startsWith('file:')) {
          final path = url.substring('file:'.length);
          final file = File(path);
          if (await file.exists()) {
            fileBytes = await file.readAsBytes();
          }
        }

        if (fileBytes != null && fileBytes.isNotEmpty) {
          imagesToValidate.add({
            'file': fileBytes,
            'url': url,
            'tags': tags,
            'photoID': photoID,
          });
        }
      }
    }

    developer.log(
      '✅ Found ${imagesToValidate.length} YOLO-classified images to validate',
    );

    if (imagesToValidate.isEmpty) {
      developer.log('⚠️ No YOLO-classified images found');
      setState(() {
        _validating = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No YOLO-classified images found to validate.\nOnly people/animals/food photos can be validated.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    developer.log('💬 Showing confirmation dialog...');
    // Show confirmation dialog with count
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validate Classifications'),
        content: Text(
          'Re-check ${imagesToValidate.length} YOLO-classified images with CLIP?\n\n'
          'This will verify YOLO detections for people/animals/food and may improve accuracy.\n\n'
          'Only validates photos that YOLO classified. Unknown and CLIP-only photos (scenery/document) will be skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Validate'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      developer.log('❌ User cancelled validation');
      setState(() {
        _validating = false;
      });
      return;
    }

    developer.log(
      '🔍 Starting validation for ${imagesToValidate.length} YOLO-classified images',
    );

    // Run validation
    await _runBackgroundValidation(imagesToValidate);
  }

  Future<void> _scanImages(List<String> urls) async {
    developer.log('📸 _scanImages called with ${urls.length} photos');

    // Adaptive batch sizing based on device capabilities
    int batchSize = await _determineOptimalBatchSize();
    int totalProcessed = 0;

    // Performance monitoring for dynamic adjustment
    final batchTimings = <int>[];
    int consecutiveSlowBatches = 0;
    int consecutiveFastBatches = 0;
    final scanStartTime = DateTime.now();

    // Track YOLO-classified images for background validation
    final yoloClassifiedImages = <Map<String, dynamic>>[]; // {file, url, tags}

    for (
      var batchStart = 0;
      batchStart < urls.length;
      batchStart += batchSize
    ) {
      final batchEnd = (batchStart + batchSize).clamp(0, urls.length);
      final batch = urls.sublist(batchStart, batchEnd);

      // Check for pause BEFORE any processing or logging
      while (_scanPaused) {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      developer.log(
        '\n════════════════════════════════════════════════════════',
      );
      developer.log(
        '⏳ BATCH ${(batchStart ~/ batchSize) + 1}/${(urls.length / batchSize).ceil()} - Processing photos ${batchStart + 1}-$batchEnd',
      );
      developer.log('════════════════════════════════════════════════════════');

      final batchStartTime = DateTime.now();

      // Update batch size and periodically check RAM/CPU (every 5 batches)
      if (mounted) {
        _currentBatchSize = batchSize;
        if ((batchStart ~/ batchSize) % 5 == 0) {
          _currentRamUsageMB = await _getCurrentRamUsage();
          _peakRamUsageMB = _currentRamUsageMB > _peakRamUsageMB
              ? _currentRamUsageMB
              : _peakRamUsageMB;
        }
      }

      // Prepare batch of files (declare outside try block for catch access)
      final batchItems = <Map<String, dynamic>>[];
      final batchUrls = <String>[];

      try {
        final assetLoadStartTime = DateTime.now();
        // Load files in parallel for maximum speed
        final fileLoadFutures = batch.map((u) async {
          File? file;
          if (u.startsWith('local:')) {
            final id = u.substring('local:'.length);
            final asset = _localAssets[id];
            if (asset != null) {
              file = await asset.file;
            }
          } else if (u.startsWith('file:')) {
            final path = u.substring('file:'.length);
            file = File(path);
          }

          if (file != null) {
            final photoID = PhotoId.canonicalId(u);
            return {'file': file, 'photoID': photoID, 'url': u};
          }
          return null;
        }).toList();

        // Wait for all files to load concurrently
        final loadedFiles = await Future.wait(fileLoadFutures);
        final assetLoadEndTime = DateTime.now();
        final assetLoadDuration = assetLoadEndTime
            .difference(assetLoadStartTime)
            .inMilliseconds;
        developer.log('⏱️  Step 1: Asset loading took ${assetLoadDuration}ms');

        // Filter out nulls and build batch items
        final filterStartTime = DateTime.now();
        for (final item in loadedFiles) {
          if (item != null) {
            batchItems.add({'file': item['file'], 'photoID': item['photoID']});
            batchUrls.add(item['url'] as String);
          }
        }
        final filterEndTime = DateTime.now();
        developer.log(
          '⏱️  Step 2: Filtering/building items took ${filterEndTime.difference(filterStartTime).inMilliseconds}ms',
        );

        if (batchItems.isEmpty) {
          totalProcessed += batch.length;
          continue;
        }

        final prepEndTime = DateTime.now();
        final prepDuration = prepEndTime
            .difference(batchStartTime)
            .inMilliseconds;
        developer.log(
          '📦 TOTAL file prep: ${prepDuration}ms for ${batchItems.length} files',
        );

        // Upload batch
        final uploadStartTime = DateTime.now();
        final res = await ApiService.uploadImagesBatch(batchItems);
        final uploadEndTime = DateTime.now();
        final uploadDuration = uploadEndTime
            .difference(uploadStartTime)
            .inMilliseconds;
        developer.log('📤 Upload + server processing took ${uploadDuration}ms');

        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            final parseStartTime = DateTime.now();
            final body = json.decode(res.body);
            final parseEndTime = DateTime.now();
            developer.log(
              '🔍 JSON parse took ${parseEndTime.difference(parseStartTime).inMilliseconds}ms',
            );

            // Response format: {"results": [{"photoID": "...", "tags": [...]}, ...]}
            if (body is Map && body['results'] is List) {
              final results = body['results'] as List;
              final batchTagsToSave = <String, List<String>>{};

              final processingStartTime = DateTime.now();
              for (var i = 0; i < results.length && i < batchUrls.length; i++) {
                final result = results[i];
                final url = batchUrls[i];
                final basename = p.basename(url);
                final photoID = PhotoId.canonicalId(url);

                List<String> tags = [];
                if (result is Map && result['tags'] is List) {
                  tags = (result['tags'] as List).cast<String>();
                }

                // Update in-memory tags
                photoTags[basename] = tags;
                batchTagsToSave[photoID] = tags;

                if (tags.isNotEmpty) {
                  developer.log('✅ Tagged $basename with: ${tags.join(", ")}');

                  // Track for background validation (only non-empty tags)
                  if (i < batchItems.length) {
                    yoloClassifiedImages.add({
                      'file': batchItems[i]['file'],
                      'url': url,
                      'tags': tags,
                      'photoID': photoID,
                    });
                  }
                }
              }
              final processingEndTime = DateTime.now();
              developer.log(
                '🔄 Tag processing took ${processingEndTime.difference(processingStartTime).inMilliseconds}ms',
              );

              // Save all tags in one batch operation (much faster)
              final saveStartTime = DateTime.now();
              await TagStore.saveLocalTagsBatch(batchTagsToSave);
              final saveEndTime = DateTime.now();
              developer.log(
                '💾 Tag save took ${saveEndTime.difference(saveStartTime).inMilliseconds}ms for ${batchTagsToSave.length} photos',
              );
            }

            // Decrement unscanned count by the number of successfully processed photos
            if (mounted && _currentUnscannedCount > 0) {
              final oldCount = _currentUnscannedCount;
              final newCount = (_currentUnscannedCount - batchUrls.length)
                  .clamp(0, _currentUnscannedCount)
                  .toInt();
              developer.log(
                '🔄 Updating unscanned count: $oldCount -> $newCount (processed ${batchUrls.length} photos)',
              );
              setState(() {
                _currentUnscannedCount = newCount;
              });
            }
          } catch (e) {
            developer.log('Failed parsing batch response: $e');
            // Mark all as scanned with empty tags
            final batchTagsToSave = <String, List<String>>{};
            for (final url in batchUrls) {
              final photoID = PhotoId.canonicalId(url);
              photoTags[p.basename(url)] = [];
              batchTagsToSave[photoID] = [];
            }
            await TagStore.saveLocalTagsBatch(batchTagsToSave);

            // Decrement unscanned count for this batch
            if (mounted && _currentUnscannedCount > 0) {
              final oldCount = _currentUnscannedCount;
              final newCount = (_currentUnscannedCount - batchUrls.length)
                  .clamp(0, _currentUnscannedCount)
                  .toInt();
              developer.log(
                '🔄 Updating unscanned count (error path): $oldCount -> $newCount',
              );
              setState(() {
                _currentUnscannedCount = newCount;
              });
            }
          }
        } else {
          developer.log('Batch scan failed: status=${res.statusCode}');
          // Mark all as scanned with empty tags on failure
          final batchTagsToSave = <String, List<String>>{};
          for (final url in batchUrls) {
            final photoID = PhotoId.canonicalId(url);
            photoTags[p.basename(url)] = [];
            batchTagsToSave[photoID] = [];
          }
          await TagStore.saveLocalTagsBatch(batchTagsToSave);

          // Update unscanned count for failed batch
          if (mounted && _currentUnscannedCount > 0) {
            final oldCount = _currentUnscannedCount;
            final newCount = (_currentUnscannedCount - batchUrls.length)
                .clamp(0, _currentUnscannedCount)
                .toInt();
            developer.log(
              '🔄 Updating unscanned count (failure): $oldCount -> $newCount',
            );
            setState(() {
              _currentUnscannedCount = newCount;
            });
          }
        }
      } catch (e) {
        developer.log('Batch scan error: $e');
        // Mark all as scanned with empty tags on exception
        final batchTagsToSave = <String, List<String>>{};
        for (final url in batchUrls) {
          final photoID = PhotoId.canonicalId(url);
          photoTags[p.basename(url)] = [];
          batchTagsToSave[photoID] = [];
        }
        await TagStore.saveLocalTagsBatch(batchTagsToSave);

        // Update unscanned count for exception case
        if (mounted && _currentUnscannedCount > 0) {
          final oldCount = _currentUnscannedCount;
          final newCount = (_currentUnscannedCount - batchUrls.length)
              .clamp(0, _currentUnscannedCount)
              .toInt();
          developer.log(
            '🔄 Updating unscanned count (exception): $oldCount -> $newCount',
          );
          setState(() {
            _currentUnscannedCount = newCount;
          });
        }
      }

      // Only count files that were actually processed
      totalProcessed += batchUrls.length;

      // Calculate batch timing
      final batchEndTime = DateTime.now();
      final batchDuration = batchEndTime
          .difference(batchStartTime)
          .inMilliseconds;

      developer.log('════════════════════════════════════════════════════════');
      developer.log(
        '✅ BATCH COMPLETE: ${batchDuration}ms total (${(batchDuration / batchUrls.length).toStringAsFixed(1)}ms per photo)',
      );
      developer.log(
        '════════════════════════════════════════════════════════\n',
      );

      // Update progress and performance stats
      // Always update UI for smooth progress feedback
      if (mounted) {
        final elapsedSeconds = DateTime.now()
            .difference(scanStartTime)
            .inSeconds;
        setState(() {
          _scanProcessed = totalProcessed;
          _scanProgress = totalProcessed / (_scanTotal == 0 ? 1 : _scanTotal);
          _avgBatchTimeMs = batchDuration;
          _imagesPerSecond = elapsedSeconds > 0
              ? totalProcessed / elapsedSeconds.toDouble()
              : 0;
        });
      }

      // Performance-based batch size adjustment
      final batchEndTimeMs = batchEndTime.millisecondsSinceEpoch;
      batchTimings.add(batchEndTimeMs);

      // Keep only last 5 timings for rolling average
      if (batchTimings.length > 5) batchTimings.removeAt(0);

      // Adaptive tuning: adjust batch size based on performance
      // Target: 2-5 seconds per batch (optimized for CPU-based CLIP at 170ms/image)
      // Start small (10-15 images) and dynamically adjust based on actual performance
      if (batchTimings.length >= 3) {
        final avgTime = batchDuration; // Use current batch time

        if (avgTime > 6000 && batchSize > 2) {
          // Too slow (>6s) - reduce batch size
          consecutiveSlowBatches++;
          consecutiveFastBatches = 0;

          if (consecutiveSlowBatches >= 2) {
            batchSize = (batchSize * 0.7).ceil().clamp(2, 30);
            developer.log(
              '⚡ Reducing batch size to $batchSize (performance optimization)',
            );
            consecutiveSlowBatches = 0;
          }
        } else if (avgTime < 3000 && batchSize < 30) {
          // Fast enough (<3s) - can increase batch size
          consecutiveFastBatches++;
          consecutiveSlowBatches = 0;

          if (consecutiveFastBatches >= 2) {
            batchSize = (batchSize * 1.4).ceil().clamp(2, 30);
            developer.log(
              '⚡ Increasing batch size to $batchSize (device can handle more)',
            );
            consecutiveFastBatches = 0;
          }
        } else {
          // Sweet spot (3-6s per batch) - reset counters
          consecutiveSlowBatches = 0;
          consecutiveFastBatches = 0;
        }
      }

      // No delay between batches for maximum speed
      // Device can handle it with adaptive batch sizing
    }

    // After all batches complete, run background validation if we have YOLO-classified images
    if (yoloClassifiedImages.isNotEmpty && mounted) {
      _runBackgroundValidation(yoloClassifiedImages);
    }
  }

  /// Run CLIP validation in background for YOLO-classified images
  Future<void> _runBackgroundValidation(
    List<Map<String, dynamic>> imagesToValidate,
  ) async {
    if (!mounted) return;

    developer.log(
      '🔍 Starting background CLIP validation for ${imagesToValidate.length} images',
    );

    setState(() {
      _validating = true;
      _validationCancelled = false;
      _validationPaused = false;
      _validationTotal = imagesToValidate.length;
      _validationProcessed = 0;
      _validationAgreements = 0;
      _validationDisagreements = 0;
      _validationOverrides = 0;
      _validationChanges.clear(); // Clear previous changes
      _validationSuggestions.clear(); // Clear previous suggestions
    });

    try {
      // Process in smaller batches to avoid overwhelming the server
      const validationBatchSize = 10;

      for (
        var batchStart = 0;
        batchStart < imagesToValidate.length;
        batchStart += validationBatchSize
      ) {
        if (!mounted || _validationCancelled) {
          developer.log('🛑 Validation cancelled by user');
          return;
        }

        // Wait if paused
        while (_validationPaused && !_validationCancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }

        final batchEnd = (batchStart + validationBatchSize).clamp(
          0,
          imagesToValidate.length,
        );
        final batch = imagesToValidate.sublist(batchStart, batchEnd);

        developer.log(
          '🔍 Validating batch ${(batchStart ~/ validationBatchSize) + 1}/${(imagesToValidate.length / validationBatchSize).ceil()} (${batch.length} images)',
        );

        // Call validation endpoint
        try {
          final validationData = <Map<String, dynamic>>[];
          final yoloTagsList = <List<String>>[];

          for (final item in batch) {
            final url = item['url'] as String;
            final filename = url.startsWith('local:')
                ? 'photo_${item['photoID']}.jpg'
                : p.basename(url);

            validationData.add({
              'file': item['file'], // Uint8List from asset.originBytes
              'filename': filename,
            });
            yoloTagsList.add(item['tags'] as List<String>);
          }

          developer.log(
            '📤 Sending validation request for batch of ${batch.length} images...',
          );

          final res = await ApiService.validateYoloClassifications(
            validationData,
            yoloTagsList,
          );

          developer.log(
            '📥 Received validation response: status=${res.statusCode}',
          );

          if (res.statusCode >= 200 && res.statusCode < 300) {
            final body = json.decode(res.body);

            if (body is Map && body['validations'] is List) {
              final validations = body['validations'] as List;
              final summary = body['summary'] as Map?;

              // Process validation results
              for (var i = 0; i < validations.length && i < batch.length; i++) {
                final validation = validations[i];
                final item = batch[i];
                final url = item['url'] as String;
                final photoID = item['photoID'] as String;
                final yoloTags = item['tags'] as List<String>;

                final agreement = validation['agreement'] == true;
                final shouldOverride = validation['should_override'] == true;
                final clipTags =
                    (validation['clip_tags'] as List?)?.cast<String>() ?? [];
                final overrideTags =
                    (validation['override_tags'] as List?)?.cast<String>() ??
                    [];
                final reason = validation['reason'] as String? ?? '';

                // Update stats
                if (mounted) {
                  setState(() {
                    _validationProcessed++;
                    if (agreement) {
                      _validationAgreements++;
                    } else {
                      _validationDisagreements++;
                    }
                    if (shouldOverride) {
                      _validationOverrides++;
                    }
                  });
                }

                // Log validation results
                if (agreement) {
                  developer.log(
                    '✅ Validation: ${p.basename(url)} - Agreement: ${yoloTags.join(", ")}',
                  );
                } else {
                  developer.log(
                    '⚠️ Validation: ${p.basename(url)} - Disagreement',
                  );
                  developer.log('   YOLO: ${yoloTags.join(", ")}');
                  developer.log('   CLIP: ${clipTags.join(", ")}');
                  developer.log('   Reason: $reason');

                  if (shouldOverride && overrideTags.isNotEmpty) {
                    developer.log(
                      '   🔄 Override recommended: ${overrideTags.join(", ")}',
                    );

                    // Track this suggestion for user review (NOT auto-applied)
                    // SAFETY: Never suggest empty tags
                    _validationSuggestions.add({
                      'url': url,
                      'photoID': photoID,
                      'oldTags': List<String>.from(yoloTags),
                      'newTags': List<String>.from(overrideTags),
                      'reason': reason,
                      'clipTags': List<String>.from(clipTags),
                      'basename': p.basename(url),
                    });

                    developer.log('   📋 Suggestion recorded for user review');
                  } else if (shouldOverride && overrideTags.isEmpty) {
                    developer.log(
                      '   ⚠️ WARNING: Override suggested with EMPTY tags! Ignoring to prevent data loss.',
                    );
                  }
                }
              }

              // Log batch summary
              if (summary != null) {
                developer.log(
                  '📊 Validation batch summary: ${summary['agreements']} agreements, ${summary['disagreements']} disagreements, ${summary['overrides']} overrides',
                );
              }
            }
          } else {
            developer.log(
              '⚠️ Validation batch failed: status=${res.statusCode}, body=${res.body}',
            );
          }
        } catch (e, stackTrace) {
          developer.log('⚠️ Validation batch error: $e');
          developer.log('Stack trace: $stackTrace');
        }

        // Small delay between validation batches
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Validation complete
      developer.log(
        '✅ Background validation complete: $_validationAgreements agreements, $_validationDisagreements disagreements, $_validationOverrides overrides',
      );

      // Show summary if significant improvements were made
      if (mounted && _validationOverrides > 0) {
        final improvementPercent =
            (_validationOverrides / _validationTotal * 100).toStringAsFixed(1);
        // ignore: use_build_context_synchronously

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Validation complete: $_validationOverrides images reclassified ($improvementPercent% improved)',
            ),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () {
                setState(() {}); // Refresh UI to show updated tags
              },
            ),
          ),
        );
      }
    } catch (e) {
      developer.log('⚠️ Background validation error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _validating = false;
        });
      }
    }
  }

  /// Build image widget for any URL type
  Widget _buildImageWidget(String url, BoxFit fit) {
    if (url.startsWith('local:')) {
      final assetId = url.substring('local:'.length);
      // Use thumbnail for better performance
      return FutureBuilder<Uint8List?>(
        future: _getThumbForAsset(assetId),
        builder: (ctx, snap) {
          if (snap.hasData && snap.data != null) {
            return Image.memory(snap.data!, fit: fit);
          }
          return Container(
            color: Colors.grey.shade300,
            child: const Center(child: CircularProgressIndicator()),
          );
        },
      );
    } else if (url.startsWith('file:')) {
      return Image.file(File(url.substring('file:'.length)), fit: fit);
    } else {
      return Image.network(ApiService.resolveImageUrl(url), fit: fit);
    }
  }

  /// Show validation progress and changes dialog
  void _showValidationProgressDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade700,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Validation Progress',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _validating
                                ? _validationPaused
                                      ? 'Paused... $_validationProcessed/$_validationTotal'
                                      : 'Processing... $_validationProcessed/$_validationTotal'
                                : 'Completed',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_validating) ...[
                      TextButton.icon(
                        icon: Icon(
                          _validationPaused ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                        ),
                        label: Text(
                          _validationPaused ? 'Resume' : 'Pause',
                          style: const TextStyle(color: Colors.white),
                        ),
                        onPressed: () {
                          setState(() {
                            _validationPaused = !_validationPaused;
                          });
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.stop, color: Colors.white),
                        label: const Text(
                          'Stop',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: () {
                          setState(() {
                            _validationCancelled = true;
                          });
                          Navigator.pop(context);
                        },
                      ),
                    ] else
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                  ],
                ),
              ),

              // Progress stats
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Progress bar
                    LinearProgressIndicator(
                      value: _validationTotal > 0
                          ? _validationProcessed / _validationTotal
                          : 0,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.deepPurple.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Agreements',
                            _validationAgreements.toString(),
                            Icons.check_circle,
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatCard(
                            'Disagreements',
                            _validationDisagreements.toString(),
                            Icons.warning,
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatCard(
                            'Overrides',
                            _validationOverrides.toString(),
                            Icons.auto_fix_high,
                            Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Suggested changes list (during validation)
              if (_validationSuggestions.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Suggested Changes (${_validationSuggestions.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _validationSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _validationSuggestions[index];
                      return _buildChangeItem(suggestion);
                    },
                  ),
                ),
              ] else if (!_validating) ...[
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No changes suggested',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChangeItem(Map<String, dynamic> change) {
    final url = change['url'] as String;
    final oldTags = change['oldTags'] as List<String>;
    final newTags = change['newTags'] as List<String>;
    final reason = change['reason'] as String;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showChangeDetails(change),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: _buildImageWidget(url, BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),

              // Tags comparison
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Old tags
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'WAS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            oldTags.isEmpty ? 'unknown' : oldTags.join(', '),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              decoration: TextDecoration.lineThrough,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // New tags
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NOW',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            newTags.join(', '),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        reason,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangeDetails(Map<String, dynamic> change) {
    final url = change['url'] as String;
    final oldTags = change['oldTags'] as List<String>;
    final newTags = change['newTags'] as List<String>;
    final reason = change['reason'] as String;
    final clipTags = change['clipTags'] as List<String>;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.95,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.compare_arrows, color: Colors.white),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Classification Change',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Image
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Full image
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildImageWidget(url, BoxFit.contain),
                        ),
                      ),

                      // Tags comparison
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // YOLO (old) tags
                            _buildTagSection(
                              'YOLO Classification',
                              oldTags.isEmpty ? ['unknown'] : oldTags,
                              Colors.red,
                              Icons.cancel,
                            ),

                            const SizedBox(height: 16),

                            // CLIP (new) tags
                            _buildTagSection(
                              'CLIP Classification',
                              clipTags,
                              Colors.blue,
                              Icons.lightbulb,
                            ),

                            const SizedBox(height: 16),

                            // Final (override) tags
                            _buildTagSection(
                              'Final Tags',
                              newTags,
                              Colors.green,
                              Icons.check_circle,
                            ),

                            if (reason.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        reason,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagSection(
    String title,
    List<String> tags,
    Color color,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: tags
              .map(
                (tag) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  /// Get current RAM usage in MB
  Future<double> _getCurrentRamUsage() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isLinux)) {
        // Read current process memory from /proc/self/status
        final statusFile = File('/proc/self/status');
        if (await statusFile.exists()) {
          final content = await statusFile.readAsString();
          final vmRssLine = content
              .split('\n')
              .firstWhere(
                (line) => line.startsWith('VmRSS:'),
                orElse: () => '',
              );
          if (vmRssLine.isNotEmpty) {
            final memKB = int.tryParse(
              vmRssLine.replaceAll(RegExp(r'[^0-9]'), ''),
            );
            if (memKB != null) {
              return memKB / 1024.0; // Convert to MB
            }
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Determine optimal initial batch size based on device capabilities
  Future<int> _determineOptimalBatchSize() async {
    try {
      // Try to get device info
      int cpuCores = 4; // Default assumption
      int ramGB = 4; // Default assumption

      // Attempt to read /proc/cpuinfo for CPU cores (Android/Linux)
      try {
        if (!kIsWeb && Platform.isAndroid || Platform.isLinux) {
          final cpuInfo = await File('/proc/cpuinfo').readAsString();
          final processors = cpuInfo
              .split('\n')
              .where((line) => line.startsWith('processor'))
              .length;
          if (processors > 0) cpuCores = processors;
        }
      } catch (_) {
        // Fallback to default
      }

      // Attempt to read /proc/meminfo for RAM (Android/Linux)
      try {
        if (!kIsWeb && Platform.isAndroid || Platform.isLinux) {
          final memInfo = await File('/proc/meminfo').readAsString();
          final memTotalLine = memInfo
              .split('\n')
              .firstWhere(
                (line) => line.startsWith('MemTotal:'),
                orElse: () => '',
              );
          if (memTotalLine.isNotEmpty) {
            final memKB = int.tryParse(
              memTotalLine.replaceAll(RegExp(r'[^0-9]'), ''),
            );
            if (memKB != null) {
              ramGB = (memKB / 1024 / 1024).ceil();
            }
          }
        }
      } catch (_) {
        // Fallback to default
      }

      developer.log('📱 Device: $cpuCores CPU cores, ~${ramGB}GB RAM');

      // Calculate batch size based on device capabilities
      // Formula: Start small and let adaptive tuning increase it
      // Small batches = faster feedback, less network overhead, better responsiveness
      int batchSize;

      if (ramGB <= 3 || cpuCores <= 4) {
        // Low-end device: 3 images per batch
        batchSize = 3;
      } else if (ramGB <= 6 || cpuCores <= 6) {
        // Mid-range device: 6 images per batch
        batchSize = 6;
      } else if (ramGB <= 8 || cpuCores <= 8) {
        // Mid-high device: 10 images per batch
        batchSize = 10;
      } else {
        // High-end device: 15 images per batch (8+ cores or 8+ GB RAM)
        batchSize = 15;
      }

      developer.log('⚙️ Initial batch size: $batchSize (adaptive)');
      return batchSize;
    } catch (e) {
      developer.log('Failed to detect device specs: $e');
      // Conservative fallback for unknown devices
      return 5;
    }
  }

  /// Show dialog to review and approve/reject validation suggestions
  void _showReviewChangesDialog() {
    if (_validationSuggestions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No changes to review')));
      return;
    }

    // Track which suggestions are selected (all selected by default)
    final selectedIndices = List<int>.generate(
      _validationSuggestions.length,
      (index) => index,
    ).toSet();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.rate_review, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Review Suggested Changes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_validationSuggestions.length} changes suggested • ${selectedIndices.length} selected',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Quick actions
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.select_all, size: 16),
                        label: const Text('Select All'),
                        onPressed: () {
                          setDialogState(() {
                            selectedIndices.addAll(
                              List<int>.generate(
                                _validationSuggestions.length,
                                (index) => index,
                              ),
                            );
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.deselect, size: 16),
                        label: const Text('Deselect All'),
                        onPressed: () {
                          setDialogState(() {
                            selectedIndices.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Suggestions list
                Expanded(
                  child: ListView.builder(
                    itemCount: _validationSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _validationSuggestions[index];
                      final isSelected = selectedIndices.contains(index);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (selected) {
                          setDialogState(() {
                            if (selected == true) {
                              selectedIndices.add(index);
                            } else {
                              selectedIndices.remove(index);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            // Thumbnail (tappable to show details)
                            GestureDetector(
                              onTap: () => _showChangeDetails(suggestion),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: _buildImageWidget(
                                    suggestion['url'] as String,
                                    BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Change info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Old tags
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.label_off,
                                        size: 14,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          (suggestion['oldTags']
                                                  as List<String>)
                                              .join(', '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red.shade700,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // New tags
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.label,
                                        size: 14,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          (suggestion['newTags']
                                                  as List<String>)
                                              .join(', '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Reason
                                  Text(
                                    suggestion['reason'] as String,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Action buttons
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.check_circle,
                                    color: Colors.green.shade600,
                                    size: 28,
                                  ),
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await _applySelectedChanges([index]);
                                  },
                                  tooltip: 'Approve',
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.cancel,
                                    color: Colors.red.shade600,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      _validationSuggestions.removeAt(index);
                                      selectedIndices.remove(index);
                                      // Adjust indices after removal
                                      final adjustedIndices = <int>{};
                                      for (var i in selectedIndices) {
                                        if (i > index) {
                                          adjustedIndices.add(i - 1);
                                        } else if (i < index) {
                                          adjustedIndices.add(i);
                                        }
                                      }
                                      selectedIndices
                                        ..clear()
                                        ..addAll(adjustedIndices);
                                    });
                                    if (_validationSuggestions.isEmpty) {
                                      Navigator.pop(context);
                                    }
                                  },
                                  tooltip: 'Decline',
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Action buttons
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('Reject All'),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _validationSuggestions.clear();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All changes rejected'),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: Text(
                            'Apply ${selectedIndices.length} Changes',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: selectedIndices.isEmpty
                              ? null
                              : () async {
                                  Navigator.pop(context);
                                  await _applySelectedChanges(
                                    selectedIndices.toList(),
                                  );
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Apply selected validation changes
  Future<void> _applySelectedChanges(List<int> indices) async {
    try {
      int appliedCount = 0;

      for (final index in indices) {
        if (index >= _validationSuggestions.length) continue;

        final suggestion = _validationSuggestions[index];
        final basename = suggestion['basename'] as String;
        final photoID = suggestion['photoID'] as String;
        final newTags = suggestion['newTags'] as List<String>;

        // Apply the change
        photoTags[basename] = newTags;
        await TagStore.saveLocalTags(photoID, newTags);

        // Track as applied change
        _validationChanges.add(suggestion);
        appliedCount++;

        developer.log('✅ Applied change: $basename -> ${newTags.join(", ")}');
      }

      setState(() {
        // Remove applied suggestions (iterate backwards to avoid index issues)
        final sortedIndices = indices.toList()..sort((a, b) => b.compareTo(a));
        for (final index in sortedIndices) {
          if (index < _validationSuggestions.length) {
            _validationSuggestions.removeAt(index);
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Applied $appliedCount changes'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      developer.log('Error applying changes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error applying changes: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _loadOrganizedImages() async {
    // Skip server for now - load directly from device
    developer.log('🔄 Loading photos directly from device...');
    await _loadDevicePhotos();
  }

  Future<void> _loadDevicePhotos() async {
    try {
      developer.log('⏳ Checking photo permission...');
      // Request permission (will return immediately if already granted)
      var perm = await PhotoManager.requestPermissionExtend();
      developer.log(
        '📷 Permission status: ${perm.name} (isAuth: ${perm.isAuth})',
      );

      // Accept limited permission (Android 14+) - don't show dialog every time
      if (!perm.isAuth && perm != PermissionState.limited) {
        developer.log('❌ Permission denied: ${perm.name}');
        setState(() => imageUrls = []);
        return;
      }

      if (perm == PermissionState.limited) {
        developer.log(
          '⚠️ Limited access granted - loading selected photos only',
        );
      } else {
        developer.log('✅ Full photo access granted');
      }

      // Proceed with loading if we have any level of access (even limited)
      if (perm == PermissionState.authorized ||
          perm == PermissionState.limited) {
        if (perm == PermissionState.limited) {
          developer.log('⚠️ Limited access - loading selected photos only');
        } else {
          developer.log('✅ Full photo access granted');
        }
      } else {
        developer.log('❌ Permission denied: ${perm.name}');
        // Try filesystem fallback
        try {
          final pics = await _discoverPicturesFromFs();
          if (pics.isNotEmpty) {
            setState(() => imageUrls = pics);
            return;
          }
        } catch (_) {}
        setState(() => imageUrls = []);
        return;
      }

      // Get ALL albums (Camera, Screenshots, Downloads, DCIM, etc.)
      developer.log('🔍 Getting asset path list...');
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        onlyAll: false, // Get all individual albums, not just "Recent"
      );
      developer.log(
        '📁 Found ${albums.length} albums: ${albums.map((a) => a.name).join(", ")}',
      );

      if (albums.isEmpty) {
        developer.log('⚠️ No albums found, trying filesystem fallback');
        // Try filesystem fallback
        try {
          final pics = await _discoverPicturesFromFs();
          developer.log('📂 Filesystem found ${pics.length} photos');
          if (pics.isNotEmpty) {
            setState(() => imageUrls = pics);
            return;
          }
        } catch (_) {}
        setState(() => imageUrls = []);
        return;
      }

      // Combine photos from ALL albums
      developer.log('🔄 Processing albums...');
      final allAssets = <AssetEntity>[];
      for (final album in albums) {
        final count = await album.assetCountAsync;
        developer.log('📸 Album "${album.name}": $count photos');
        if (count > 0) {
          final assets = await album.getAssetListRange(start: 0, end: count);
          allAssets.addAll(assets);
        }
      }

      // Remove duplicates (same photo might be in multiple albums)
      final seenIds = <String>{};
      final uniqueAssets = <AssetEntity>[];
      for (final asset in allAssets) {
        if (seenIds.add(asset.id)) {
          uniqueAssets.add(asset);
        }
      }

      developer.log('🎯 Total unique photos: ${uniqueAssets.length}');

      final urls = <String>[];
      _localAssets.clear();
      _thumbCache.clear();
      for (final a in uniqueAssets) {
        final id = a.id;
        _localAssets[id] = a;
        urls.add('local:$id');
      }
      developer.log('✅ Loaded ${urls.length} photo URLs');
      setState(() => imageUrls = urls);

      if (urls.isEmpty) {
        // fallback to filesystem scan if MediaStore returned no assets
        try {
          final pics = await _discoverPicturesFromFs();
          if (pics.isNotEmpty) {
            setState(() => imageUrls = pics);
            return;
          }
        } catch (_) {}
      }
    } catch (e, stack) {
      developer.log('❌ Error loading device photos: $e');
      developer.log('Stack trace: $stack');
      setState(() => imageUrls = []);
    }
  }

  Future<List<String>> _discoverPicturesFromFs() async {
    try {
      final dir = Directory('/sdcard/Pictures');
      if (!await dir.exists()) {
        return [];
      }
      final files = await dir.list().toList();
      final images = files
          .whereType<File>()
          .where((f) {
            final ext = f.path.toLowerCase();
            return ext.endsWith('.png') ||
                ext.endsWith('.jpg') ||
                ext.endsWith('.jpeg') ||
                ext.endsWith('.webp');
          })
          .map((f) => 'file:${f.path}')
          .toList();
      return images;
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> _getThumbForAsset(String id) async {
    if (_thumbCache.containsKey(id)) return _thumbCache[id];
    final asset = _localAssets[id];
    if (asset == null) return null;
    try {
      final bytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize(768, 768),
        quality: 80,
      );
      if (bytes != null) _thumbCache[id] = bytes;
      return bytes;
    } catch (e) {
      developer.log('Failed to get thumbnail for $id: $e');
      return null;
    }
  }

  Future<void> _loadTags() async {
    for (final url in imageUrls) {
      final key = p.basename(url);
      if (photoTags.containsKey(key) && (photoTags[key]?.isNotEmpty ?? false)) {
        continue; // prefer server
      }
      // Load from canonical photoID key
      final photoID = PhotoId.canonicalId(url);
      final tags = await TagStore.loadLocalTags(photoID);
      if (tags != null) {
        photoTags[key] = tags;
      }
    }
  }

  Color _colorForTag(String tag) {
    final t = tag.toLowerCase();
    if (t == 'person') return Colors.blueAccent;
    if (t == 'cat' || t == 'dog') return Colors.greenAccent;
    if (t == 'car') return Colors.redAccent;
    return Colors.pinkAccent;
  }

  Future<void> _createAlbumFromSelection() async {
    if (_selectedKeys.isEmpty) return;
    final selectedUrls = imageUrls
        .where((u) => _selectedKeys.contains(p.basename(u)))
        .toList();
    if (selectedUrls.isEmpty) return;
    final controller = TextEditingController(text: 'Album');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Album from selection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Album Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (name != null && name.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('album_$name', json.encode(selectedUrls));
      final albumsJson = prefs.getString('albums');
      Map<String, dynamic> albumsMap = {};
      if (albumsJson != null) {
        try {
          albumsMap = json.decode(albumsJson) as Map<String, dynamic>;
        } catch (_) {
          albumsMap = {};
        }
      }
      albumsMap[name] = selectedUrls;
      await prefs.setString('albums', json.encode(albumsMap));
      developer.log(
        '📁 Album created from selection: $name (${selectedUrls.length} images)',
      );
      if (!mounted) return;
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Album "$name" created with ${selectedUrls.length} images',
          ),
        ),
      );
      setState(() {
        _isSelectMode = false;
        _selectedKeys.clear();
      });
      widget.onAlbumCreated?.call();
    }
  }

  void _updateSystemUI() {
    // Update system UI colors to match theme
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: isDark
              ? const Color(0xFF121212)
              : const Color(0xFFF2F0EF),
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
      );
    });
  }

  void _showTagMenu(String tag) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tag: $tag',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.search),
                  title: Text('Search for "\$tag"'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      searchQuery = tag;
                      _searchController.text = tag;
                    });
                    widget.onSearchChanged?.call();
                    FocusScope.of(context).requestFocus(_searchFocusNode);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder),
                  title: Text('Create album with "$tag"'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _createAlbumWithTag(tag);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHiddenTagsMenu(List<String> allTags, List<String> visibleTags) {
    final hidden = allTags.where((t) => !visibleTags.contains(t)).toList();
    if (hidden.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: hidden
                  .map(
                    (t) => ListTile(
                      leading: const Icon(Icons.label),
                      title: Text(t),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showTagMenu(t);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUnscannedModal() async {
    final prefs = await SharedPreferences.getInstance();
    final unscanned = imageUrls
        .where(
          (u) =>
              (u.startsWith('local:') || u.startsWith('file:')) &&
              !prefs.containsKey(p.basename(u)),
        )
        .toList();
    if (unscanned.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No unscanned images')));
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: unscanned.length,
              itemBuilder: (c, idx) {
                final url = unscanned[idx];
                final key = p.basename(url);
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(c);
                    if (url.startsWith('local:')) {
                      final id = url.substring('local:'.length);
                      final asset = _localAssets[id];
                      if (asset != null) {
                        final file = await asset.file;
                        if (file != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PhotoViewer(
                                filePath: file.path,
                                heroTag: key,
                              ),
                            ),
                          );
                        }
                      }
                    } else if (url.startsWith('file:')) {
                      final path = url.substring('file:'.length);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PhotoViewer(filePath: path, heroTag: key),
                        ),
                      );
                    } else {
                      final resolved = ApiService.resolveImageUrl(url);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PhotoViewer(networkUrl: resolved, heroTag: key),
                        ),
                      );
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: url.startsWith('local:')
                        ? FutureBuilder<Uint8List?>(
                            future: _getThumbForAsset(url.substring(6)),
                            builder: (ctx, snap) {
                              if (snap.hasData && snap.data != null) {
                                return Image.memory(
                                  snap.data!,
                                  fit: BoxFit.cover,
                                );
                              }
                              return Container(color: Colors.black26);
                            },
                          )
                        : (url.startsWith('file:')
                              ? Image.file(
                                  File(url.substring('file:'.length)),
                                  fit: BoxFit.cover,
                                )
                              : Image.network(
                                  ApiService.resolveImageUrl(url),
                                  fit: BoxFit.cover,
                                )),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _createAlbumWithTag(String tag) async {
    final tagged = imageUrls
        .where((u) => (photoTags[p.basename(u)] ?? []).contains(tag))
        .toList();
    if (tagged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No images found with tag "$tag"')),
      );
      return;
    }
    final controller = TextEditingController(text: '$tag Album');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create Album with "$tag"'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Album Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (name != null && name.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      // Persist the album as a distinct key and also update the central albums map
      await prefs.setString('album_$name', json.encode(tagged));
      // Update central map under 'albums'
      final albumsJson = prefs.getString('albums');
      Map<String, dynamic> albumsMap = {};
      if (albumsJson != null) {
        try {
          albumsMap = json.decode(albumsJson) as Map<String, dynamic>;
        } catch (_) {
          albumsMap = {};
        }
      }
      albumsMap[name] = tagged;
      await prefs.setString('albums', json.encode(albumsMap));
      developer.log(
        '📁 Album created and saved: $name with ${tagged.length} images',
      );
      if (!mounted) return;
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Album "$name" created with ${tagged.length} images'),
        ),
      );
      widget.onAlbumCreated?.call();
    }
  }

  /// Process an album (frontend-only simulation for the "sparks" flow).
  /// Loads the album from SharedPreferences and shows a progress dialog
  /// while iterating the images. This is a lightweight front-end step
  /// that prepares the UI/flow before adding device-level scanning.
  Future<void> processAlbum(String name) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> urls = [];
    try {
      final albumsJson = prefs.getString('albums');
      if (albumsJson != null) {
        final Map<String, dynamic> map = json.decode(albumsJson);
        if (map.containsKey(name)) {
          urls = List<String>.from(map[name]);
        }
      }
      if (urls.isEmpty) {
        final albumKey = prefs.getString('album_$name');
        if (albumKey != null) {
          urls = (json.decode(albumKey) as List).cast<String>();
        }
      }
    } catch (_) {}

    if (urls.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Album "$name" is empty or not found.')),
      );
      return;
    }

    if (!mounted) return;
    double progress = 0.0;
    final total = urls.length;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            // Kick off the simulated processing on first build
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              for (var i = 0; i < total; i++) {
                await Future.delayed(const Duration(milliseconds: 150));
                setState(() {
                  progress = (i + 1) / total;
                });
              }
            });

            return AlertDialog(
              title: Text('Processing album "$name"'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text('${(progress * 100).round()}%'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // disallow closing while running; if the user really wants to
                    // cancel they can use the system back button, but keep UI simple.
                  },
                  child: const Text('Please wait'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Processed ${urls.length} images from "$name"')),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.shade900
                  : Colors.grey.shade300,
            ],
          ),
        ),
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : imageUrls.isEmpty
            ? const Center(
                child: Text(
                  'No photos found in gallery.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              )
            : Column(
                children: [
                  // Add top padding for status bar
                  SizedBox(height: MediaQuery.of(context).padding.top),
                  // Gallery title and Credits
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                    child: SizedBox(
                      height: 100,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Three dots menu on the left at credits height
                          Positioned(
                            left: -15,
                            top: 0,
                            child: IconButton(
                              icon: Icon(
                                Icons.more_vert,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                                size: 28,
                              ),
                              onPressed: widget.onSettingsTap,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                          // Credits on the right
                          Positioned(
                            right: 5,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 4,
                                top: 6,
                                bottom: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 80,
                                    ),
                                    child: ShaderMask(
                                      shaderCallback: (bounds) =>
                                          const LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              Colors.black87,
                                              Color(0xFFC0C0C0),
                                              Colors.black87,
                                            ],
                                            stops: [0.1, 0.5, 0.93],
                                          ).createShader(bounds),
                                      child: Text(
                                        '1,000',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Transform.scale(
                                    scale: 1.8,
                                    child: Image.asset(
                                      'assets/T Creadit Icon.png',
                                      width: 30,
                                      height: 30,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Unscanned button on the right (if any unscanned)
                          if (_currentUnscannedCount > 0)
                            Positioned(
                              right: 5,
                              top: 50,
                              child: GestureDetector(
                                onTap: _showUnscannedModal,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.orange.shade400,
                                        Colors.orange.shade600,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.pending_outlined,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Unscanned $_currentUnscannedCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Active search filters
                  if (searchQuery.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ...searchQuery
                                      .split(' ')
                                      .where((tag) => tag.isNotEmpty)
                                      .map(
                                        (tag) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.lightBlue.shade400,
                                                  Colors.lightBlue.shade600,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color:
                                                    Colors.lightBlue.shade300,
                                                width: 1.5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.2),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  tag,
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      final tags = searchQuery
                                                          .split(' ')
                                                          .where(
                                                            (t) =>
                                                                t != tag &&
                                                                t.isNotEmpty,
                                                          )
                                                          .toList();
                                                      searchQuery = tags.join(
                                                        ' ',
                                                      );
                                                      _searchController.text =
                                                          searchQuery;
                                                    });
                                                    widget.onSearchChanged
                                                        ?.call();
                                                  },
                                                  child: Icon(
                                                    Icons.close,
                                                    size: 16,
                                                    color:
                                                        Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  searchQuery = '';
                                  _searchController.text = '';
                                });
                                widget.onSearchChanged?.call();
                              },
                              icon: const Icon(Icons.clear_all, size: 16),
                              label: const Text('Clear'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.lightBlue.shade300,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Sort toggle on the right
                          TextButton.icon(
                            icon: Icon(
                              _sortNewestFirst
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black87,
                              size: 20,
                            ),
                            label: Text(
                              _sortNewestFirst ? 'Newest' : 'Oldest',
                              style: TextStyle(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _sortNewestFirst = !_sortNewestFirst;
                              });
                            },
                          ),
                        ],
                      ),
                    ), // Show album chips (horizontal) when albums exist.
                  if (albums.isNotEmpty)
                    SizedBox(
                      height: 64,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (ctx, idx) {
                          final name = albums.keys.elementAt(idx);
                          final count = albums[name]?.length ?? 0;
                          return ActionChip(
                            label: Text('$name ($count)'),
                            onPressed: () {
                              // Open AlbumScreen to show album contents
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => const AlbumScreen(),
                                ),
                              );
                            },
                          );
                        },
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemCount: albums.length,
                      ),
                    ),

                  Expanded(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onScaleStart: (details) {
                            _lastScale = 1.0;
                          },
                          onScaleUpdate: (details) {
                            // Detect scale changes more reliably with lower threshold for immediate response
                            final scaleDiff = details.scale - _lastScale;

                            if (scaleDiff.abs() > 0.05) {
                              if (scaleDiff > 0) {
                                // Pinch out - zoom in (fewer columns)
                                setState(() {
                                  if (_crossAxisCount > 1) _crossAxisCount--;
                                });
                              } else {
                                // Pinch in - zoom out (more columns)
                                setState(() {
                                  if (_crossAxisCount < 5) _crossAxisCount++;
                                });
                              }
                              _lastScale = details.scale;
                            }
                          },
                          onScaleEnd: (details) {
                            _lastScale = 1.0;
                          },
                          child: Builder(
                            builder: (context) {
                              var filtered = imageUrls.where((u) {
                                final tags = photoTags[p.basename(u)] ?? [];
                                if (searchQuery.isEmpty) return true;

                                // Special case: "None" searches for untagged photos
                                if (searchQuery.trim().toLowerCase() ==
                                    'none') {
                                  return tags.isEmpty;
                                }

                                // Split search query into individual search terms
                                final searchTerms = searchQuery
                                    .split(' ')
                                    .where((term) => term.isNotEmpty)
                                    .map((term) => term.toLowerCase())
                                    .toList();

                                // Check if any photo tag contains any of the search terms
                                return searchTerms.any(
                                  (searchTerm) => tags.any(
                                    (t) => t.toLowerCase().contains(searchTerm),
                                  ),
                                );
                              }).toList();

                              // Apply sorting based on creation date
                              filtered.sort((a, b) {
                                // For local: assets, get creation date from AssetEntity
                                if (a.startsWith('local:') &&
                                    b.startsWith('local:')) {
                                  final aId = a.substring('local:'.length);
                                  final bId = b.substring('local:'.length);
                                  final aAsset = _localAssets[aId];
                                  final bAsset = _localAssets[bId];
                                  if (aAsset != null && bAsset != null) {
                                    final aDate = aAsset.createDateTime;
                                    final bDate = bAsset.createDateTime;
                                    return _sortNewestFirst
                                        ? bDate.compareTo(aDate) // newest first
                                        : aDate.compareTo(
                                            bDate,
                                          ); // oldest first
                                  }
                                }
                                return 0; // Keep original order if can't determine dates
                              });

                              // Adjust spacing based on column count - fewer columns = more spacing
                              final spacing = _crossAxisCount <= 2
                                  ? 4.0
                                  : (_crossAxisCount == 3 ? 3.0 : 2.0);

                              return Column(
                                children: [
                                  // Select button row
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      4,
                                    ),
                                    child: Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              // Toggle select mode
                                              _isSelectMode = !_isSelectMode;
                                              if (!_isSelectMode) {
                                                // Exit select mode and clear selections
                                                _selectedKeys.clear();
                                              }
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _isSelectMode
                                                  ? Colors.blue.shade50
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: _isSelectMode
                                                    ? Colors.blue.shade400
                                                    : Colors.grey.shade300,
                                                width: 2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.1),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _isSelectMode
                                                      ? Icons.check_box
                                                      : Icons
                                                            .check_box_outline_blank,
                                                  color: _isSelectMode
                                                      ? Colors.blue.shade700
                                                      : Colors.grey.shade600,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Select',
                                                  style: TextStyle(
                                                    color: _isSelectMode
                                                        ? Colors.blue.shade700
                                                        : Colors.grey.shade800,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (_isSelectMode &&
                                            _selectedKeys.isNotEmpty) ...[
                                          const SizedBox(width: 12),
                                          Text(
                                            '${_selectedKeys.length} selected',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        // Sort button on the right
                                        IconButton(
                                          icon: Icon(
                                            _sortNewestFirst
                                                ? Icons.arrow_downward
                                                : Icons.arrow_upward,
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black87,
                                            size: 24,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _sortNewestFirst =
                                                  !_sortNewestFirst;
                                            });
                                          },
                                          tooltip: _sortNewestFirst
                                              ? 'Newest first'
                                              : 'Oldest first',
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Photo Grid
                                  Expanded(
                                    child: GridView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        12,
                                        12,
                                      ),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: _crossAxisCount,
                                            mainAxisSpacing: spacing,
                                            crossAxisSpacing: spacing,
                                            childAspectRatio: 1.0,
                                          ),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final url = filtered[index];
                                        final key = p.basename(url);
                                        final fullTags = photoTags[key] ?? [];
                                        // Only show tags <= 8 characters in the grid
                                        final shortTags = fullTags
                                            .where((t) => t.length <= 8)
                                            .toList();
                                        final visibleTags = shortTags
                                            .take(3)
                                            .toList();

                                        final isSelected = _selectedKeys
                                            .contains(key);
                                        return GestureDetector(
                                          onTap: () async {
                                            if (_isSelectMode) {
                                              setState(() {
                                                if (isSelected) {
                                                  _selectedKeys.remove(key);
                                                } else {
                                                  _selectedKeys.add(key);
                                                }
                                              });
                                              return;
                                            }

                                            // Open full-screen viewer. For local assets, load the file first.
                                            if (url.startsWith('local:')) {
                                              final id = url.substring(
                                                'local:'.length,
                                              );
                                              final asset = _localAssets[id];
                                              if (asset != null) {
                                                final file = await asset.file;
                                                if (file != null && mounted) {
                                                  final nav = Navigator.of(
                                                    // ignore: use_build_context_synchronously
                                                    context,
                                                  );
                                                  nav.push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          PhotoViewer(
                                                            filePath: file.path,
                                                            heroTag: key,
                                                          ),
                                                    ),
                                                  );
                                                }
                                              }
                                            } else if (url.startsWith(
                                              'file:',
                                            )) {
                                              final path = url.substring(
                                                'file:'.length,
                                              );
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => PhotoViewer(
                                                    filePath: path,
                                                    heroTag: key,
                                                  ),
                                                ),
                                              );
                                            } else {
                                              final resolved =
                                                  ApiService.resolveImageUrl(
                                                    url,
                                                  );
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => PhotoViewer(
                                                    networkUrl: resolved,
                                                    heroTag: key,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          onLongPress: () {
                                            setState(() {
                                              _isSelectMode = true;
                                              _selectedKeys.add(key);
                                            });
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                // Wrap the image in a Hero for smooth transition to the fullscreen viewer.
                                                Hero(
                                                  tag: key,
                                                  child:
                                                      url.startsWith('local:')
                                                      ? FutureBuilder<
                                                          Uint8List?
                                                        >(
                                                          future:
                                                              _getThumbForAsset(
                                                                url.substring(
                                                                  6,
                                                                ),
                                                              ),
                                                          builder: (context, snap) {
                                                            if (snap.hasData &&
                                                                snap.data !=
                                                                    null) {
                                                              return Image.memory(
                                                                snap.data!,
                                                                fit: BoxFit
                                                                    .cover,
                                                              );
                                                            }
                                                            if (snap.connectionState ==
                                                                ConnectionState
                                                                    .waiting) {
                                                              return Container(
                                                                color: Colors
                                                                    .black26,
                                                              );
                                                            }
                                                            return Container(
                                                              color: Colors
                                                                  .black26,
                                                              child: const Icon(
                                                                Icons
                                                                    .broken_image,
                                                                color: Colors
                                                                    .white54,
                                                              ),
                                                            );
                                                          },
                                                        )
                                                      : (url.startsWith('file:')
                                                            ? (() {
                                                                final path = url
                                                                    .substring(
                                                                      'file:'
                                                                          .length,
                                                                    );
                                                                return ClipRRect(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        6,
                                                                      ),
                                                                  child: Image.file(
                                                                    File(path),
                                                                    fit: BoxFit
                                                                        .cover,
                                                                  ),
                                                                );
                                                              })()
                                                            : Image.network(
                                                                ApiService.resolveImageUrl(
                                                                  url,
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                                // Show a neutral placeholder instead of the
                                                                // engine's red X when the server returns 404
                                                                // or other network errors.
                                                                errorBuilder:
                                                                    (
                                                                      context,
                                                                      error,
                                                                      stackTrace,
                                                                    ) {
                                                                      return Container(
                                                                        color: Colors
                                                                            .black26,
                                                                        child: const Center(
                                                                          child: Icon(
                                                                            Icons.broken_image,
                                                                            color:
                                                                                Colors.white54,
                                                                            size:
                                                                                36,
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                              )),
                                                ),
                                                if (_isSelectMode)
                                                  Positioned(
                                                    top: 8,
                                                    left: 8,
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: isSelected
                                                            ? Colors.blueAccent
                                                            : Colors.black54,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            6,
                                                          ),
                                                      child: Icon(
                                                        isSelected
                                                            ? Icons.check_box
                                                            : Icons.crop_square,
                                                        color: Colors.white,
                                                        size: 18,
                                                      ),
                                                    ),
                                                  ),
                                                Positioned(
                                                  left: 8,
                                                  right: 8,
                                                  bottom: 8,
                                                  child: LayoutBuilder(
                                                    builder:
                                                        (context, constraints) {
                                                          final chips =
                                                              _buildTagChipsForWidth(
                                                                visibleTags,
                                                                fullTags,
                                                                constraints
                                                                    .maxWidth,
                                                              );
                                                          return Wrap(
                                                            spacing: 4,
                                                            children: chips,
                                                          );
                                                        },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // Floating controls overlay - bottom right (menu buttons)
                        Positioned(
                          bottom: 80,
                          right: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    showDebug
                                        ? Icons.bug_report_sharp
                                        : Icons.bug_report,
                                    color: Colors.white,
                                  ),
                                  onPressed: () =>
                                      setState(() => showDebug = !showDebug),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                  ),
                                  tooltip: 'Scan now',
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (ctx) {
                                        return SafeArea(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.photo_library,
                                                ),
                                                title: const Text(
                                                  'Scan missing images',
                                                ),
                                                onTap: () {
                                                  Navigator.pop(ctx);
                                                  _manualScan(force: false);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.verified,
                                                  color: Colors.deepPurple,
                                                ),
                                                title: const Text(
                                                  'Validate all classifications',
                                                ),
                                                subtitle: const Text(
                                                  'Re-check all tagged photos with CLIP',
                                                ),
                                                onTap: () {
                                                  Navigator.pop(ctx);
                                                  _validateAllClassifications();
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.delete_forever,
                                                ),
                                                title: const Text(
                                                  'Remove all persisted tags',
                                                ),
                                                subtitle: const Text(
                                                  'Clears saved scan results for all photos',
                                                ),
                                                onTap: () async {
                                                  Navigator.pop(ctx);
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (dctx) => AlertDialog(
                                                      title: const Text(
                                                        'Confirm',
                                                      ),
                                                      content: const Text(
                                                        'Are you sure you want to remove all persisted tags? '
                                                        'This cannot be undone.',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                dctx,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                dctx,
                                                                true,
                                                              ),
                                                          child: const Text(
                                                            'Remove',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm != true) return;
                                                  try {
                                                    // Clear all tags at once (much faster)
                                                    final removed =
                                                        await TagStore.clearAllTags();

                                                    // Clear in-memory tags
                                                    photoTags.clear();

                                                    // Update UI and unscanned counter
                                                    if (mounted) {
                                                      await _updateUnscannedCount();
                                                      setState(() {});
                                                    }

                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        // ignore: use_build_context_synchronously
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Removed $removed tags from storage',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    developer.log(
                                                      'Failed to remove tags: $e',
                                                    );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        // ignore: use_build_context_synchronously
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Failed to remove tags',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.refresh,
                                                ),
                                                title: const Text(
                                                  'Force rescan all device images',
                                                ),
                                                onTap: () {
                                                  Navigator.pop(ctx);
                                                  _manualScan(force: true);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.cancel,
                                                ),
                                                title: const Text('Cancel'),
                                                onTap: () => Navigator.pop(ctx),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Floating glassmorphic scanning progress overlay
                        if (_scanning)
                          Positioned(
                            left: 16,
                            right: 100,
                            bottom: 100,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey.shade900
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: Colors.lightBlue.shade300,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Icon(
                                          _scanPaused
                                              ? Icons.pause_circle_filled
                                              : Icons.sync,
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.grey.shade900
                                              : Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  '${(_scanProgress * 100).round()}%',
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    'Scanning images',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          (Theme.of(
                                                                        context,
                                                                      ).brightness ==
                                                                      Brightness
                                                                          .dark
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .black87)
                                                              .withValues(
                                                                alpha: 0.9,
                                                              ),
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '$_scanProcessed / $_scanTotal processed',
                                              style: TextStyle(
                                                color:
                                                    (Theme.of(
                                                                  context,
                                                                ).brightness ==
                                                                Brightness.dark
                                                            ? Colors.white
                                                            : Colors.black87)
                                                        .withValues(alpha: 0.8),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Flexible(
                                        flex: 0,
                                        child: IconButton(
                                          icon: Icon(
                                            _showPerformanceMonitor
                                                ? Icons.speed
                                                : Icons.speed_outlined,
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black87,
                                            size: 28,
                                          ),
                                          tooltip: 'Performance Monitor',
                                          onPressed: () => setState(
                                            () => _showPerformanceMonitor =
                                                !_showPerformanceMonitor,
                                          ),
                                        ),
                                      ),
                                      Flexible(
                                        flex: 0,
                                        child: IconButton(
                                          icon: Icon(
                                            _scanPaused
                                                ? Icons.play_circle_filled
                                                : Icons.pause_circle_filled,
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black87,
                                            size: 32,
                                          ),
                                          tooltip: _scanPaused
                                              ? 'Resume scan'
                                              : 'Pause scan',
                                          onPressed: () => setState(
                                            () => _scanPaused = !_scanPaused,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _scanTotal > 0
                                          ? _scanProgress
                                          : null,
                                      minHeight: 5,
                                      backgroundColor:
                                          (Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87)
                                              .withValues(alpha: 0.3),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Background validation indicator (compact, non-intrusive)
                        if (_validating || _validationSuggestions.isNotEmpty)
                          Positioned(
                            left: 16,
                            bottom: 40,
                            child: GestureDetector(
                              onTap: _validating
                                  ? _showValidationProgressDialog
                                  : _showReviewChangesDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade700.withValues(
                                    alpha: 0.9,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_validating) ...[
                                      SizedBox(
                                        width: 24,
                                        height: 12,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: List.generate(3, (index) {
                                            return TweenAnimationBuilder<
                                              double
                                            >(
                                              tween: Tween(
                                                begin: 0.3,
                                                end: 1.0,
                                              ),
                                              duration: const Duration(
                                                milliseconds: 600,
                                              ),
                                              curve: Curves.easeInOut,
                                              builder: (context, value, child) {
                                                return Opacity(
                                                  opacity: value,
                                                  child: Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: Colors.white,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                );
                                              },
                                              onEnd: () {
                                                if (mounted && _validating) {
                                                  Future.delayed(
                                                    Duration(
                                                      milliseconds: index * 200,
                                                    ),
                                                    () {
                                                      if (mounted) {
                                                        setState(() {});
                                                      }
                                                    },
                                                  );
                                                }
                                              },
                                            );
                                          }),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _validationTotal == 0
                                            ? 'Preparing...'
                                            : 'Validating $_validationProcessed/$_validationTotal',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ] else ...[
                                      const Icon(
                                        Icons.rate_review,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Review ${_validationSuggestions.length} Changes',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    if (_validationSuggestions.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade600,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          '${_validationSuggestions.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.touch_app,
                                      color: Colors.white70,
                                      size: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Performance Monitor Overlay
                        if (_scanning && _showPerformanceMonitor)
                          Positioned(
                            left: 16,
                            top: 80,
                            child: Container(
                              width: 200,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.lightBlue.shade300,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.lightBlue.shade300.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.speed,
                                        color: Colors.lightBlue.shade300,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      const Expanded(
                                        child: Text(
                                          'Performance',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => setState(
                                          () => _showPerformanceMonitor = false,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(
                                    color: Colors.white24,
                                    height: 16,
                                  ),
                                  _buildPerfStat(
                                    'RAM Usage',
                                    '${_currentRamUsageMB.toStringAsFixed(1)} MB',
                                    Icons.memory,
                                  ),
                                  _buildPerfStat(
                                    'Peak RAM',
                                    '${_peakRamUsageMB.toStringAsFixed(1)} MB',
                                    Icons.trending_up,
                                  ),
                                  _buildPerfStat(
                                    'Batch Size',
                                    '$_currentBatchSize photos',
                                    Icons.burst_mode,
                                  ),
                                  _buildPerfStat(
                                    'Batch Time',
                                    '${(_avgBatchTimeMs / 1000).toStringAsFixed(1)}s',
                                    Icons.timer,
                                  ),
                                  _buildPerfStat(
                                    'Speed',
                                    '${_imagesPerSecond.toStringAsFixed(1)} img/s',
                                    Icons.flash_on,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      // Pricing moved to Settings screen; FAB removed.
      bottomNavigationBar: _isSelectMode && _selectedKeys.isNotEmpty
          ? ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.25),
                        Colors.white.withValues(alpha: 0.15),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selectedKeys.length} selected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.withValues(alpha: 0.8),
                                  Colors.blueAccent.withValues(alpha: 0.8),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _createAlbumFromSelection,
                              icon: const Icon(
                                Icons.create_new_folder,
                                size: 20,
                              ),
                              label: Text(
                                'Create Album (${_selectedKeys.length})',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      bottomSheet: showDebug
          ? Container(
              color: Colors.black87,
              height: 240,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Server: ${ApiService.baseUrl}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          onPressed: _loadAllImages,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: photoTags.entries
                              .map(
                                (e) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    '${e.key}: ${e.value.isNotEmpty ? e.value.join(', ') : '(none)'}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
