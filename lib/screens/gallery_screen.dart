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
import '../services/trash_store.dart';
import '../services/api_service.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'album_screen.dart';
import 'photo_viewer.dart';
import 'intro_video_screen.dart';
import 'onboarding_screen.dart';

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
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<String> imageUrls = [];
  Map<String, List<String>> photoTags = {};
  Map<String, List<String>> photoAllDetections = {};
  bool loading = true;
  final Map<String, AssetEntity> _localAssets = {};
  final Map<String, Uint8List> _thumbCache = {};
  Map<String, List<String>> albums = {};
  String searchQuery = '';
  bool showDebug = false;
  bool _showSearchBar = true;
  bool _showTags = true;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  int _crossAxisCount = 4;
  bool _isSelectMode = false;
  final Set<String> _selectedKeys = {};
  final Map<String, double> _textWidthCache = {};
  bool _scanning = false;
  bool _clearingTags = false;
  bool _hasScannedAtLeastOneBatch = false;
  bool _validating = false;
  bool _validationComplete = false;
  final Map<String, DateTime> _recentlyValidated = {};
  double _scanProgress = 0.0;
  int _scanTotal = 0;
  int _scanProcessed = 0;
  double _lastScale = 1.0;
  List<String> _cachedFilteredUrls = [];
  String _lastSearchQuery = '';
  int _lastPhotoTagsLength = 0;
  int _lastImageUrlsLength = 0;
  final ValueNotifier<int> _scannedCountNotifier = ValueNotifier<int>(0);
  int _cachedLocalPhotoCount = 0;
  DateTime? _reached100At;
  bool _galleryReadyShown = false;
  final ValueNotifier<bool> _showScrollToTop = ValueNotifier<bool>(false);
  final ScrollController _scrollController = ScrollController();
  Timer? _fastScrollerHideTimer;
  ValueNotifier<bool> _showFastScrollerNotifier = ValueNotifier<bool>(false);
  bool _isDraggingScroller = false;
  Timer? _autoScanRetryTimer;
  bool _showPerformanceMonitor = false;
  double _currentRamUsageMB = 0.0;
  double _peakRamUsageMB = 0.0;
  int _currentBatchSize = 20;
  double _avgBatchTimeMs = 0.0;
  double _imagesPerSecond = 0.0;
  late AnimationController _starAnimationController;
  late Animation<double> _starRotation;
  StreamSubscription<dynamic>? _photoChangesSubscription;
  static const _photoChangesChannel = EventChannel(
    'com.example.photo_organizer/photo_changes',
  );

  // Additional state variables
  final ValueNotifier<int> _dotIndexNotifier = ValueNotifier<int>(0);
  Timer? _dotAnimationTimer;
  final Map<String, Future<Uint8List?>> _thumbFutureCache = {};
  bool _sortNewestFirstCached = true;
  bool _sortNewestFirst = true;
  Timer? _progressRefreshTimer;
  Timer? _smoothProgressTimer;
  Timer? _longPressTimer;
  final ValueNotifier<double> _scanProgressNotifier = ValueNotifier<double>(
    0.0,
  );
  bool _validationCancelled = false;
  double _estimatedMsPerPhoto = 100.0;
  double _targetProgress = 0.0;
  double _displayProgress = 0.0;
  bool _validationPaused = false;
  int _validationTotal = 0;
  int _validationAgreements = 0;
  int _validationDisagreements = 0;
  int _validationOverrides = 0;
  List<Map<String, dynamic>> _validationChanges = [];
  String _currentScrollYear = '';
  bool _scanPaused = false;

  void _showSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 48, left: 16, right: 16),
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  double _measureTextWidth(String text, TextStyle style) {
    final key = text;
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: Colors.lightBlue.shade300, size: 14),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
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

    // Initialize star animation for "final touches" display
    _starAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // Twice as slow
    )..repeat();
    _starRotation = Tween<double>(begin: 0, end: 2 * 3.14159).animate(
      CurvedAnimation(parent: _starAnimationController, curve: Curves.linear),
    );

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

    // Listen to native photo changes instead of polling
    _photoChangesSubscription = _photoChangesChannel
        .receiveBroadcastStream()
        .listen((event) async {
          developer.log('📸 Photo library changed (native event)');
          // Only check if not actively scanning to avoid conflicts
          if (!_scanning && !_validating) {
            await _checkForGalleryChanges();
          }
        });
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

  /// Build a list of PhotoData for all filtered photos (for swipe navigation)
  /// This is instant - no file loading happens here, only URL references
  List<PhotoData> _buildPhotoDataList(List<String> filtered) {
    final List<PhotoData> photos = [];

    for (final url in filtered) {
      final key = p.basename(url);
      final tags = photoTags[key] ?? [];
      final detections = photoAllDetections[key] ?? [];

      AssetEntity? asset;
      if (url.startsWith('local:')) {
        final id = url.substring('local:'.length);
        asset = _localAssets[id];
      }

      photos.add(
        PhotoData(
          url: url,
          heroTag: key,
          tags: tags,
          allDetections: detections,
          asset: asset,
        ),
      );
    }

    return photos;
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
    // Don't sync during tag clearing - the server DB was just wiped
    if (_clearingTags) return;

    ApiService.pingServer(timeout: const Duration(seconds: 2)).then((online) {
      if (online && mounted && !_clearingTags) {
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
      // Only retry if not already scanning/validating and not complete, and not clearing tags
      if (!_scanning &&
          !_validating &&
          !_validationComplete &&
          !_clearingTags &&
          mounted) {
        developer.log(
          '🔄 Auto-retry: Checking if scan is needed (silent, no reload)...',
        );
        // Just check if scan is needed - don't reload images (causes loading animation)
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

  /// Start a timer that smoothly animates progress between batch updates
  void _startProgressRefreshTimer() {
    _progressRefreshTimer?.cancel();
    _smoothProgressTimer?.cancel();

    // Smooth progress animation - ticks every 500ms
    _smoothProgressTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (!mounted || (!_scanning && !_validating)) {
        timer.cancel();
        _smoothProgressTimer = null;
        return;
      }

      // Smoothly animate towards target progress
      if (_displayProgress < _targetProgress) {
        // Calculate increment based on estimated speed
        // If we estimate 300ms/photo and tick every 500ms, we process ~1.67 photos/tick
        final photosPerTick = 500.0 / _estimatedMsPerPhoto;
        final incrementPerTick = _scanTotal > 0
            ? photosPerTick / _scanTotal
            : 0.01;

        // Increment but cap at 95% of target (never exceed actual progress)
        final maxDisplay = _targetProgress * 0.95;
        _displayProgress = (_displayProgress + incrementPerTick).clamp(
          0.0,
          maxDisplay,
        );
        _scanProgressNotifier.value = _displayProgress;
      }
    });

    // NOTE: Removed 2-second setState timer - it was rebuilding the entire
    // 3000+ photo grid every 2 seconds during scan, causing major lag.
    // All important UI elements (progress bar, dots, count) already use
    // ValueListenableBuilder and update independently.
  }

  /// Show a small tooltip-like popup near the badge
  OverlayEntry? _badgeTooltipEntry;
  Timer? _tooltipTimer;

  void _dismissTooltip() {
    _tooltipTimer?.cancel();
    _badgeTooltipEntry?.remove();
    _badgeTooltipEntry = null;
  }

  void _showBadgeTooltip(BuildContext context, String message, Color color) {
    _dismissTooltip();
    final overlay = Overlay.of(context);
    _badgeTooltipEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 64, // 4px rule
        right: 208, // 4px rule
        child: FractionalTranslation(
          translation: const Offset(0.5, 0),
          child: GestureDetector(
            onTap: _dismissTooltip, // Tap on tooltip itself to dismiss
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ), // 4px rule
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8), // 4px rule
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8, // 4px rule
                      offset: const Offset(0, 4), // 4px rule
                    ),
                  ],
                ),
                // Use ValueListenableBuilder for live progress updates
                child: ValueListenableBuilder<int>(
                  valueListenable: _scannedCountNotifier,
                  builder: (context, scannedCount, _) {
                    final pct = _cachedLocalPhotoCount > 0
                        ? (scannedCount / _cachedLocalPhotoCount * 100)
                              .toStringAsFixed(0)
                        : '0';

                    // Track when we reach 100%
                    final isAt100 =
                        scannedCount >= _cachedLocalPhotoCount &&
                        _cachedLocalPhotoCount > 0;
                    if (isAt100 && _reached100At == null) {
                      _reached100At = DateTime.now();
                    } else if (!isAt100) {
                      _reached100At = null;
                    }

                    // Show "Final touches" if stuck at 100% for more than 3 seconds
                    final stuckAt100 =
                        _reached100At != null &&
                        DateTime.now().difference(_reached100At!).inSeconds > 3;

                    String liveMessage;
                    Widget? icon;

                    if (_scanning && stuckAt100) {
                      liveMessage = 'Final touches';
                      icon = AnimatedBuilder(
                        animation: _starRotation,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _starRotation.value,
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Colors.yellow,
                                  Colors.orange,
                                  Colors.pink,
                                  Colors.purple,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: const Icon(
                                Icons.star,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          );
                        },
                      );
                    } else if (_scanning) {
                      liveMessage =
                          'Scanning $scannedCount/$_cachedLocalPhotoCount ($pct%)';
                    } else if (_validationComplete) {
                      liveMessage = '✓ All $scannedCount photos scanned';
                    } else {
                      liveMessage = message;
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[icon, const SizedBox(width: 6)],
                        Text(
                          liveMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (icon != null) ...[const SizedBox(width: 6), icon],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_badgeTooltipEntry!);
    // Auto-dismiss after 10 seconds
    _tooltipTimer = Timer(const Duration(seconds: 3), _dismissTooltip);
  }

  /// Sort photos for optimal scan order: alternate between newest and oldest batches
  /// This prioritizes both ends of the gallery (most browsed) and leaves middle for last
  List<String> _sortForOptimalScanOrder(List<String> urls) {
    if (urls.length <= 2) return urls;

    // Sort by date first (newest first)
    final sorted = List<String>.from(urls);
    sorted.sort((a, b) {
      if (a.startsWith('local:') && b.startsWith('local:')) {
        final aId = a.substring('local:'.length);
        final bId = b.substring('local:'.length);
        final aAsset = _localAssets[aId];
        final bAsset = _localAssets[bId];
        if (aAsset != null && bAsset != null) {
          return bAsset.createDateTime.compareTo(aAsset.createDateTime);
        }
      }
      return 0;
    });

    // Interleave batches: 75 from front (newest), 75 from back (oldest), repeat
    const batchSize = 75;
    final result = <String>[];
    int frontIdx = 0;
    int backIdx = sorted.length - 1;
    bool takeFront = true;

    while (frontIdx <= backIdx) {
      if (takeFront) {
        // Take up to 75 from front (newest)
        final endIdx = (frontIdx + batchSize - 1).clamp(frontIdx, backIdx);
        for (int i = frontIdx; i <= endIdx; i++) {
          result.add(sorted[i]);
        }
        frontIdx = endIdx + 1;
      } else {
        // Take up to 75 from back (oldest)
        final startIdx = (backIdx - batchSize + 1).clamp(frontIdx, backIdx);
        for (int i = backIdx; i >= startIdx; i--) {
          result.add(sorted[i]);
        }
        backIdx = startIdx - 1;
      }
      takeFront = !takeFront;
    }

    developer.log(
      '📅 Optimized scan order: 75 newest → 75 oldest → repeat, middle last',
    );
    return result;
  }

  /// Get year from a photo URL for fast scroller
  int? _getYearForPhoto(String url) {
    if (url.startsWith('local:')) {
      final id = url.substring('local:'.length);
      final asset = _localAssets[id];
      if (asset != null) {
        return asset.createDateTime.year;
      }
    }
    return null;
  }

  /// Build year markers for the fast scroller based on current filtered list
  List<MapEntry<double, int>> _buildYearMarkers(List<String> filtered) {
    if (filtered.isEmpty) return [];

    final markers = <MapEntry<double, int>>[];
    int? lastYear;

    for (int i = 0; i < filtered.length; i++) {
      final year = _getYearForPhoto(filtered[i]);
      if (year != null && year != lastYear) {
        // Position as fraction of total list
        final position = i / filtered.length;
        markers.add(MapEntry(position, year));
        lastYear = year;
      }
    }

    return markers;
  }

  /// Scroll to position based on scroller drag
  void _scrollToPosition(double fraction, List<String> filtered) {
    if (_scrollController.hasClients && filtered.isNotEmpty) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final targetOffset = (fraction * maxExtent).clamp(0.0, maxExtent);
      _scrollController.jumpTo(targetOffset);

      // Update current year display (only if changed to avoid unnecessary rebuilds)
      final index = (fraction * filtered.length)
          .clamp(0, filtered.length - 1)
          .toInt();
      if (index < filtered.length) {
        final year = _getYearForPhoto(filtered[index]);
        if (year != null) {
          final newYearStr = "'${year.toString().substring(2)}";
          if (_currentScrollYear != newYearStr) {
            setState(() {
              _currentScrollYear = newYearStr;
            });
          }
        }
      }
    }
  }

  /// Get current scroll position as fraction
  double _getCurrentScrollFraction() {
    if (!_scrollController.hasClients) return 0.0;
    try {
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return 0.0;
      return (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  /// Build the fast scroller widget
  Widget _buildFastScroller(List<String> filtered, double height) {
    final scrollerHeight = height - 140; // Account for bottom offset

    return ValueListenableBuilder<bool>(
      valueListenable: _showFastScrollerNotifier,
      builder: (context, showScroller, child) {
        return AnimatedBuilder(
          animation: _scrollController,
          builder: (context, child) {
            final yearMarkers = _buildYearMarkers(filtered);
            final scrollFraction = _getCurrentScrollFraction();

            return Positioned(
              right: 4,
              top: 0,
              bottom: 140, // End above floating buttons
              child: AnimatedOpacity(
                opacity: showScroller ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !showScroller,
                  child: GestureDetector(
                    onVerticalDragStart: (details) {
                      _isDraggingScroller = true;
                      final fraction =
                          details.localPosition.dy / scrollerHeight;
                      _scrollToPosition(fraction.clamp(0.0, 1.0), filtered);
                    },
                    onVerticalDragUpdate: (details) {
                      final fraction =
                          details.localPosition.dy / scrollerHeight;
                      _scrollToPosition(fraction.clamp(0.0, 1.0), filtered);
                    },
                    onVerticalDragEnd: (details) {
                      _isDraggingScroller = false;
                      setState(() {
                        _currentScrollYear = '';
                      });
                      // Hide after 2 seconds
                      _fastScrollerHideTimer?.cancel();
                      _fastScrollerHideTimer = Timer(
                        const Duration(seconds: 2),
                        () {
                          if (mounted && !_isDraggingScroller) {
                            _showFastScrollerNotifier.value = false;
                          }
                        },
                      );
                    },
                    child: Container(
                      width: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Stack(
                        children: [
                          // Year markers
                          ...yearMarkers.map(
                            (marker) => Positioned(
                              top: marker.key * scrollerHeight,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Text(
                                  "'${marker.value.toString().substring(2)}",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Scroll indicator thumb
                          Positioned(
                            top: scrollFraction * (scrollerHeight - 24),
                            left: 2,
                            right: 2,
                            child: Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _currentScrollYear.isNotEmpty
                                    ? Text(
                                        _currentScrollYear,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : Container(
                                        width: 8,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade400,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
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
            );
          },
        );
      },
    );
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
    if (_clearingTags) {
      developer.log('⏸️ Tag clearing in progress, blocking scan');
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
        '⚠️ Server not available at ${ApiService.baseUrl}, skipping auto-scan (will retry automatically)',
      );
      // Silent - auto-retry timer will check again in 30 seconds
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

      // Double-check: verify that photoTags actually has entries for all/most photos
      // This prevents validation from starting if tags were just cleared
      final scannedCount = photoTags.length;
      if (scannedCount == 0 || scannedCount < localUrls.length * 0.9) {
        developer.log(
          '⚠️ Tags not fully loaded yet (have $scannedCount, need ~${localUrls.length}). NOT starting validation.',
        );
        // Don't try to validate - just return and let the scan happen first
        return;
      }

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
          // Only validate if we've actually scanned photos
          if (!_hasScannedAtLeastOneBatch) {
            developer.log(
              '⚠️ Found YOLO photos but no batches scanned yet - NOT validating',
            );
            return;
          }
          developer.log(
            '📸 Found YOLO-classified photos. Starting validation...',
          );
          _validateAllClassifications();
        } else if (_hasScannedAtLeastOneBatch) {
          developer.log(
            '✅ No YOLO-classified photos found. Marking validation as complete.',
          );
          setState(() {
            _validationComplete = true;
          });
        } else {
          developer.log(
            '⚠️ No YOLO photos but also no batches scanned - NOT marking complete',
          );
        }
      } else {
        developer.log(
          '✅ Validation already complete or in progress. Nothing to do.',
        );
      }
      return;
    }

    // Sort photos by date and interleave newest/oldest for better UX
    // Users typically browse recent photos or very old ones, middle is least viewed
    final toScan = _sortForOptimalScanOrder(missing);
    developer.log('🚀 Starting scan of ${toScan.length} photos...');

    // Reset the 'gallery ready' flag so message shows again after this scan
    _galleryReadyShown = false;

    // Update cached local photo count for accurate progress display
    _cachedLocalPhotoCount = localUrls.length;

    setState(() {
      _scanning = true;
      _scanTotal = toScan.length;
      developer.log(
        '📊 SET _scanTotal = $_scanTotal, _cachedLocalPhotoCount = $_cachedLocalPhotoCount',
      );
      // Don't reset _scanPaused - let user control pause/resume
      _scanProcessed = 0;
      _scanProgress = 0.0;
      // Reset smooth progress animation
      _displayProgress = 0.0;
      _targetProgress = 0.0;
    });
    // Initialize scanned count notifier with current count
    _scannedCountNotifier.value = photoTags.length;
    // Start progress refresh timer (updates UI every 5 seconds)
    _startProgressRefreshTimer();

    await _scanImages(toScan);

    // Stop progress refresh timer
    _progressRefreshTimer?.cancel();
    _progressRefreshTimer = null;
    _smoothProgressTimer?.cancel();
    _smoothProgressTimer = null;

    setState(() {
      _scanning = false;
      _scanProgress = 0.0;
      _scanTotal = 0;
    });

    // Cancel dot animation if validation is also complete
    if (!_validating) {
      _dotAnimationTimer?.cancel();
      _dotAnimationTimer = null;
      // Show combined completion message if validation is already done AND we scanned something
      if (_validationComplete && _hasScannedAtLeastOneBatch) {
        _showGalleryReadyMessage();
      }
    }
  }

  // Manual scan helper restored: scans missing images by default,
  // or force-rescans all device images when `force` is true.
  Future<void> _manualScan({bool force = false}) async {
    developer.log(
      '🔧 _manualScan called with force=$force, _scanning=$_scanning, _clearingTags=$_clearingTags',
    );
    // Allow force scan even if _scanning is true (for post-clear recovery)
    // but block if actually scanning (has scanTotal > 0)
    if (_scanning && _scanTotal > 0) {
      developer.log('⏸️ Already actively scanning, blocking manual scan');
      return;
    }
    // Allow force=true to bypass _clearingTags check (post-clear rescan needs this)
    if (_clearingTags && !force) {
      developer.log('⏸️ Tag clearing in progress, blocking manual scan');
      return;
    }

    // Check server connectivity first
    final serverAvailable = await ApiService.pingServer(
      timeout: const Duration(seconds: 3),
      retries: 1,
    );
    if (!serverAvailable) {
      developer.log('⚠️ Server offline, manual scan aborted (silent)');
      // Silent - auto-retry timer will check again
      return;
    }

    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();
    developer.log(
      '🔧 _manualScan: Found ${localUrls.length} local photos (imageUrls.length=${imageUrls.length})',
    );
    if (localUrls.isEmpty) {
      developer.log('⚠️ _manualScan: No local photos found, returning');
      return;
    }

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
      _showSnackBar('No images to scan');
      return;
    }

    // Reset gallery ready flag so message shows again after scan
    _galleryReadyShown = false;

    // Update cached local photo count for accurate progress display
    _cachedLocalPhotoCount = localUrls.length;

    setState(() {
      _scanning = true;
      _scanTotal = toScan.length;
      _validationComplete = false; // Reset validation since we're rescanning
      developer.log(
        '📊 SET _scanTotal = $_scanTotal, _cachedLocalPhotoCount = $_cachedLocalPhotoCount',
      );
      // Don't reset _scanPaused - let user control pause/resume
      _scanProcessed = 0;
      _scanProgress = 0.0;
      // Reset smooth progress animation
      _displayProgress = 0.0;
      _targetProgress = 0.0;
    });
    // Initialize scanned count notifier with current count
    _scannedCountNotifier.value = photoTags.length;
    // Start progress refresh timer (updates UI every 5 seconds)
    _startProgressRefreshTimer();

    await _scanImages(toScan);

    // Stop progress refresh timer
    _progressRefreshTimer?.cancel();
    _progressRefreshTimer = null;
    _smoothProgressTimer?.cancel();
    _smoothProgressTimer = null;

    // Note: Skip _syncTagsFromServer() and _loadTags() here - we already have
    // all tags in memory from the batch processing loop. Re-downloading from
    // server and re-reading from storage is redundant and slow.
    developer.log(
      '✅ Scan complete - tags already in memory, skipping redundant sync/load',
    );

    setState(() {
      _scanning = false;
      _scanProgress = 0.0;
      _scanTotal = 0;
      _scanProcessed = 0;
    });

    // After scan completes, mark as validation complete (YOLO-only scan doesn't need CLIP validation)
    // BUT only if we actually scanned photos - don't complete if scan failed/aborted
    if (mounted && !_validationComplete && _hasScannedAtLeastOneBatch) {
      developer.log(
        '✅ Manual scan complete with ${photoTags.length} tags, marking validation complete',
      );
      setState(() {
        _validationComplete = true;
      });
      _showGalleryReadyMessage();
    } else if (mounted && !_hasScannedAtLeastOneBatch) {
      developer.log(
        '⚠️ Manual scan ended but no batches were processed - NOT marking complete',
      );
    }
  }

  /// Validate all previously classified images with CLIP
  Future<void> _validateAllClassifications() async {
    developer.log('🔍 _validateAllClassifications called');
    developer.log(
      '   _scanning=$_scanning, _validating=$_validating, _clearingTags=$_clearingTags',
    );
    developer.log('   photoTags.length=${photoTags.length}');

    if (_scanning || _validating) {
      developer.log('⚠️ Already scanning or validating, returning');
      return;
    }

    if (_clearingTags) {
      developer.log('⏸️ Tag clearing in progress, blocking validation');
      return;
    }

    // CRITICAL: Never validate if no batch has been scanned yet
    if (!_hasScannedAtLeastOneBatch) {
      developer.log(
        '⏸️ No batch scanned yet. Validation blocked until scanning completes at least one batch.',
      );
      return;
    }

    // CRITICAL: Never start validation if we have no/few tags
    // This prevents validation from starting before scanning
    final localCount = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .length;
    if (photoTags.length < localCount * 0.9) {
      developer.log(
        '⏸️ Not enough photos scanned yet (${photoTags.length}/$localCount). Blocking validation.',
      );
      return;
    }

    // Show loading indicator immediately
    setState(() {
      _validating = true;
      _validationComplete = false;
      _validationTotal = 0;
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
      // Silent - settings indicator shows server status
      developer.log('⚠️ Server offline, rescan aborted silently');
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

    developer.log(
      '📸 Found ${urlsToValidate.length} photos needing validation',
    );

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
      _showSnackBar(
        'No YOLO-classified images found to validate.\nOnly people/animals/food photos can be validated.',
        duration: const Duration(seconds: 4),
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
    final yoloClassifiedImages = <Map<String, dynamic>>[];

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

      // Check if scan was stopped or tags are being cleared
      if (!_scanning || _clearingTags) {
        developer.log(
          '⏹️ Scan stopped (scanning=$_scanning, clearingTags=$_clearingTags)',
        );
        await Future.wait(activeBatches.map((c) => c.future));
        return;
      }

      // Check for pause
      while (_scanPaused) {
        if (!mounted || !_scanning || _clearingTags) {
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
            // Note: Streaming validation is disabled (enableStreamingValidation = false)
            // Validation only runs after all photos are scanned
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
      // Use thumbnails (1024px) for large images, original for small ones
      final fileLoadFutures = batch.map((u) async {
        Uint8List? imageBytes;
        if (u.startsWith('local:')) {
          final id = u.substring('local:'.length);
          final asset = _localAssets[id];
          if (asset != null) {
            // Check if image is already small - if so, use original to preserve quality
            final width = asset.width;
            final height = asset.height;
            final maxDimension = width > height ? width : height;

            if (maxDimension <= 1024) {
              // Small image - use original bytes to preserve quality
              imageBytes = await asset.originBytes;
            } else {
              // Large image - use 1024px thumbnail for speed
              // CLIP uses 224x224 internally, so 1024px is plenty
              imageBytes = await asset.thumbnailDataWithSize(
                const ThumbnailSize(1024, 1024),
                quality: 85,
              );
            }
          }
        } else if (u.startsWith('file:')) {
          final path = u.substring('file:'.length);
          final file = File(path);
          if (await file.exists()) {
            imageBytes = await file.readAsBytes();
          }
        }

        if (imageBytes != null && imageBytes.isNotEmpty) {
          final photoID = PhotoId.canonicalId(u);
          return {'file': imageBytes, 'photoID': photoID, 'url': u};
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
              developer.log(
                '📊 Updated _scannedCountNotifier to ${photoTags.length}',
              );

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

            // Mark that at least one batch was scanned (enables validation)
            _hasScannedAtLeastOneBatch = true;

            // Trigger UI refresh to show new tags on photos
            if (mounted) {
              developer.log('🔄 Triggering setState after batch save');
              // Also invalidate filter cache so tags appear on grid
              _lastPhotoTagsLength = -1;
              setState(() {});
            }
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

      // Update adaptive timing estimate (exponential moving average)
      if (batchUrls.isNotEmpty) {
        final actualMsPerPhoto = batchDuration / batchUrls.length;
        _estimatedMsPerPhoto =
            (_estimatedMsPerPhoto * 0.7) + (actualMsPerPhoto * 0.3);
        developer.log(
          '📈 Updated timing estimate: ${_estimatedMsPerPhoto.toStringAsFixed(0)}ms/photo',
        );
      }

      setState(() {
        // Set actual progress and snap display to it
        _scanProcessed = (batchStart + batchUrls.length).clamp(0, _scanTotal);
        _scanProgress = (_scanTotal == 0)
            ? 0.0
            : (_scanProcessed / _scanTotal).clamp(0.0, 1.0);

        // Update target for smooth animation, snap display to actual
        _targetProgress = _scanProgress;
        _displayProgress =
            _scanProgress; // Snap to real value on batch complete
        _scanProgressNotifier.value = _displayProgress;

        developer.log('📊 PROGRESS UPDATE: $_scanProcessed / $_scanTotal');
        _avgBatchTimeMs = batchDuration.toDouble();
        _imagesPerSecond = elapsedSeconds > 0
            ? _scanProcessed / elapsedSeconds.toDouble()
            : 0;
      });
    }
  }

  /// Start streaming validation - validates images as they're scanned (parallel processing)
  /// This allows scan and validation to overlap without overwhelming the device
  // ignore: unused_element
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
          // Only mark complete if scanning is also done AND we actually scanned something
          if (!_scanning && _hasScannedAtLeastOneBatch) {
            _validationComplete = true;
          }
        });

        // Cancel dot animation if scanning is also complete
        if (!_scanning && _hasScannedAtLeastOneBatch) {
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
        setState(() {});
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
          // Only mark complete if scanning is also done AND we actually scanned something
          if (!_scanning && _hasScannedAtLeastOneBatch) {
            _validationComplete = true;
          }
        });
        // Cancel dot animation if scanning is also complete
        if (!_scanning && _hasScannedAtLeastOneBatch) {
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
    // Only show once per scan cycle
    if (_galleryReadyShown) {
      developer.log('⏭️ Gallery ready message already shown, skipping');
      return;
    }
    _galleryReadyShown = true;
    final totalPhotos = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .length;
    _showSnackBar(
      '✅ Gallery ready: $totalPhotos photos scanned & verified',
      duration: const Duration(seconds: 3),
    );
  }

  // ignore: unused_element
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

  // ignore: unused_element
  Widget _buildChangeItem(Map<String, dynamic> change) {
    final url = change['url'] as String;
    final oldTags = change['oldTags'] as List<String>;
    final newTags = change['newTags'] as List<String>;
    final reason = change['reason'] as String;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        // onTap: () => _showChangeDetails(change),
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

  // ignore: unused_element
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

  /// Check for new or deleted photos and update incrementally (no full reload)
  Future<void> _checkForGalleryChanges() async {
    try {
      // Get current device photos without clearing existing data
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth && perm != PermissionState.limited) {
        return; // No permission, skip check
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        onlyAll: false,
      );

      if (albums.isEmpty) return;

      // Collect all current device photos
      final currentDeviceIds = <String>{};
      for (final album in albums) {
        final count = await album.assetCountAsync;
        if (count > 0) {
          final assets = await album.getAssetListRange(start: 0, end: count);
          for (final asset in assets) {
            currentDeviceIds.add(asset.id);
            // Update _localAssets with any new photos
            if (!_localAssets.containsKey(asset.id)) {
              _localAssets[asset.id] = asset;
            }
          }
        }
      }

      // Check for changes
      final oldUrls = imageUrls.where((u) => u.startsWith('local:')).toSet();
      final oldIds = oldUrls.map((u) => u.substring('local:'.length)).toSet();

      // Find new photos (on device but not in our list)
      final newIds = currentDeviceIds.difference(oldIds);

      // Find deleted photos (in our list but not on device)
      final deletedIds = oldIds.difference(currentDeviceIds);

      if (newIds.isEmpty && deletedIds.isEmpty) {
        return; // No changes
      }

      developer.log('📸 Gallery changes detected:');
      developer.log('  + ${newIds.length} new photos');
      developer.log('  - ${deletedIds.length} deleted photos');

      // Add new photos
      for (final id in newIds) {
        imageUrls.add('local:$id');
      }

      // Remove deleted photos
      if (deletedIds.isNotEmpty) {
        imageUrls.removeWhere((url) {
          if (url.startsWith('local:')) {
            final id = url.substring('local:'.length);
            return deletedIds.contains(id);
          }
          return false;
        });

        // Clean up associated data
        for (final id in deletedIds) {
          _localAssets.remove(id);
          _thumbCache.remove(id);
          final key = 'local:$id';
          photoTags.remove(key);
          photoAllDetections.remove(key);
        }
      }

      // Update cached count and trigger UI refresh
      _updateCachedLocalPhotoCount();
      _lastImageUrlsLength = -1; // Invalidate filtered cache

      if (mounted) {
        setState(() {});
        developer.log(
          '✅ Gallery updated incrementally: ${imageUrls.length} total photos',
        );

        // Immediately trigger scan for new photos (don't wait for 30s timer)
        if (newIds.isNotEmpty) {
          developer.log(
            '🚀 Auto-triggering scan for ${newIds.length} new photos',
          );
          _startAutoScanIfNeeded();
        }
      }
    } catch (e) {
      developer.log('⚠️ Error checking gallery changes: $e');
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
    developer.log('📂 photoTags BEFORE load has ${photoTags.length} entries');

    // Batch load all tags at once for better performance
    final allPhotoIDs = imageUrls
        .map((url) => PhotoId.canonicalId(url))
        .toList();
    developer.log('📂 Total photos: ${allPhotoIDs.length}');

    final photoIDs = imageUrls
        .where((url) {
          final key = p.basename(url);
          // Skip if already have tags from server
          final skip =
              photoTags.containsKey(key) &&
              (photoTags[key]?.isNotEmpty ?? false);
          if (skip) {
            developer.log(
              '📂 Skipping $key - already has ${photoTags[key]?.length ?? 0} tags',
            );
          }
          return !skip;
        })
        .map((url) => PhotoId.canonicalId(url))
        .toList();

    developer.log('📂 Photos needing tag load: ${photoIDs.length}');
    if (photoIDs.isEmpty) {
      developer.log('📂 No photos need tag loading, returning early');
      developer.log('📂 photoTags FINAL has ${photoTags.length} entries');
      return;
    }

    // Load all tags in a single batch operation
    developer.log(
      '📂 Calling TagStore.loadAllTagsMap with ${photoIDs.length} IDs...',
    );
    final tagsMap = await TagStore.loadAllTagsMap(photoIDs);
    developer.log('📂 TagStore returned ${tagsMap.length} tags from storage');

    // Log first few tags for debugging
    int logged = 0;
    for (final entry in tagsMap.entries) {
      if (logged++ < 3) {
        developer.log('📂   Sample: ${entry.key} = ${entry.value}');
      }
    }

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
        if (loaded <= 3) {
          developer.log(
            '📂   Mapped: key=$key photoID=$photoID tags=${tagsMap[photoID]}',
          );
        }
      }
      if (detectionsMap.containsKey(photoID)) {
        photoAllDetections[key] = detectionsMap[photoID]!;
      }
    }
    developer.log('📂 Mapped $loaded tags to photoTags map');
    developer.log('📂 photoTags AFTER load has ${photoTags.length} entries');
  }

  /// Sync all tags from server database to local storage
  /// This ensures local cache matches server data
  Future<void> _syncTagsFromServer() async {
    // Don't sync during tag clearing - the server DB was just wiped
    if (_clearingTags) {
      developer.log('⏸️ Skipping server sync - tag clearing in progress');
      return;
    }

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
      _showSnackBar('Album "$name" created with ${selectedUrls.length} images');
      setState(() {
        _isSelectMode = false;
        _selectedKeys.clear();
      });
      widget.onAlbumCreated?.call();
    }
  }

  Future<void> _deleteSelectedPhotos(BuildContext context) async {
    if (_selectedKeys.isEmpty) return;

    final count = _selectedKeys.length;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count photo${count > 1 ? 's' : ''}?'),
        content: const Text(
          'Photos will be moved to trash and permanently deleted after 30 days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // Get selected URLs
      final selectedUrls = imageUrls
          .where((u) => _selectedKeys.contains(p.basename(u)))
          .toList();

      // Move to trash (soft delete)
      for (final url in selectedUrls) {
        await TrashStore.moveToTrash(url);
        developer.log('🗑️ Moved to trash: $url');
      }

      // Update UI state - remove from gallery
      setState(() {
        imageUrls.removeWhere((url) => selectedUrls.contains(url));
        for (final key in _selectedKeys) {
          photoTags.remove(key);
          photoAllDetections.remove(key);
        }
        // Clear asset cache for deleted items
        for (final url in selectedUrls) {
          if (url.startsWith('local:')) {
            final id = url.substring('local:'.length);
            _localAssets.remove(id);
            _thumbCache.remove(id);
          }
        }
        _selectedKeys.clear();
        _isSelectMode = false;
        _cachedFilteredUrls.clear(); // Invalidate filter cache
      });

      // Show feedback
      _showSnackBar('Moved $count photo${count > 1 ? 's' : ''} to trash');
    } catch (e) {
      developer.log('❌ Error deleting photos: $e');
      _showSnackBar('Failed to delete: $e');
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

  void _showAddFilterMenu() {
    final allTags = getAllCurrentTags().toList()..sort();
    final current = searchQuery.split(' ').where((t) => t.isNotEmpty).toSet();
    final available = allTags.where((t) => !current.contains(t)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more filters available')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: available.length,
            itemBuilder: (context, index) {
              final tag = available[index];
              return ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(tag),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    final tags = searchQuery
                        .split(' ')
                        .where((t) => t.isNotEmpty)
                        .toList();
                    tags.add(tag);
                    searchQuery = tags.join(' ');
                    _searchController.text = searchQuery;
                  });
                  widget.onSearchChanged?.call();
                },
              );
            },
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
    _photoChangesSubscription?.cancel();
    _dotAnimationTimer?.cancel();
    _autoScanRetryTimer?.cancel();
    _progressRefreshTimer?.cancel();
    _smoothProgressTimer?.cancel();
    _fastScrollerHideTimer?.cancel();
    _longPressTimer?.cancel();
    _tooltipTimer?.cancel();
    _starAnimationController.dispose();
    _dotIndexNotifier.dispose();
    _scanProgressNotifier.dispose();
    _scannedCountNotifier.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _showScrollToTop.dispose();
    _showFastScrollerNotifier.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.offset >= 200 && !_showScrollToTop.value) {
      _showScrollToTop.value = true;
    } else if (_scrollController.offset < 200 && _showScrollToTop.value) {
      _showScrollToTop.value = false;
    }

    // Show fast scroller when scrolling (if not already dragging it)
    if (!_isDraggingScroller && _scrollController.offset > 0) {
      // Update notifier instead of setState - only the scroller rebuilds
      _showFastScrollerNotifier.value = true;
      // Reset hide timer
      _fastScrollerHideTimer?.cancel();
      _fastScrollerHideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_isDraggingScroller) {
          _showFastScrollerNotifier.value = false;
        }
      });
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
                        color: Colors.white.withValues(alpha: 0.9),
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
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      8,
                    ), // 4px rule
                    child: SizedBox(
                      height: 96, // 4px rule (divisible by 8)
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          // Three dots menu on the left at credits height
                          Positioned(
                            left: -12, // 4px rule
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
                          // Validation badge - centered horizontally
                          // Only show blue badge when BOTH scanning and validation are complete
                          if (_validationComplete && !_validating && !_scanning)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 4, // 4px rule
                              child: Center(
                                child: GestureDetector(
                                  onTap: () {
                                    // Toggle tooltip - dismiss if already showing
                                    if (_badgeTooltipEntry != null) {
                                      _dismissTooltip();
                                    } else {
                                      _showBadgeTooltip(
                                        context,
                                        '✓ All ${photoTags.length} photos scanned',
                                        Colors.blue.shade700,
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(
                                      4,
                                    ), // 4px rule - smaller
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
                                      size: 16, // 4px rule - smaller
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Show grey/orange badge when scanning or validation is in progress
                          if (!_validationComplete || _scanning || _validating)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 4, // 4px rule
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        // Toggle tooltip - dismiss if already showing
                                        if (_badgeTooltipEntry != null) {
                                          _dismissTooltip();
                                          return;
                                        }
                                        final pct = _cachedLocalPhotoCount > 0
                                            ? (photoTags.length /
                                                      _cachedLocalPhotoCount *
                                                      100)
                                                  .toStringAsFixed(0)
                                            : '0';
                                        final status =
                                            (_scanning || _validating)
                                            ? 'Scanning ${photoTags.length}/$_cachedLocalPhotoCount ($pct%)'
                                            : photoTags.isNotEmpty
                                            ? '${photoTags.length} photos scanned ($pct%)'
                                            : 'No photos scanned yet';
                                        _showBadgeTooltip(
                                          context,
                                          status,
                                          (_scanning || _validating)
                                              ? Colors.orange.shade700
                                              : photoTags.isNotEmpty
                                              ? Colors.green.shade700
                                              : Colors.grey.shade700,
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(
                                          4,
                                        ), // 4px rule - smaller
                                        decoration: BoxDecoration(
                                          color: (_scanning || _validating)
                                              ? Colors.orange.shade100
                                                    .withValues(alpha: 0.3)
                                              : photoTags.isNotEmpty
                                              ? Colors.green.shade100
                                                    .withValues(alpha: 0.3)
                                              : Colors.grey.shade400.withValues(
                                                  alpha: 0.3,
                                                ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: (_scanning || _validating)
                                                ? Colors.orange.shade600
                                                : photoTags.isNotEmpty
                                                ? Colors.green.shade600
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
                                              : photoTags.isNotEmpty
                                              ? Colors.green.shade600
                                              : Colors.grey.shade600,
                                          size: 16, // 4px rule - smaller
                                        ),
                                      ),
                                    ),
                                    // Hide loading dots during "final touches" to avoid redundancy
                                    if ((_scanning || _validating) &&
                                        !(_reached100At != null &&
                                            DateTime.now()
                                                    .difference(_reached100At!)
                                                    .inSeconds >
                                                3))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                        ), // 4px rule
                                        child: _buildLoadingDots(),
                                      ),
                                    // Show scan progress percentage during scanning
                                    if (_scanning)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                        ), // 4px rule
                                        child: ValueListenableBuilder<int>(
                                          valueListenable:
                                              _scannedCountNotifier,
                                          builder: (context, scannedCount, _) {
                                            // Use _cachedLocalPhotoCount if available, otherwise fall back to _scanTotal
                                            final totalPhotos =
                                                _cachedLocalPhotoCount > 0
                                                ? _cachedLocalPhotoCount
                                                : (_scanTotal > 0
                                                      ? _scanTotal
                                                      : 1);
                                            final pct = totalPhotos > 0
                                                ? (scannedCount /
                                                          totalPhotos *
                                                          100)
                                                      .toStringAsFixed(0)
                                                : '0';

                                            // Track when we reach 100%
                                            final isAt100 =
                                                scannedCount >= totalPhotos &&
                                                totalPhotos > 0;
                                            if (isAt100 &&
                                                _reached100At == null) {
                                              _reached100At = DateTime.now();
                                            } else if (!isAt100) {
                                              _reached100At = null;
                                            }

                                            // Show "Final touches" if stuck at 100% for more than 3 seconds
                                            final stuckAt100 =
                                                _reached100At != null &&
                                                DateTime.now()
                                                        .difference(
                                                          _reached100At!,
                                                        )
                                                        .inSeconds >
                                                    3;

                                            if (stuckAt100) {
                                              // Show Final touches with rotating star
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Final touches',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color: Colors
                                                          .orange
                                                          .shade700,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  AnimatedBuilder(
                                                    animation:
                                                        _starAnimationController,
                                                    builder: (context, child) {
                                                      // Slow color animation
                                                      final colorValue =
                                                          (_starAnimationController
                                                                  .value *
                                                              4) %
                                                          4;
                                                      Color starColor;
                                                      if (colorValue < 1) {
                                                        starColor = Color.lerp(
                                                          Colors.yellow,
                                                          Colors.orange,
                                                          colorValue,
                                                        )!;
                                                      } else if (colorValue <
                                                          2) {
                                                        starColor = Color.lerp(
                                                          Colors.orange,
                                                          Colors.pink,
                                                          colorValue - 1,
                                                        )!;
                                                      } else if (colorValue <
                                                          3) {
                                                        starColor = Color.lerp(
                                                          Colors.pink,
                                                          Colors.purple,
                                                          colorValue - 2,
                                                        )!;
                                                      } else {
                                                        starColor = Color.lerp(
                                                          Colors.purple,
                                                          Colors.yellow,
                                                          colorValue - 3,
                                                        )!;
                                                      }

                                                      return Icon(
                                                        Icons
                                                            .auto_awesome, // 4-pointed star, no rotation
                                                        color: starColor,
                                                        size: 12,
                                                      );
                                                    },
                                                  ),
                                                ],
                                              );
                                            }

                                            // Only show percentage if >= 75%
                                            final pctNum =
                                                int.tryParse(pct) ?? 0;
                                            if (pctNum >= 75) {
                                              return Text(
                                                '$pct%',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.orange.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              );
                                            }

                                            // Below 75%, show nothing (just dots visible above)
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            right: 120, // 4px rule
                            top: 0, // 4px rule
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
                            right: 4, // 4px rule
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.only(
                                left: 12, // 4px rule
                                right: 4, // 4px rule
                                top: 8, // 4px rule
                                bottom: 8, // 4px rule
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  24,
                                ), // 4px rule
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
                                              vertical: 8, // 4px rule
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
                                                  offset: const Offset(
                                                    0,
                                                    4,
                                                  ), // 4px rule
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
                                                const SizedBox(
                                                  width: 8,
                                                ), // 4px rule
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
                          const SizedBox(
                            width: 8,
                          ), // 4px rule - gap before Clear
                          // Clear button on the right
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
                                  horizontal: 12, // 4px rule
                                  vertical: 8, // 4px rule
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Add filter button under the magnifying glass/search area
                  if (searchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _showAddFilterMenu,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add filter'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.lightBlue.shade300,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ), // Show album chips (horizontal) when albums exist.
                  // Re-enable album chips when needed
                  // if (albums.isNotEmpty)
                  //   SizedBox(
                  //     height: 64,
                  //     child: ListView.separated(
                  //       padding: const EdgeInsets.symmetric(horizontal: 12),
                  //       scrollDirection: Axis.horizontal,
                  //       itemBuilder: (ctx, idx) {
                  //         final name = albums.keys.elementAt(idx);
                  //         final count = albums[name]?.length ?? 0;
                  //         return ActionChip(
                  //           label: Text('$name ($count)'),
                  //           onPressed: () {
                  //             // Open AlbumScreen to show album contents
                  //             Navigator.push(
                  //               context,
                  //               MaterialPageRoute(
                  //                 builder: (c) => const AlbumScreen(),
                  //               ),
                  //             );
                  //           },
                  //         );
                  //       },
                  //       separatorBuilder: (context, index) =>
                  //           const SizedBox(width: 8),
                  //       itemCount: albums.length,
                  //     ),
                  //   ),
                  Expanded(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onScaleStart: (details) {
                            _lastScale = 1.0;
                          },
                          onScaleUpdate: (details) {
                            // Only trigger zoom when 2+ fingers are on screen (true pinch gesture)
                            if (details.pointerCount < 2) return;

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
                                      8, // 4px rule - reduced
                                      16,
                                      8, // 4px rule
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
                                  // Photo Grid with Fast Scroller
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final gridHeight =
                                            constraints.maxHeight;
                                        return Stack(
                                          children: [
                                            // Grid (refresh via button instead of pull-to-refresh)
                                            GridView.builder(
                                              controller: _scrollController,
                                              padding: const EdgeInsets.only(
                                                left: 12,
                                                right: 12,
                                                top: 12,
                                                bottom:
                                                    100, // Extra space for navbar
                                              ),
                                              gridDelegate:
                                                  SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount:
                                                        _crossAxisCount,
                                                    mainAxisSpacing: spacing,
                                                    crossAxisSpacing: spacing,
                                                    childAspectRatio: 1.0,
                                                  ),
                                              itemCount: filtered.length,
                                              itemBuilder: (context, index) {
                                                final url = filtered[index];
                                                final key = p.basename(url);
                                                final fullTags =
                                                    photoTags[key] ?? [];
                                                // Show the first tag (highest priority from server)
                                                final visibleTags = fullTags
                                                    .take(1)
                                                    .toList();

                                                final isSelected = _selectedKeys
                                                    .contains(key);
                                                // Key based on photo+tags for proper rebuild
                                                return GestureDetector(
                                                  key: ValueKey(
                                                    '$key-${fullTags.join(",")}',
                                                  ),
                                                  onTap: () async {
                                                    if (_isSelectMode) {
                                                      setState(() {
                                                        if (isSelected) {
                                                          _selectedKeys.remove(
                                                            key,
                                                          );
                                                        } else {
                                                          _selectedKeys.add(
                                                            key,
                                                          );
                                                        }
                                                      });
                                                      return;
                                                    }

                                                    // Build list of all photos for swipe navigation (instant, no file loading)
                                                    final allPhotos =
                                                        _buildPhotoDataList(
                                                          filtered,
                                                        );

                                                    // Navigate to photo viewer with swipe support
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            PhotoViewer(
                                                              heroTag: key,
                                                              allPhotos:
                                                                  allPhotos,
                                                              initialIndex:
                                                                  index,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  onLongPress: () {
                                                    setState(() {
                                                      _isSelectMode = true;
                                                      _selectedKeys.add(key);
                                                    });
                                                  },
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        // Wrap the image in a Hero for smooth transition to the fullscreen viewer.
                                                        Hero(
                                                          tag: key,
                                                          child:
                                                              url.startsWith(
                                                                'local:',
                                                              )
                                                              ? FutureBuilder<
                                                                  Uint8List?
                                                                >(
                                                                  future: _getCachedThumbFuture(
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
                                                                        final path = url.substring(
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
                                                                            fit:
                                                                                BoxFit.cover,
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
                                                                                color: Colors.black26,
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
                                                                shape: BoxShape
                                                                    .circle,
                                                                color:
                                                                    isSelected
                                                                    ? Colors
                                                                          .blueAccent
                                                                    : Colors
                                                                          .black54,
                                                              ),
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    6,
                                                                  ),
                                                              child: Icon(
                                                                isSelected
                                                                    ? Icons
                                                                          .check_box
                                                                    : Icons
                                                                          .crop_square,
                                                                color: Colors
                                                                    .white,
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
                                                              builder:
                                                                  (
                                                                    context,
                                                                    constraints,
                                                                  ) {
                                                                    final chips = _buildTagChipsForWidth(
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
                                                                        _recentlyValidated.containsKey(
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
                                                                            opacity:
                                                                                1.0,
                                                                            duration: const Duration(
                                                                              milliseconds: 300,
                                                                            ),
                                                                            child: Wrap(
                                                                              spacing: 4,
                                                                              children: chips,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        if (recentlyValidated)
                                                                          Padding(
                                                                            padding: const EdgeInsets.only(
                                                                              left: 4,
                                                                            ),
                                                                            child: Container(
                                                                              padding: const EdgeInsets.all(
                                                                                4,
                                                                              ),
                                                                              decoration: BoxDecoration(
                                                                                color: Colors.green.withValues(
                                                                                  alpha: 0.9,
                                                                                ),
                                                                                shape: BoxShape.circle,
                                                                                boxShadow: [
                                                                                  BoxShadow(
                                                                                    color: Colors.black.withValues(
                                                                                      alpha: 0.3,
                                                                                    ),
                                                                                    offset: const Offset(
                                                                                      0,
                                                                                      0.5,
                                                                                    ),
                                                                                    blurRadius: 2,
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                              child: const Icon(
                                                                                Icons.auto_awesome,
                                                                                size: 14,
                                                                                color: Colors.white,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                      ],
                                                                    );
                                                                  },
                                                            ),
                                                          ),
                                                        // When tags are hidden, show scan status indicator
                                                        if (!_showTags)
                                                          Positioned(
                                                            right: 6,
                                                            bottom: 6,
                                                            child:
                                                                fullTags
                                                                    .isNotEmpty
                                                                // Green sparkles = scanned
                                                                ? Container(
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
                                                                          blurRadius:
                                                                              2,
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    child: const Icon(
                                                                      Icons
                                                                          .auto_awesome,
                                                                      size: 12,
                                                                      color: Colors
                                                                          .white,
                                                                    ),
                                                                  )
                                                                // Grey circle outline = not scanned
                                                                : Container(
                                                                    width: 20,
                                                                    height: 20,
                                                                    decoration: BoxDecoration(
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      border: Border.all(
                                                                        color: Colors
                                                                            .grey
                                                                            .shade400,
                                                                        width:
                                                                            2,
                                                                      ),
                                                                    ),
                                                                  ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            // Fast Scroller overlay
                                            _buildFastScroller(
                                              filtered,
                                              gridHeight,
                                            ),
                                          ],
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
                          top: 56,
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
                                          child: SingleChildScrollView(
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
                                                      // Block any new scans during clearing
                                                      _clearingTags = true;

                                                      // Clear server tags first
                                                      // IMMEDIATELY stop any ongoing scanning/validation and ALL timers
                                                      _scanning = false;
                                                      _validating = false;
                                                      _validationCancelled =
                                                          true;
                                                      _progressRefreshTimer
                                                          ?.cancel();
                                                      _smoothProgressTimer
                                                          ?.cancel();
                                                      _dotAnimationTimer
                                                          ?.cancel();
                                                      _autoScanRetryTimer
                                                          ?.cancel();
                                                      _autoScanRetryTimer =
                                                          null;
                                                      developer.log(
                                                        '🛑 Stopped scanning/validation and all timers for tag clear',
                                                      );

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

                                                      // Verify storage is actually empty
                                                      final remainingCount =
                                                          await TagStore.getStoredTagCount();
                                                      if (remainingCount > 0) {
                                                        developer.log(
                                                          '⚠️ WARNING: $remainingCount tags still in storage after clear!',
                                                        );
                                                      }

                                                      // Clear in-memory tags AND detections
                                                      photoTags.clear();
                                                      photoAllDetections
                                                          .clear();

                                                      // Invalidate cached filtered list so it rebuilds
                                                      _lastPhotoTagsLength = -1;
                                                      _cachedFilteredUrls
                                                          .clear();

                                                      // Reset ALL scan/validation state to allow fresh re-scan
                                                      _validationComplete =
                                                          false;
                                                      _validationCancelled =
                                                          false;
                                                      _validating = false;
                                                      _scanning = false;
                                                      _hasScannedAtLeastOneBatch =
                                                          false;
                                                      _scanProgress = 0.0;
                                                      _scanProcessed = 0;
                                                      _scanTotal = 0;
                                                      _scannedCountNotifier
                                                              .value =
                                                          0;
                                                      _galleryReadyShown =
                                                          false;

                                                      // Update UI to show cleared state
                                                      if (mounted) {
                                                        setState(() {});
                                                      }

                                                      // Show snackbar
                                                      if (mounted) {
                                                        _showSnackBar(
                                                          'Removed $removed local tags. Starting fresh scan...',
                                                        );
                                                      }

                                                      // Wait briefly to let UI update
                                                      developer.log(
                                                        '🔄 Waiting 1 second before starting fresh scan...',
                                                      );
                                                      await Future.delayed(
                                                        const Duration(
                                                          seconds: 1,
                                                        ),
                                                      );

                                                      // Verify tags are still cleared before starting scan
                                                      if (photoTags
                                                          .isNotEmpty) {
                                                        developer.log(
                                                          '⚠️ Tags not empty after clear (${photoTags.length}). Aborting rescan.',
                                                        );
                                                        _clearingTags = false;
                                                        return;
                                                      }

                                                      // NOTE: Keep _clearingTags = true until _manualScan completes
                                                      // This prevents the retry timer from triggering validation
                                                      // during the gap between now and when _manualScan sets _scanning = true

                                                      if (mounted) {
                                                        developer.log(
                                                          '🔄 Starting fresh scan of ALL photos after tag clear',
                                                        );
                                                        // Use force scan to bypass TagStore checks
                                                        // TagStore was just cleared so checks would be stale
                                                        await _manualScan(
                                                          force: true,
                                                        );
                                                      }

                                                      // Now that scan has started (or completed), allow other operations
                                                      _clearingTags = false;

                                                      // Force validation state to false to prevent immediate validation
                                                      _validating = false;
                                                      _validationComplete =
                                                          false;

                                                      // Restart the retry timer in case scan failed or to continue retrying
                                                      _startAutoScanRetryTimer();
                                                    } catch (e) {
                                                      _clearingTags =
                                                          false; // Reset flag on error
                                                      developer.log(
                                                        'Failed to remove tags: $e',
                                                      );
                                                      if (mounted) {
                                                        _showSnackBar(
                                                          'Failed to remove tags',
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
                                                const Divider(),
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                  child: Text(
                                                    'Developer Testing',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.auto_awesome,
                                                    color: Colors.amber,
                                                  ),
                                                  title: const Text(
                                                    'Test sparkles effect',
                                                  ),
                                                  subtitle: const Text(
                                                    'Simulate "Final touches" animation',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    // Trigger final touches animation by simulating 100%
                                                    setState(() {
                                                      _scanning = true;
                                                      // Ensure we have a valid photo count for the test
                                                      if (_cachedLocalPhotoCount ==
                                                          0) {
                                                        _cachedLocalPhotoCount =
                                                            100; // Set a dummy count
                                                      }
                                                      _scannedCountNotifier
                                                              .value =
                                                          _cachedLocalPhotoCount;
                                                      // Set to 5 seconds ago to immediately trigger the effect
                                                      _reached100At =
                                                          DateTime.now()
                                                              .subtract(
                                                                const Duration(
                                                                  seconds: 5,
                                                                ),
                                                              );
                                                    });

                                                    // Auto-dismiss after 10 seconds
                                                    Future.delayed(
                                                      const Duration(
                                                        seconds: 10,
                                                      ),
                                                      () {
                                                        if (mounted) {
                                                          setState(() {
                                                            _scanning = false;
                                                            _reached100At =
                                                                null;
                                                          });
                                                        }
                                                      },
                                                    );
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.play_circle,
                                                    color: Colors.blue,
                                                  ),
                                                  title: const Text(
                                                    'Show intro video',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            IntroVideoScreen(
                                                              onVideoFinished:
                                                                  () {
                                                                    Navigator.pop(
                                                                      context,
                                                                    );
                                                                  },
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.info,
                                                    color: Colors.green,
                                                  ),
                                                  title: const Text(
                                                    'Show onboarding',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            OnboardingScreen(
                                                              onGetStarted: () {
                                                                Navigator.pop(
                                                                  context,
                                                                );
                                                              },
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.cancel,
                                                  ),
                                                  title: const Text('Cancel'),
                                                  onTap: () =>
                                                      Navigator.pop(ctx),
                                                ),
                                              ],
                                            ),
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

                        // Action buttons for selected photos
                        Positioned(
                          top: 224,
                          right: 16,
                          child: SizedBox(
                            width: 180,
                            height: 240,
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                // Button 3 - Create Album (highest)
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  bottom: _selectedKeys.isNotEmpty ? 160 : 0,
                                  right: 0,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 300),
                                    opacity: _selectedKeys.isNotEmpty
                                        ? 1.0
                                        : 0.0,
                                    child: IgnorePointer(
                                      ignoring: _selectedKeys.isEmpty,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _createAlbumFromSelection,
                                          borderRadius: BorderRadius.circular(
                                            21,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.2,
                                                          ),
                                                      blurRadius: 6,
                                                      offset: const Offset(
                                                        0,
                                                        3,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.create_new_folder,
                                                  color: Colors.green,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'Create album',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Button 2 - Share (middle)
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  bottom: _selectedKeys.isNotEmpty ? 80 : 0,
                                  right: 0,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 300),
                                    opacity: _selectedKeys.isNotEmpty
                                        ? 1.0
                                        : 0.0,
                                    child: IgnorePointer(
                                      ignoring: _selectedKeys.isEmpty,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            _showSnackBar(
                                              'Share ${_selectedKeys.length} photos',
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(
                                            21,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.2,
                                                          ),
                                                      blurRadius: 6,
                                                      offset: const Offset(
                                                        0,
                                                        3,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.share,
                                                  color: Colors.blue,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'Share',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Button 1 - Delete (lowest of the 3)
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  bottom: 0,
                                  right: 0,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 300),
                                    opacity: _selectedKeys.isNotEmpty
                                        ? 1.0
                                        : 0.0,
                                    child: IgnorePointer(
                                      ignoring: _selectedKeys.isEmpty,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            _deleteSelectedPhotos(context);
                                          },
                                          borderRadius: BorderRadius.circular(
                                            21,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.2,
                                                          ),
                                                      blurRadius: 6,
                                                      offset: const Offset(
                                                        0,
                                                        3,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'Delete',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => setState(() => showDebug = false),
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
