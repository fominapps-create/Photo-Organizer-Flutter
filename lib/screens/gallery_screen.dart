import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:lottie/lottie.dart';
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

class GalleryScreenState extends State<GalleryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<String> imageUrls = [];
  Map<String, List<String>> photoTags = {};
  Map<String, List<String>> photoAllDetections =
      {}; // All detections including small objects
  bool loading = true;
  // Device-local asset storage and thumbnail cache for local view
  final Map<String, AssetEntity> _localAssets = {};
  final Map<String, Uint8List> _thumbCache = {};
  Map<String, List<String>> albums = {};
  String searchQuery = '';
  bool showDebug = false;
  bool _showSearchBar = true;
  bool _sortNewestFirst = true; // true = newest first, false = oldest first
  bool _showTags = true; // Toggle to show/hide photo tags
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  int _crossAxisCount = 4;
  bool _isSelectMode = false;
  final Set<String> _selectedKeys = {};
  final Map<String, double> _textWidthCache = {};
  // Auto-scan state
  bool _scanning = false;
  bool _scanProgressMinimized = false;
  final ValueNotifier<double> _scanProgressNotifier = ValueNotifier<double>(
    0.0,
  ); // Use notifier to avoid rebuilding whole tree
  final ValueNotifier<int> _scannedCountNotifier = ValueNotifier<int>(
    0,
  ); // Track scanned photos count
  double _scanProgress = 0.0; // 0.0-1.0
  int _scanTotal = 0;
  bool _scanPaused = false;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showScrollToTop = ValueNotifier<bool>(false);
  int _scanProcessed = 0;
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
  bool _validationComplete = false; // Track if full validation is done

  // Track changed images for detailed view
  final List<Map<String, dynamic>> _validationChanges = [];
  // Track recently updated photos for animation (photoID -> timestamp)
  final Map<String, DateTime> _recentlyValidated = {};

  // Dot animation state - use ValueNotifier to avoid full rebuilds
  final ValueNotifier<int> _dotIndexNotifier = ValueNotifier<int>(0);
  Timer? _dotAnimationTimer;
  Timer? _autoScanRetryTimer;
  Timer? _progressRefreshTimer; // Refresh progress display periodically

  // Cached filtered list to avoid recomputing on every build
  List<String> _cachedFilteredUrls = [];
  String _lastSearchQuery = '';
  int _lastImageUrlsLength = 0;
  int _lastPhotoTagsLength = 0;
  bool _sortNewestFirstCached = true;

  // Cached local photo count
  int _cachedLocalPhotoCount = 0;

  // Thumbnail future cache to prevent recreating futures on rebuild
  final Map<String, Future<Uint8List?>> _thumbFutureCache = {};

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
    const double horizontalPadding = 6 * 2;
    const double chipSpacing = 4.0;
    const double maxChipWidth = 80.0; // Maximum width for a single chip
    const double minFontSize = 9.0;
    const double defaultFontSize = 12.0;

    final baseStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.8),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ],
    );

    double used = 0.0;
    final List<Widget> chips = [];
    final List<double> chipWidths = [];

    for (var t in visibleTags) {
      // Calculate text width at default size
      final defaultStyle = baseStyle.copyWith(fontSize: defaultFontSize);
      final textWidth = _measureTextWidth(t, defaultStyle);
      double chipWidth = textWidth + horizontalPadding;
      double fontSize = defaultFontSize;

      // If text is too wide, scale down font size to fit max chip width
      if (chipWidth > maxChipWidth) {
        fontSize = (defaultFontSize * maxChipWidth / chipWidth).clamp(
          minFontSize,
          defaultFontSize,
        );
        chipWidth = maxChipWidth;
      }

      final finalStyle = baseStyle.copyWith(fontSize: fontSize);
      final nextUsed = chips.isEmpty
          ? used + chipWidth
          : used + chipSpacing + chipWidth;

      if (nextUsed <= maxWidth) {
        // add this chip
        used = nextUsed;
        chipWidths.add(chipWidth);
        chips.add(
          GestureDetector(
            onTap: () => _showTagMenu(t),
            child: Container(
              constraints: BoxConstraints(maxWidth: maxChipWidth),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    offset: const Offset(0, 0.5),
                    blurRadius: 1,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Text(
                t,
                style: finalStyle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
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
      final plusWidth =
          _measureTextWidth(
            plusStr,
            baseStyle.copyWith(fontSize: defaultFontSize),
          ) +
          horizontalPadding;
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
                color: Colors.transparent,
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    offset: const Offset(0, 0.5),
                    blurRadius: 1,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Text(
                plusStr,
                style: baseStyle.copyWith(fontSize: defaultFontSize),
              ),
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
                  color: Colors.transparent,
                  border: Border.all(color: Colors.white, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      offset: const Offset(0, 0.5),
                      blurRadius: 1,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  plusStr,
                  style: baseStyle.copyWith(fontSize: defaultFontSize),
                ),
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
              color: Colors.transparent,
              border: Border.all(color: Colors.white, width: 1.5),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  offset: const Offset(0, 0.5),
                  blurRadius: 1,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Text(
              'None',
              style: baseStyle.copyWith(fontSize: defaultFontSize),
            ),
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
    _scrollController.addListener(_scrollListener);
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

    // Clean up any empty tag entries from failed scans
    final cleanedCount = await TagStore.cleanEmptyTags();
    if (cleanedCount > 0) {
      developer.log('🧹 Cleaned up $cleanedCount empty tag entries');
    }

    developer.log('🔄 Calling _loadOrganizedImages...');
    await _loadOrganizedImages();
    developer.log(
      '✅ _loadOrganizedImages completed. Found ${imageUrls.length} photos',
    );

    await _loadTags();
    developer.log('Total photos in gallery: ${imageUrls.length}');
    setState(() => loading = false);

    // Sync tags from server in background (non-blocking) if available
    _syncTagsFromServerInBackground();

    _startAutoScanIfNeeded();
    _startAutoScanRetryTimer();
  }

  /// Sync tags from server in background without blocking UI
  void _syncTagsFromServerInBackground() {
    ApiService.pingServer(timeout: const Duration(seconds: 2)).then((online) {
      if (online && mounted) {
        _syncTagsFromServer().then((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  /// Start a timer that periodically retries scanning if server was unavailable
  void _startAutoScanRetryTimer() {
    _autoScanRetryTimer?.cancel();
    _autoScanRetryTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      // Only retry if not already scanning/validating and not complete
      if (!_scanning && !_validating && !_validationComplete && mounted) {
        developer.log(
          '🔄 Auto-retry: Reloading photos and checking if scan is needed...',
        );
        // Reload photos first to pick up any new ones
        await _loadAllImages();
        await _startAutoScanIfNeeded();
      }
      // Stop retrying once validation is complete
      if (_validationComplete) {
        developer.log(
          '✅ Auto-retry: Validation complete, stopping retry timer',
        );
        timer.cancel();
        _autoScanRetryTimer = null;
      }
    });
  }

  /// Start a timer that refreshes the progress display every 5 seconds during scanning
  void _startProgressRefreshTimer() {
    _progressRefreshTimer?.cancel();
    _progressRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && (_scanning || _validating)) {
        setState(() {
          // Just trigger a rebuild to update percentage display
        });
      } else {
        timer.cancel();
        _progressRefreshTimer = null;
      }
    });
  }

  /// Show a small tooltip-like popup near the badge
  OverlayEntry? _badgeTooltipEntry;
  void _showBadgeTooltip(BuildContext context, String message, Color color) {
    _badgeTooltipEntry?.remove();
    final overlay = Overlay.of(context);
    _badgeTooltipEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 62,
        right: 210,
        child: FractionalTranslation(
          translation: const Offset(
            0.5,
            0,
          ), // Shift left by half width to center under badge
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_badgeTooltipEntry!);
    // Auto-dismiss after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), () {
      _badgeTooltipEntry?.remove();
      _badgeTooltipEntry = null;
    });
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
    developer.log('🎯 _startAutoScanIfNeeded() ENTRY');
    // Only scan if there are local images and we aren't already scanning
    if (_scanning) {
      developer.log('⏸️ Scan already in progress');
      return;
    }
    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();
    developer.log('📊 Total local photos: ${localUrls.length}');
    if (localUrls.isEmpty) {
      developer.log('⚠️ No local photos found, returning');
      return;
    }

    // Check server connectivity before scanning
    developer.log(
      '🔌 Checking server connectivity at ${ApiService.baseUrl}...',
    );
    final serverAvailable = await ApiService.pingServer(
      timeout: const Duration(seconds: 3),
      retries: 1,
    );
    if (!serverAvailable) {
      developer.log(
        '⚠️ Server not available at ${ApiService.baseUrl}, skipping auto-scan',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server offline: ${ApiService.baseUrl}'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    developer.log('✅ Server available!');

    // Only consider images that have no persisted scan entry OR have empty tags.
    // Check using canonical photoID keys from TagStore (bulk check for speed)
    final photoIDs = localUrls.map((u) => PhotoId.canonicalId(u)).toList();
    final scannedIDs = await TagStore.getPhotoIDsWithNonEmptyTags(photoIDs);

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

    // If there are photos to scan, reset validation state
    if (missing.isNotEmpty && _validationComplete) {
      developer.log('🔄 Found unscanned photos, resetting validation state');
      setState(() {
        _validationComplete = false;
      });
    }

    if (missing.isEmpty) {
      developer.log('✅ All photos already scanned!');
      developer.log('🔍 Now checking if validation is needed...');
      // Check if validation is complete
      // If all photos are scanned but validation isn't complete, trigger it
      if (!_validationComplete && !_validating) {
        developer.log(
          '🚀 All scanned but not validated. Checking for YOLO-classified photos...',
        );

        // Quick check: do we have any YOLO-classified images?
        bool hasYoloImages = false;
        const yoloCategories = {'people', 'animals', 'food'};

        for (final url in localUrls.take(10)) {
          // Just check first 10 as sample
          final photoID = PhotoId.canonicalId(url);
          final tags = await TagStore.loadLocalTags(photoID);
          if (tags != null && tags.any((tag) => yoloCategories.contains(tag))) {
            hasYoloImages = true;
            break;
          }
        }

        if (hasYoloImages) {
          developer.log(
            '📸 Found YOLO-classified photos. Starting validation...',
          );
          _validateAllClassifications();
        } else {
          developer.log(
            '✅ No YOLO-classified photos found. Marking validation as complete.',
          );
          setState(() {
            _validationComplete = true;
          });
        }
      } else {
        developer.log(
          '✅ Validation already complete or in progress. Nothing to do.',
        );
      }
      return;
    }

    // Scan all photos that need scanning
    final toScan = missing;
    developer.log('🚀 Starting scan of ${toScan.length} photos...');
    setState(() {
      _scanning = true;
      _scanTotal = toScan.length;
      developer.log('📊 SET _scanTotal = $_scanTotal');
      // Don't reset _scanPaused - let user control pause/resume
      _scanProcessed = 0;
      _scanProgress = 0.0;
    });
    // Initialize scanned count notifier with current count
    _scannedCountNotifier.value = photoTags.length;
    // Start progress refresh timer (updates UI every 5 seconds)
    _startProgressRefreshTimer();

    await _scanImages(toScan);

    // Stop progress refresh timer
    _progressRefreshTimer?.cancel();
    _progressRefreshTimer = null;

    setState(() {
      _scanning = false;
      _scanProgress = 0.0;
      _scanTotal = 0;
    });

    // Cancel dot animation if validation is also complete
    if (!_validating) {
      _dotAnimationTimer?.cancel();
      _dotAnimationTimer = null;
      // Show combined completion message if validation is already done
      if (_validationComplete) {
        _showGalleryReadyMessage();
      }
    }
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

    setState(() {
      _scanning = true;
      _scanTotal = toScan.length;
      developer.log('📊 SET _scanTotal = $_scanTotal');
      // Don't reset _scanPaused - let user control pause/resume
      _scanProcessed = 0;
      _scanProgress = 0.0;
    });
    // Initialize scanned count notifier with current count
    _scannedCountNotifier.value = photoTags.length;
    // Start progress refresh timer (updates UI every 5 seconds)
    _startProgressRefreshTimer();

    await _scanImages(toScan);

    // Stop progress refresh timer
    _progressRefreshTimer?.cancel();
    _progressRefreshTimer = null;

    // Note: Skip _syncTagsFromServer() and _loadTags() here - we already have
    // all tags in memory from the batch processing loop. Re-downloading from
    // server and re-reading from storage is redundant and slow.
    developer.log('✅ Scan complete - tags already in memory, skipping redundant sync/load');

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
      _validationComplete = false;
      _validationTotal = 0;
      _validationProcessed = 0;
    });

    developer.log('🔍 VALIDATION STARTED - _validating set to true');

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
      setState(() {
        _validating = false;
      });
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

    // OPTIMIZATION: Load all tags in one batch instead of individual loads
    final allPhotoIDs = localUrls.map((u) => PhotoId.canonicalId(u)).toList();
    final allTagsMap = await TagStore.loadAllTagsMap(allPhotoIDs);
    developer.log('📦 Loaded ${allTagsMap.length} tags in batch');

    // Find photos with YOLO tags that need validation
    final urlsToValidate = <String>[];
    for (final url in localUrls) {
      final photoID = PhotoId.canonicalId(url);
      final tags = allTagsMap[photoID];

      if (tags == null || tags.isEmpty) continue;

      // Include ONLY if image has YOLO-detectable categories (people/animals/food)
      // Don't validate unknown images - they already failed, nothing to validate
      // Don't validate scenery/document - those are CLIP-only, not YOLO
      final hasYoloTags = tags.any((tag) => yoloCategories.contains(tag));
      if (hasYoloTags) {
        urlsToValidate.add(url);
      }
    }

    developer.log('📸 Found ${urlsToValidate.length} photos needing validation');

    // Load file bytes only for photos that need validation
    for (final url in urlsToValidate) {
      final photoID = PhotoId.canonicalId(url);
      final tags = allTagsMap[photoID]!;

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

    developer.log(
      '✅ Found ${imagesToValidate.length} YOLO-classified images to validate',
    );

    if (imagesToValidate.isEmpty) {
      developer.log('⚠️ No YOLO-classified images found');
      setState(() {
        _validating = false;
        _validationComplete =
            true; // Mark as complete since nothing to validate
      });
      // Cancel dot animation if scanning is also complete
      if (!_scanning) {
        _dotAnimationTimer?.cancel();
        _dotAnimationTimer = null;
      }
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

    // Auto-start validation - no confirmation needed
    developer.log(
      '🚀 Auto-starting background validation for ${imagesToValidate.length} photos',
    );

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
    final scanStartTime = DateTime.now();

    // Track YOLO-classified images for background validation
    final yoloClassifiedImages = <Map<String, dynamic>>[]; // {file, url, tags}

    // Enable streaming validation: start validation as images are scanned
    // This allows scan and validation to run in parallel without overwhelming the phone
    const bool enableStreamingValidation = true;
    const int validationStartThreshold =
        20; // Start validation after 20 images scanned

    // Pipeline approach: process multiple batches concurrently for better throughput
    // Use Completer to properly track batch completion
    const int maxConcurrentBatches =
        3; // Increased from 2 to 3 for better pipeline
    final activeBatches = <Completer<void>>[];
    int batchStart = 0;

    while (batchStart < urls.length) {
      developer.log(
        '🔄 DEBUG: Loop iteration, batchStart=$batchStart, activeBatches.length=${activeBatches.length}',
      );

      // Check if scan was stopped
      if (!_scanning) {
        developer.log('⏹️ Scan stopped by user');
        await Future.wait(activeBatches.map((c) => c.future));
        return;
      }

      // Check for pause
      while (_scanPaused) {
        if (!mounted || !_scanning) {
          await Future.wait(activeBatches.map((c) => c.future));
          return;
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // If at max capacity, wait for ANY batch to complete
      if (activeBatches.length >= maxConcurrentBatches) {
        developer.log(
          '⏸️  DEBUG: At max capacity, waiting for ANY batch to complete...',
        );
        await Future.any(activeBatches.map((c) => c.future));
        developer.log(
          '✅ DEBUG: A batch completed! Removing completed batches...',
        );
        // Remove completed batches
        activeBatches.removeWhere((c) => c.isCompleted);
        developer.log(
          '📊 DEBUG: After cleanup, activeBatches.length=${activeBatches.length}',
        );
      }

      final batchEnd = (batchStart + batchSize).clamp(0, urls.length);
      final batch = urls.sublist(batchStart, batchEnd);

      // Create completer for this batch
      final completer = Completer<void>();
      activeBatches.add(completer);
      developer.log(
        '🚀 DEBUG: Starting batch ${(batchStart ~/ batchSize) + 1}, activeBatches.length now=${activeBatches.length}',
      );

      // Start batch processing (don't await - let it run concurrently)
      _processBatchConcurrent(
            batch,
            batchStart,
            batchSize,
            urls.length,
            yoloClassifiedImages,
            scanStartTime,
          )
          .then((_) {
            completer.complete();

            // Trigger streaming validation if enabled and threshold reached
            if (enableStreamingValidation &&
                !_validating &&
                yoloClassifiedImages.length >= validationStartThreshold) {
              developer.log(
                '🔄 Streaming validation: Starting validation with ${yoloClassifiedImages.length} images (threshold: $validationStartThreshold)',
              );
              _startStreamingValidation(yoloClassifiedImages);
            }
          })
          .catchError((e) {
            developer.log('Batch error: $e');
            completer.complete(); // Complete even on error
          });

      batchStart += batchSize;
    }

    // Wait for all remaining batches to complete
    await Future.wait(activeBatches.map((c) => c.future));

    // After all batches complete, run background validation if we have YOLO-classified images
    // Note: With streaming validation enabled, validation may already be running
    if (yoloClassifiedImages.isNotEmpty && mounted && !_validating) {
      developer.log(
        '🔍 Starting validation after scan complete (${yoloClassifiedImages.length} images)',
      );
      _runBackgroundValidation(yoloClassifiedImages);
    } else if (_validating) {
      developer.log('✅ Validation already running in parallel - continuing...');
    }
  }

  /// Process a single batch concurrently (for pipeline processing)
  Future<void> _processBatchConcurrent(
    List<String> batch,
    int batchStart,
    int batchSize,
    int totalUrls,
    List<Map<String, dynamic>> yoloClassifiedImages,
    DateTime scanStartTime,
  ) async {
    final batchEnd = (batchStart + batchSize).clamp(0, totalUrls);
    final batchNumber = (batchStart ~/ batchSize) + 1;
    final totalBatches = (totalUrls / batchSize).ceil();

    developer.log('\n════════════════════════════════════════════════════════');
    developer.log(
      '⏳ BATCH $batchNumber/$totalBatches - Processing photos ${batchStart + 1}-$batchEnd [CONCURRENT START]',
    );
    developer.log('════════════════════════════════════════════════════════');

    final batchStartTime = DateTime.now();

    // Update batch size and periodically check RAM/CPU (every 5 batches)
    if (mounted) {
      _currentBatchSize = batchSize;
      if (batchNumber % 5 == 0) {
        _currentRamUsageMB = await _getCurrentRamUsage();
        _peakRamUsageMB = _currentRamUsageMB > _peakRamUsageMB
            ? _currentRamUsageMB
            : _peakRamUsageMB;
      }
    }

    // Prepare batch of files
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
        return;
      }

      // Check for pause before uploading
      while (_scanPaused && _scanning) {
        developer.log('⏸️  Batch paused before upload...');
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || !_scanning) return;
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
      developer.log(
        '📤 BATCH $batchNumber: Starting upload/server processing...',
      );

      final res = await ApiService.uploadImagesBatch(batchItems);

      final uploadEndTime = DateTime.now();
      final uploadDuration = uploadEndTime
          .difference(uploadStartTime)
          .inMilliseconds;
      developer.log(
        '📤 BATCH $batchNumber: Upload + server processing took ${uploadDuration}ms',
      );

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
            final batchDetectionsToSave = <String, List<String>>{};

            // Check for pause before processing results
            while (_scanPaused && _scanning) {
              developer.log('⏸️  Batch paused before processing results...');
              await Future.delayed(const Duration(milliseconds: 200));
              if (!mounted || !_scanning) return;
            }

            final processingStartTime = DateTime.now();
            for (var i = 0; i < results.length && i < batchUrls.length; i++) {
              final result = results[i];
              final url = batchUrls[i];
              final basename = p.basename(url);
              final photoID = PhotoId.canonicalId(url);

              List<String> tags = [];
              List<String> allDetections = [];
              if (result is Map && result['tags'] is List) {
                tags = (result['tags'] as List).cast<String>();
              }
              // Store all detections if available (includes small objects)
              if (result is Map && result['all_detections'] is List) {
                allDetections = (result['all_detections'] as List)
                    .cast<String>();
              } else {
                // Fallback: if no separate all_detections, use tags
                allDetections = List.from(tags);
              }

              // Update in-memory tags and detections
              photoTags[basename] = tags;
              photoAllDetections[basename] = allDetections;
              batchTagsToSave[photoID] = tags;
              batchDetectionsToSave[photoID] = allDetections;
              // Update scanned count notifier for live UI updates
              _scannedCountNotifier.value = photoTags.length;

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
            await TagStore.saveLocalDetectionsBatch(batchDetectionsToSave);
            final saveEndTime = DateTime.now();
            developer.log(
              '💾 Tag save took ${saveEndTime.difference(saveStartTime).inMilliseconds}ms for ${batchTagsToSave.length} photos',
            );
          }
        } catch (e) {
          developer.log('Failed parsing batch response: $e');
          // Don't save empty tags on failure - leave photos unscanned for retry
        }
      } else {
        developer.log('Batch scan failed: status=${res.statusCode}');
        // Don't save empty tags on failure - leave photos unscanned for retry
      }
    } catch (e) {
      developer.log('Batch scan error: $e');
      // Don't save empty tags on error - leave photos unscanned for retry
    }

    // Calculate batch timing
    final batchEndTime = DateTime.now();
    final batchDuration = batchEndTime
        .difference(batchStartTime)
        .inMilliseconds;

    developer.log('════════════════════════════════════════════════════════');
    developer.log(
      '✅ BATCH $batchNumber COMPLETE: ${batchDuration}ms total (${batchUrls.isEmpty ? 0 : (batchDuration / batchUrls.length).toStringAsFixed(1)}ms per photo)',
    );
    developer.log('════════════════════════════════════════════════════════\n');

    // Update progress and performance stats
    if (mounted && _scanning) {
      final elapsedSeconds = DateTime.now().difference(scanStartTime).inSeconds;
      setState(() {
        // Set actual progress (may have been smoothly estimated during batch)
        _scanProcessed = (batchStart + batchUrls.length).clamp(0, _scanTotal);
        _scanProgress = (_scanTotal == 0)
            ? 0.0
            : (_scanProcessed / _scanTotal).clamp(0.0, 1.0);
        _scanProgressNotifier.value = _scanProgress;
        developer.log('📊 PROGRESS UPDATE: $_scanProcessed / $_scanTotal');
        _avgBatchTimeMs = batchDuration;
        _imagesPerSecond = elapsedSeconds > 0
            ? _scanProcessed / elapsedSeconds.toDouble()
            : 0;
      });
    }
  }

  /// Start streaming validation - validates images as they're scanned (parallel processing)
  /// This allows scan and validation to overlap without overwhelming the device
  void _startStreamingValidation(List<Map<String, dynamic>> imageList) {
    if (_validating) {
      developer.log('⚠️ Validation already running, skipping streaming start');
      return;
    }

    developer.log(
      '🚀 Starting streaming validation with ${imageList.length} images',
    );

    // Run validation asynchronously (don't await - let it run in parallel)
    _runStreamingValidation(imageList);
  }

  /// Run streaming validation that processes images as they become available
  /// Throttles validation to avoid overloading the device during concurrent scan+validation
  Future<void> _runStreamingValidation(
    List<Map<String, dynamic>> imageList,
  ) async {
    if (!mounted) return;

    developer.log(
      '🔍 Starting streaming CLIP validation for ${imageList.length} images',
    );

    setState(() {
      _validating = true;
      _validationComplete = false;
      _validationCancelled = false;
      _validationPaused = false;
      _validationTotal = imageList.length;
      _validationProcessed = 0;
      _validationAgreements = 0;
      _validationDisagreements = 0;
      _validationOverrides = 0;
      _validationChanges.clear();
      _recentlyValidated.clear();
    });

    try {
      // Batch size for streaming validation (matches regular validation)
      const validationBatchSize = 10;

      // Short delay between batches to avoid overwhelming phone during concurrent scan
      const delayBetweenBatches = Duration(milliseconds: 200);

      for (
        var batchStart = 0;
        batchStart < imageList.length;
        batchStart += validationBatchSize
      ) {
        if (!mounted || _validationCancelled) {
          developer.log('🛑 Streaming validation cancelled');
          return;
        }

        // Wait if paused
        while (_validationPaused && !_validationCancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }

        // Check if more images were added to the list (scanning still in progress)
        // Update total count dynamically as scan continues
        if (imageList.length > _validationTotal) {
          setState(() {
            _validationTotal = imageList.length;
          });
          developer.log(
            '📈 Updated validation total to $_validationTotal (scan added more images)',
          );
        }

        final batchEnd = (batchStart + validationBatchSize).clamp(
          0,
          imageList.length,
        );
        final batch = imageList.sublist(batchStart, batchEnd);

        developer.log(
          '🔍 Streaming validation batch ${(batchStart ~/ validationBatchSize) + 1}/${(imageList.length / validationBatchSize).ceil()} (${batch.length} images)',
        );

        // Process validation batch (same logic as regular validation)
        await _processValidationBatch(batch);

        // Add delay between batches to reduce CPU/network contention with scanning
        if (batchStart + validationBatchSize < imageList.length) {
          await Future.delayed(delayBetweenBatches);
        }
      }

      // Validation complete
      developer.log(
        '✅ Streaming validation complete: ${_validationChanges.length} improvements applied',
      );

      if (mounted) {
        setState(() {
          _validating = false;
          _validationComplete = true; // Mark validation as complete
        });

        // Cancel dot animation if scanning is also complete
        if (!_scanning) {
          _dotAnimationTimer?.cancel();
          _dotAnimationTimer = null;
          // Show combined completion message
          _showGalleryReadyMessage();
        }
      }
    } catch (e) {
      developer.log('❌ Streaming validation error: $e');
      if (mounted) {
        setState(() {
          _validating = false;
        });
        // Cancel dot animation if scanning is also complete
        if (!_scanning) {
          _dotAnimationTimer?.cancel();
          _dotAnimationTimer = null;
        }
      }
    }
  }

  /// Process a single validation batch (shared by regular and streaming validation)
  Future<void> _processValidationBatch(List<Map<String, dynamic>> batch) async {
    try {
      final validationData = <Map<String, dynamic>>[];
      final yoloTagsList = <List<String>>[];

      for (final item in batch) {
        final url = item['url'] as String;
        final filename = url.startsWith('local:')
            ? 'photo_${item['photoID']}.jpg'
            : p.basename(url);

        validationData.add({'file': item['file'], 'filename': filename});
        yoloTagsList.add(item['tags'] as List<String>);
      }

      final res = await ApiService.validateYoloClassifications(
        validationData,
        yoloTagsList,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = json.decode(res.body);

        if (body is Map && body['validations'] is List) {
          final validations = body['validations'] as List;

          for (var i = 0; i < validations.length && i < batch.length; i++) {
            final validation = validations[i];
            final item = batch[i];

            await _applyValidationResult(validation, item);
          }
        }
      }

      // Update progress
      if (mounted) {
        setState(() {
          _validationProcessed += batch.length;
        });
      }
    } catch (e) {
      developer.log('❌ Validation batch error: $e');
    }
  }

  /// Apply a single validation result (shared logic)
  Future<void> _applyValidationResult(
    Map<String, dynamic> validation,
    Map<String, dynamic> item,
  ) async {
    final url = item['url'] as String;
    final basename = p.basename(url);
    final photoID = item['photoID'] as String;
    final oldTags = item['tags'] as List<String>;

    final clipTags = (validation['clip_tags'] as List).cast<String>();
    final shouldOverride = validation['should_override'] == true;
    final agreement = validation['agreement'] == true;
    final overrideTags = validation['override_tags'] != null
        ? (validation['override_tags'] as List).cast<String>()
        : clipTags;
    final reason = validation['reason'] as String? ?? '';

    if (agreement) {
      _validationAgreements++;
      developer.log('✅ Agreement: $basename');
    } else {
      _validationDisagreements++;
      developer.log(
        '⚠️ Disagreement: $basename - ${oldTags.join(", ")} vs ${clipTags.join(", ")}',
      );

      if (shouldOverride) {
        _validationOverrides++;

        // Auto-apply the improvement
        photoTags[basename] = overrideTags;
        await TagStore.saveLocalTags(photoID, overrideTags);

        // Track for animation
        _recentlyValidated[photoID] = DateTime.now();

        // Log the change
        _validationChanges.add({
          'url': url,
          'basename': basename,
          'photoID': photoID,
          'oldTags': oldTags,
          'newTags': overrideTags,
          'clipTags': clipTags,
          'reason': reason,
        });

        developer.log(
          '🔄 Auto-applied override: $basename -> ${overrideTags.join(", ")} ($reason)',
        );

        // Update UI to show the change
        if (mounted) setState(() {});
      }
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
      _validationComplete = false;
      _validationCancelled = false;
      _validationPaused = false;
      _validationTotal = imagesToValidate.length;
      _validationProcessed = 0;
      _validationAgreements = 0;
      _validationDisagreements = 0;
      _validationOverrides = 0;
      _validationChanges.clear(); // Clear previous changes
      _recentlyValidated.clear(); // Clear previous animation timestamps
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

        // Use shared batch processing method
        await _processValidationBatch(batch);

        // Small delay between validation batches
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Validation complete
      developer.log(
        '✅ Background validation complete: $_validationAgreements agreements, $_validationDisagreements disagreements, $_validationOverrides overrides',
      );

      // Sync tags from server to ensure local cache has all override results
      await _syncTagsFromServer();
    } catch (e) {
      developer.log('⚠️ Background validation error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _validating = false;
          _validationComplete = true; // Mark validation as complete
        });
        // Cancel dot animation if scanning is also complete
        if (!_scanning) {
          _dotAnimationTimer?.cancel();
          _dotAnimationTimer = null;
          // Show combined completion message
          _showGalleryReadyMessage();
        }
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

  /// Show message when gallery is fully scanned and validated
  void _showGalleryReadyMessage() {
    if (!mounted) return;
    final totalPhotos = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Gallery ready: $totalPhotos photos scanned & verified',
        ),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Build validation status popup content
  Widget _buildValidationPopup() {
    final totalPhotos = _cachedLocalPhotoCount;
    final scannedPhotos = photoTags.length;
    final scannedPercentage = totalPhotos > 0
        ? (scannedPhotos / totalPhotos * 100).toStringAsFixed(0)
        : '0';

    // Check server status for display
    final serverOnline = ApiService.baseUrl.isNotEmpty;

    final validationStatus = _validationComplete
        ? '✓ Validated'
        : _validating
        ? 'Validating...'
        : _scanning
        ? 'Scanning...'
        : !serverOnline
        ? '⚠ Server offline'
        : 'Not validated';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _validationComplete
            ? Colors.blue.shade700
            : _scanning
            ? Colors.orange.shade700
            : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$scannedPhotos/$totalPhotos ($scannedPercentage%) • $validationStatus',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
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

              // Applied changes list (for viewing history)
              if (_validationChanges.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 20,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Auto-Applied Changes (${_validationChanges.length})',
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
                    itemCount: _validationChanges.length,
                    itemBuilder: (context, index) {
                      final change = _validationChanges[index];
                      return _buildChangeItem(change);
                    },
                  ),
                ),
              ] else if (!_validating) ...[
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No changes applied',
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

  /// Build 4-dot loading animation that lights up sequentially
  /// Uses ValueListenableBuilder to avoid rebuilding the entire widget tree
  Widget _buildLoadingDots() {
    // Start timer if not running (timer updates ValueNotifier, not setState)
    if (_dotAnimationTimer == null || !_dotAnimationTimer!.isActive) {
      _dotIndexNotifier.value = 0;
      _dotAnimationTimer?.cancel();
      _dotAnimationTimer = Timer.periodic(const Duration(milliseconds: 300), (
        timer,
      ) {
        if (mounted && (_scanning || _validating)) {
          _dotIndexNotifier.value = (_dotIndexNotifier.value + 1) % 4;
        } else {
          timer.cancel();
          _dotAnimationTimer = null;
        }
      });
    }

    return ValueListenableBuilder<int>(
      valueListenable: _dotIndexNotifier,
      builder: (context, currentIndex, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (index) {
            final isLit = index == currentIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isLit
                      ? Colors.orange.shade400
                      : Colors.grey.shade400.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
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
      // Aggressive sizing for maximum throughput while maintaining stability
      // Server can handle 6-10 img/sec with batching, so larger batches = better
      int batchSize;

      if (ramGB <= 3 || cpuCores <= 4) {
        // Low-end device: 15 images per batch
        batchSize = 15;
      } else if (ramGB <= 6 || cpuCores <= 6) {
        // Mid-range device: 30 images per batch
        batchSize = 30;
      } else if (ramGB <= 8 || cpuCores <= 8) {
        // Mid-high device: 50 images per batch
        batchSize = 50;
      } else {
        // High-end device: 75 images per batch (8+ cores or 8+ GB RAM)
        batchSize = 75;
      }

      developer.log('⚙️ Initial batch size: $batchSize (aggressive adaptive)');
      return batchSize;
    } catch (e) {
      developer.log('Failed to detect device specs: $e');
      // Conservative fallback for unknown devices
      return 5;
    }
  }

  /// Show dialog to review and approve/reject validation suggestions
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
        setState(() {
          _setImageUrls([]);
        });
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
            setState(() {
              _setImageUrls(pics);
            });
            return;
          }
        } catch (_) {}
        setState(() {
          _setImageUrls([]);
        });
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
            setState(() {
              _setImageUrls(pics);
            });
            return;
          }
        } catch (_) {}
        setState(() {
          _setImageUrls([]);
        });
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
      setState(() {
        _setImageUrls(urls);
      });

      if (urls.isEmpty) {
        // fallback to filesystem scan if MediaStore returned no assets
        try {
          final pics = await _discoverPicturesFromFs();
          if (pics.isNotEmpty) {
            setState(() {
              _setImageUrls(pics);
            });
            return;
          }
        } catch (_) {}
      }
    } catch (e, stack) {
      developer.log('❌ Error loading device photos: $e');
      developer.log('Stack trace: $stack');
      setState(() {
        _setImageUrls([]);
      });
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
        const ThumbnailSize(
          256,
          256,
        ), // Reduced from 768 for better performance
        quality: 75,
      );
      if (bytes != null) _thumbCache[id] = bytes;
      return bytes;
    } catch (e) {
      developer.log('Failed to get thumbnail for $id: $e');
      return null;
    }
  }

  /// Get cached thumbnail future to prevent recreating on every rebuild
  Future<Uint8List?> _getCachedThumbFuture(String id) {
    return _thumbFutureCache.putIfAbsent(id, () => _getThumbForAsset(id));
  }

  /// Update cached filtered list when inputs change
  void _updateCachedFilteredList() {
    // Check if we need to recompute
    if (_lastSearchQuery == searchQuery &&
        _lastImageUrlsLength == imageUrls.length &&
        _lastPhotoTagsLength == photoTags.length &&
        _sortNewestFirstCached == _sortNewestFirst &&
        _cachedFilteredUrls.isNotEmpty) {
      return; // No changes, use cached version
    }

    // Recompute filtered list
    _cachedFilteredUrls = imageUrls.where((u) {
      final key = p.basename(u);
      final tags = photoTags[key] ?? [];
      final allDetections = photoAllDetections[key] ?? [];
      if (searchQuery.isEmpty) return true;

      if (searchQuery.trim().toLowerCase() == 'none') {
        return tags.isEmpty;
      }

      final searchTerms = searchQuery
          .split(' ')
          .where((term) => term.isNotEmpty)
          .map((term) => term.toLowerCase())
          .toList();

      return searchTerms.any(
        (searchTerm) =>
            tags.any((t) => t.toLowerCase().contains(searchTerm)) ||
            allDetections.any((d) => d.toLowerCase().contains(searchTerm)),
      );
    }).toList();

    // Sort the filtered list
    _cachedFilteredUrls.sort((a, b) {
      if (a.startsWith('local:') && b.startsWith('local:')) {
        final aId = a.substring('local:'.length);
        final bId = b.substring('local:'.length);
        final aAsset = _localAssets[aId];
        final bAsset = _localAssets[bId];
        if (aAsset != null && bAsset != null) {
          final aDate = aAsset.createDateTime;
          final bDate = bAsset.createDateTime;
          return _sortNewestFirst
              ? bDate.compareTo(aDate)
              : aDate.compareTo(bDate);
        }
      }
      return 0;
    });

    // Update cache keys
    _lastSearchQuery = searchQuery;
    _lastImageUrlsLength = imageUrls.length;
    _lastPhotoTagsLength = photoTags.length;
    _sortNewestFirstCached = _sortNewestFirst;
  }

  /// Update cached local photo count
  void _updateCachedLocalPhotoCount() {
    _cachedLocalPhotoCount = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .length;
  }

  /// Helper to set imageUrls and update related caches
  void _setImageUrls(List<String> urls) {
    imageUrls = urls;
    _updateCachedLocalPhotoCount();
    // Invalidate filtered cache so it rebuilds on next access
    _lastImageUrlsLength = -1;
  }

  Future<void> _loadTags() async {
    developer.log('📂 _loadTags called');
    // Batch load all tags at once for better performance
    final allPhotoIDs = imageUrls
        .map((url) => PhotoId.canonicalId(url))
        .toList();
    developer.log('📂 Total photos: ${allPhotoIDs.length}');

    final photoIDs = imageUrls
        .where((url) {
          final key = p.basename(url);
          // Skip if already have tags from server
          return !(photoTags.containsKey(key) &&
              (photoTags[key]?.isNotEmpty ?? false));
        })
        .map((url) => PhotoId.canonicalId(url))
        .toList();

    developer.log('📂 Photos needing tag load: ${photoIDs.length}');
    if (photoIDs.isEmpty) {
      developer.log('📂 No photos need tag loading, returning');
      return;
    }

    // Load all tags in a single batch operation
    final tagsMap = await TagStore.loadAllTagsMap(photoIDs);
    developer.log('📂 Loaded ${tagsMap.length} tags from storage');

    // Load all detections in a single batch operation
    final detectionsMap = await TagStore.loadAllDetectionsMap(photoIDs);
    developer.log('📂 Loaded ${detectionsMap.length} detections from storage');

    // Map back to basename keys
    int loaded = 0;
    for (final url in imageUrls) {
      final key = p.basename(url);
      final photoID = PhotoId.canonicalId(url);
      if (tagsMap.containsKey(photoID)) {
        photoTags[key] = tagsMap[photoID]!;
        loaded++;
      }
      if (detectionsMap.containsKey(photoID)) {
        photoAllDetections[key] = detectionsMap[photoID]!;
      }
    }
    developer.log('📂 Mapped $loaded tags to photoTags map');
    developer.log('📂 photoTags now has ${photoTags.length} entries');
  }

  /// Sync all tags from server database to local storage
  /// This ensures local cache matches server data
  Future<void> _syncTagsFromServer() async {
    developer.log('🔄 Starting tag sync from server...');
    try {
      final res = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/tags-db/'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final Map<String, dynamic> serverTags = json.decode(res.body);
        developer.log('📥 Downloaded ${serverTags.length} tags from server');

        // Convert to Map<String, List<String>> and save to local storage
        final tagsToSave = <String, List<String>>{};
        final detectionsToSave = <String, List<String>>{};
        for (final entry in serverTags.entries) {
          final photoID = entry.key;
          final tagData = entry.value;
          if (tagData is Map && tagData['tags'] is List) {
            final tags = (tagData['tags'] as List).cast<String>();
            if (tags.isNotEmpty) {
              tagsToSave[photoID] = tags;
            }
            // Also extract all_detections if available
            if (tagData['all_detections'] is List) {
              final detections = (tagData['all_detections'] as List)
                  .cast<String>();
              if (detections.isNotEmpty) {
                detectionsToSave[photoID] = detections;
              }
            }
          } else if (tagData is List) {
            final tags = tagData.cast<String>();
            if (tags.isNotEmpty) {
              tagsToSave[photoID] = tags;
            }
          }
        }

        // Save all tags and detections to local storage
        await TagStore.saveLocalTagsBatch(tagsToSave);
        if (detectionsToSave.isNotEmpty) {
          await TagStore.saveLocalDetectionsBatch(detectionsToSave);
        }
        developer.log('💾 Saved ${tagsToSave.length} tags to local storage');

        // Update in-memory photoTags and photoAllDetections
        for (final url in imageUrls) {
          final key = p.basename(url);
          final photoID = PhotoId.canonicalId(url);
          if (tagsToSave.containsKey(photoID)) {
            photoTags[key] = tagsToSave[photoID]!;
          }
          if (detectionsToSave.containsKey(photoID)) {
            photoAllDetections[key] = detectionsToSave[photoID]!;
          }
        }
        developer.log('📂 Updated photoTags with ${photoTags.length} entries');
        developer.log(
          '📂 Updated photoAllDetections with ${photoAllDetections.length} entries',
        );

        // Update scanned count
        _scannedCountNotifier.value = photoTags.length;
        _updateCachedFilteredList();
        if (mounted) setState(() {});
      } else {
        developer.log('⚠️ Failed to sync tags: ${res.statusCode}');
      }
    } catch (e) {
      developer.log('⚠️ Error syncing tags from server: $e');
    }
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
    _dotAnimationTimer?.cancel();
    _autoScanRetryTimer?.cancel();
    _progressRefreshTimer?.cancel();
    _dotIndexNotifier.dispose();
    _scanProgressNotifier.dispose();
    _scannedCountNotifier.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _showScrollToTop.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.offset >= 200 && !_showScrollToTop.value) {
      _showScrollToTop.value = true;
    } else if (_scrollController.offset < 200 && _showScrollToTop.value) {
      _showScrollToTop.value = false;
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
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
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 250,
                      height: 250,
                      child: Lottie.asset(
                        'assets/animations/fox-loading.json',
                        fit: BoxFit.contain,
                        repeat: true,
                        animate: true,
                        onLoaded: (composition) {
                          developer.log(
                            '✅ Lottie loaded: ${composition.duration}',
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading your photos...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
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
                        clipBehavior: Clip.none,
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
                          // Validation badge - next to tag toggle
                          // Only show blue badge when BOTH scanning and validation are complete
                          if (_validationComplete && !_validating && !_scanning)
                            Positioned(
                              right: 173,
                              top: 2,
                              child: GestureDetector(
                                onTap: () => _showBadgeTooltip(
                                  context,
                                  '✓ All ${photoTags.length} photos scanned',
                                  Colors.blue.shade700,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade600,
                                    shape: BoxShape.circle,
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
                                  child: const Icon(
                                    Icons.verified,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          // Show grey/orange badge when scanning or validation is in progress
                          if (!_validationComplete || _scanning || _validating)
                            Positioned(
                              right: 173,
                              top: 2,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      final pct = _cachedLocalPhotoCount > 0
                                          ? (photoTags.length /
                                                    _cachedLocalPhotoCount *
                                                    100)
                                                .toStringAsFixed(0)
                                          : '0';
                                      final status = _scanning
                                          ? 'Scanning ${photoTags.length}/$_cachedLocalPhotoCount ($pct%)'
                                          : _validating
                                          ? 'Validating...'
                                          : 'Waiting for server';
                                      _showBadgeTooltip(
                                        context,
                                        status,
                                        (_scanning || _validating)
                                            ? Colors.orange.shade700
                                            : Colors.grey.shade700,
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: (_scanning || _validating)
                                            ? Colors.orange.shade100.withValues(
                                                alpha: 0.3,
                                              )
                                            : Colors.grey.shade400.withValues(
                                                alpha: 0.3,
                                              ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: (_scanning || _validating)
                                              ? Colors.orange.shade600
                                              : Colors.grey.shade600,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.1,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.verified_outlined,
                                        color: (_scanning || _validating)
                                            ? Colors.orange.shade600
                                            : Colors.grey.shade600,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  if (_scanning || _validating)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: _buildLoadingDots(),
                                    ),
                                  // Show scan progress percentage during scanning
                                  if (_scanning && _scanTotal > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _scannedCountNotifier,
                                        builder: (context, scannedCount, _) {
                                          final pct = _cachedLocalPhotoCount > 0
                                              ? (scannedCount /
                                                        _cachedLocalPhotoCount *
                                                        100)
                                                    .toStringAsFixed(0)
                                              : '0';
                                          return Text(
                                            '$pct%',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.orange.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  // Show "Validating" text during validation
                                  if (_validating && !_scanning)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Validating',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          Positioned(
                            right: 120,
                            top: -3,
                            child: IconButton(
                              icon: Icon(
                                _showTags ? Icons.label_off : Icons.label,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                size: 22,
                              ),
                              tooltip: _showTags ? 'Hide tags' : 'Show tags',
                              onPressed: () =>
                                  setState(() => _showTags = !_showTags),
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
                              // Use cached filtered list for performance
                              _updateCachedFilteredList();
                              final filtered = _cachedFilteredUrls;

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
                                        // Refresh button
                                        IconButton(
                                          icon: Icon(
                                            Icons.refresh,
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black87,
                                            size: 24,
                                          ),
                                          onPressed: () async {
                                            await _loadAllImages();
                                          },
                                          tooltip: 'Refresh gallery',
                                        ),
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
                                    child: RefreshIndicator(
                                      onRefresh: () async {
                                        developer.log(
                                          '🔄 Pull-to-refresh triggered',
                                        );
                                        await _loadAllImages();
                                        developer.log('✅ Refresh complete');
                                      },
                                      child: GridView.builder(
                                        controller: _scrollController,
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
                                                              filePath:
                                                                  file.path,
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
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                                                                _getCachedThumbFuture(
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
                                                        : (url.startsWith(
                                                                'file:',
                                                              )
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
                                                                      File(
                                                                        path,
                                                                      ),
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
                                                                          color:
                                                                              Colors.black26,
                                                                          child: const Center(
                                                                            child: Icon(
                                                                              Icons.broken_image,
                                                                              color: Colors.white54,
                                                                              size: 36,
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
                                                          shape:
                                                              BoxShape.circle,
                                                          color: isSelected
                                                              ? Colors
                                                                    .blueAccent
                                                              : Colors.black54,
                                                        ),
                                                        padding:
                                                            const EdgeInsets.all(
                                                              6,
                                                            ),
                                                        child: Icon(
                                                          isSelected
                                                              ? Icons.check_box
                                                              : Icons
                                                                    .crop_square,
                                                          color: Colors.white,
                                                          size: 18,
                                                        ),
                                                      ),
                                                    ),
                                                  if (_showTags)
                                                    Positioned(
                                                      left: 8,
                                                      right: 8,
                                                      bottom: 8,
                                                      child: LayoutBuilder(
                                                        builder: (context, constraints) {
                                                          final chips =
                                                              _buildTagChipsForWidth(
                                                                visibleTags,
                                                                fullTags,
                                                                constraints
                                                                    .maxWidth,
                                                              );

                                                          // Check if this photo was recently validated (within last 10 seconds)
                                                          final photoID =
                                                              PhotoId.canonicalId(
                                                                url,
                                                              );
                                                          final recentlyValidated =
                                                              _recentlyValidated
                                                                  .containsKey(
                                                                    photoID,
                                                                  ) &&
                                                              DateTime.now()
                                                                      .difference(
                                                                        _recentlyValidated[photoID]!,
                                                                      )
                                                                      .inSeconds <
                                                                  10;

                                                          return Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Expanded(
                                                                child: AnimatedOpacity(
                                                                  opacity: 1.0,
                                                                  duration:
                                                                      const Duration(
                                                                        milliseconds:
                                                                            300,
                                                                      ),
                                                                  child: Wrap(
                                                                    spacing: 4,
                                                                    children:
                                                                        chips,
                                                                  ),
                                                                ),
                                                              ),
                                                              if (recentlyValidated)
                                                                Padding(
                                                                  padding:
                                                                      const EdgeInsets.only(
                                                                        left: 4,
                                                                      ),
                                                                  child: Container(
                                                                    padding:
                                                                        const EdgeInsets.all(
                                                                          4,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .green
                                                                          .withValues(
                                                                            alpha:
                                                                                0.9,
                                                                          ),
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      boxShadow: [
                                                                        BoxShadow(
                                                                          color: Colors.black.withValues(
                                                                            alpha:
                                                                                0.3,
                                                                          ),
                                                                          offset: const Offset(
                                                                            0,
                                                                            0.5,
                                                                          ),
                                                                          blurRadius:
                                                                              2,
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    child: const Icon(
                                                                      Icons
                                                                          .auto_awesome,
                                                                      size: 14,
                                                                      color: Colors
                                                                          .white,
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
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
                                                    // Clear server tags first
                                                    try {
                                                      await http
                                                          .delete(
                                                            Uri.parse(
                                                              '${ApiService.baseUrl}/tags-db/',
                                                            ),
                                                            headers: {
                                                              'Content-Type':
                                                                  'application/json',
                                                            },
                                                          )
                                                          .timeout(
                                                            const Duration(
                                                              seconds: 10,
                                                            ),
                                                          );
                                                      developer.log(
                                                        '🗑️ Cleared server tags database',
                                                      );
                                                    } catch (e) {
                                                      developer.log(
                                                        '⚠️ Failed to clear server tags: $e',
                                                      );
                                                    }

                                                    // Clear all local tags at once (much faster)
                                                    final removed =
                                                        await TagStore.clearAllTags();

                                                    // Clear in-memory tags
                                                    photoTags.clear();

                                                    // Reset validation state to allow re-scan
                                                    _validationComplete = false;
                                                    _scannedCountNotifier
                                                            .value =
                                                        0;

                                                    // Update UI
                                                    if (mounted) {
                                                      setState(() {});
                                                    }

                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        // ignore: use_build_context_synchronously
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Removed $removed local + server tags',
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

                        // Scroll to top button
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 105,
                          child: Center(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _showScrollToTop,
                              builder: (context, show, child) {
                                return AnimatedScale(
                                  scale: show ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  child: AnimatedOpacity(
                                    opacity: show ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    child: IgnorePointer(
                                      ignoring: !show,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _scrollToTop,
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                          child: Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              color: Colors.lightBlue.shade300,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.2),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.arrow_upward,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
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
