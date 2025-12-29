import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../services/api_service.dart';

/// Data class for a photo in the gallery viewer
/// Uses URL string for lazy loading instead of pre-resolved file paths
class PhotoData {
  final String url; // Can be 'local:id', 'file:path', or network URL
  final String heroTag;
  final List<String> tags;
  final List<String> allDetections;

  /// For local assets, store the asset reference for lazy file loading
  final AssetEntity? asset;

  const PhotoData({
    required this.url,
    required this.heroTag,
    this.tags = const [],
    this.allDetections = const [],
    this.asset,
  });
}

/// Fullscreen photo viewer with pinch-zoom, swipe navigation, and tag display.
/// Supports swiping left/right to navigate between photos.
class PhotoViewer extends StatefulWidget {
  final String? filePath;
  final String? networkUrl;
  final String heroTag;
  final List<String> tags;
  final List<String> allDetections;

  /// Optional list of all photos for swipe navigation
  final List<PhotoData>? allPhotos;

  /// Initial index when using allPhotos
  final int initialIndex;

  /// Callbacks for action buttons
  final void Function(String url)? onDelete;
  final void Function(String url)? onShare;
  final void Function(String url)? onAddToAlbum;

  const PhotoViewer({
    super.key,
    this.filePath,
    this.networkUrl,
    required this.heroTag,
    this.tags = const [],
    this.allDetections = const [],
    this.allPhotos,
    this.initialIndex = 0,
    this.onDelete,
    this.onShare,
    this.onAddToAlbum,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer>
    with TickerProviderStateMixin {
  bool _showInfo = true;
  bool _showControls = true;
  late PageController _pageController;
  late int _currentIndex;

  /// Capitalize the first letter of a tag, and convert 'unknown' to 'Other'
  String _capitalizeTag(String tag) {
    if (tag.isEmpty) return tag;
    // Treat 'unknown' as 'other'
    if (tag.toLowerCase() == 'unknown') return 'Other';
    return tag[0].toUpperCase() + tag.substring(1).toLowerCase();
  }

  /// Cache loaded files to prevent flickering when swiping
  final Map<int, File> _fileCache = {};

  /// Cache TransformationControllers per page to avoid recreation
  final Map<int, TransformationController> _transformControllers = {};

  /// Track if user is zoomed in (to disable PageView swiping)
  bool _isZoomed = false;

  /// Track scale at interaction start to detect intentional pinch
  double _scaleAtStart = 1.0;

  /// Minimum scale change required before zoom is applied (gives time for 2nd finger)
  static const double _scaleThreshold = 0.08;

  /// Track number of pointers to detect pinch vs swipe
  int _pointerCount = 0;

  /// Whether we're currently in a pinch gesture
  bool _isPinching = false;

  /// Animation controller for double-tap zoom
  AnimationController? _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // Make status bar transparent for true fullscreen feel
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Preload current and adjacent photos
    _preloadPhotos(_currentIndex);
  }

  /// Get or create a TransformationController for a page
  TransformationController _getTransformController(int index) {
    return _transformControllers.putIfAbsent(
      index,
      () => TransformationController(),
    );
  }

  /// Preload files for current, previous, and next photos (no setState to avoid lag)
  void _preloadPhotos(int index) {
    if (widget.allPhotos == null) return;

    for (int i = index - 1; i <= index + 1; i++) {
      if (i >= 0 &&
          i < widget.allPhotos!.length &&
          !_fileCache.containsKey(i)) {
        final photo = widget.allPhotos![i];
        if (photo.url.startsWith('local:') && photo.asset != null) {
          photo.asset!.file.then((file) {
            if (file != null && mounted) {
              // Just cache it, don't setState - the FutureBuilder will handle display
              _fileCache[i] = file;
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _zoomAnimationController?.dispose();
    // Dispose all transform controllers
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    // Restore system UI
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    super.dispose();
  }

  PhotoData get _currentPhoto {
    if (widget.allPhotos != null && widget.allPhotos!.isNotEmpty) {
      return widget.allPhotos![_currentIndex];
    }
    // Fallback for single photo mode
    String url = '';
    if (widget.filePath != null) {
      url = 'file:${widget.filePath}';
    } else if (widget.networkUrl != null) {
      url = widget.networkUrl!;
    }
    return PhotoData(
      url: url,
      heroTag: widget.heroTag,
      tags: widget.tags,
      allDetections: widget.allDetections,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiplePhotos =
        widget.allPhotos != null && widget.allPhotos!.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.5),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: hasMultiplePhotos
                  ? Text(
                      '${_currentIndex + 1} / ${widget.allPhotos!.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    )
                  : null,
              centerTitle: true,
              actions: [
                if (_currentPhoto.tags.isNotEmpty ||
                    _currentPhoto.allDetections.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _showInfo ? Icons.info : Icons.info_outline,
                      color: Colors.white,
                    ),
                    onPressed: () => setState(() => _showInfo = !_showInfo),
                    tooltip: 'Toggle info',
                  ),
              ],
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Photo(s) with PageView for swiping
          if (hasMultiplePhotos)
            Listener(
              onPointerDown: (_) {
                _pointerCount++;
                if (_pointerCount >= 2 && !_isPinching) {
                  setState(() => _isPinching = true);
                }
              },
              onPointerUp: (_) {
                _pointerCount = (_pointerCount - 1).clamp(0, 10);
                if (_pointerCount < 2 && _isPinching) {
                  // Reset immediately - no delay needed
                  setState(() => _isPinching = false);
                }
              },
              onPointerCancel: (_) {
                _pointerCount = (_pointerCount - 1).clamp(0, 10);
                if (_pointerCount < 2 && _isPinching) {
                  setState(() => _isPinching = false);
                }
              },
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.allPhotos!.length,
                // Disable swiping when zoomed in OR when pinching (2+ fingers)
                physics: (_isZoomed || _isPinching)
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (index) {
                  // Reset pointer state when page changes
                  _pointerCount = 0;
                  _isPinching = false;
                  setState(() {
                    _currentIndex = index;
                    _isZoomed = false; // Reset zoom when changing pages
                  });
                  // Preload adjacent photos
                  _preloadPhotos(index);
                },
                itemBuilder: (context, index) {
                  final photo = widget.allPhotos![index];
                  return _buildZoomablePhoto(
                    photo,
                    index,
                    index == widget.initialIndex,
                  );
                },
              ),
            )
          else
            _buildZoomablePhoto(_currentPhoto, 0, true),

          // Tags overlay at bottom
          if (_showInfo && _showControls) _buildTagsOverlay(_currentPhoto),

          // Action buttons at bottom
          if (_showControls) _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final hasCallbacks =
        widget.onDelete != null ||
        widget.onShare != null ||
        widget.onAddToAlbum != null;

    if (!hasCallbacks) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomPadding + 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.onAddToAlbum != null)
            _buildActionButton(Icons.photo_album, 'Album', Colors.green, () {
              widget.onAddToAlbum?.call(_currentPhoto.url);
            }),
          if (widget.onShare != null)
            _buildActionButton(Icons.share, 'Share', Colors.blue, () {
              widget.onShare?.call(_currentPhoto.url);
            }),
          if (widget.onDelete != null)
            _buildActionButton(Icons.delete, 'Delete', Colors.red, () {
              widget.onDelete?.call(_currentPhoto.url);
            }),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomablePhoto(PhotoData photo, int index, bool isHero) {
    Widget imageWidget;
    final url = photo.url;

    if (url.startsWith('local:')) {
      // Check cache first to avoid flickering
      if (_fileCache.containsKey(index)) {
        imageWidget = Image.file(
          _fileCache[index]!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        );
      } else {
        // Local asset - use FutureBuilder to load lazily
        imageWidget = FutureBuilder<File?>(
          future: photo.asset?.file,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            if (snapshot.hasData && snapshot.data != null) {
              // Cache the file for next time
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_fileCache.containsKey(index)) {
                  _fileCache[index] = snapshot.data!;
                }
              });
              return Image.file(
                snapshot.data!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              );
            }
            return const Center(
              child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
            );
          },
        );
      }
    } else if (url.startsWith('file:')) {
      final path = url.substring('file:'.length);
      imageWidget = Image.file(
        File(path),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    } else if (url.isNotEmpty) {
      // Network URL
      final resolved = ApiService.resolveImageUrl(url);
      imageWidget = Image.network(
        resolved,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          );
        },
      );
    } else {
      imageWidget = const Center(
        child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
      );
    }

    // Use cached TransformationController to track zoom state
    final transformController = _getTransformController(index);

    // Animated double tap handler for zoom toggle
    void handleDoubleTap() {
      final currentScale = transformController.value.getMaxScaleOnAxis();

      // Cancel any existing animation
      _zoomAnimationController?.dispose();

      // Create new animation controller
      _zoomAnimationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      );

      final Matrix4 targetMatrix;
      final bool willBeZoomed;

      if (currentScale > 1.05) {
        // Zoomed in - animate back to original
        targetMatrix = Matrix4.identity();
        willBeZoomed = false;
      } else {
        // Not zoomed - animate to 2x at center
        final center = MediaQuery.of(context).size.center(Offset.zero);
        targetMatrix = Matrix4.identity()
          ..translateByVector3(vm.Vector3(center.dx, center.dy, 0))
          ..scaleByVector3(vm.Vector3(2.0, 2.0, 2.0))
          ..translateByVector3(vm.Vector3(-center.dx, -center.dy, 0));
        willBeZoomed = true;
      }

      // Create the animation
      _zoomAnimation =
          Matrix4Tween(
            begin: transformController.value,
            end: targetMatrix,
          ).animate(
            CurvedAnimation(
              parent: _zoomAnimationController!,
              curve: Curves.easeOutCubic,
            ),
          );

      // Update transform controller on each frame
      _zoomAnimation!.addListener(() {
        transformController.value = _zoomAnimation!.value;
      });

      // Update zoom state when animation completes
      _zoomAnimationController!.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _isZoomed = willBeZoomed);
        }
      });

      // Start the animation
      _zoomAnimationController!.forward();
    }

    final viewer = GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      onDoubleTap: handleDoubleTap,
      child: InteractiveViewer(
        transformationController: transformController,
        panEnabled: true,
        // Allow panning only within the scaled image bounds
        boundaryMargin: EdgeInsets.zero,
        constrained: true,
        clipBehavior: Clip.hardEdge,
        minScale: 1.0,
        // 2 pinches worth of zoom (1.0 -> 1.7 -> 3.0)
        maxScale: 3.0,
        // Require a meaningful scale change before zooming starts
        // This gives users time to place their second finger
        scaleEnabled: true,
        onInteractionStart: (details) {
          _scaleAtStart = transformController.value.getMaxScaleOnAxis();
        },
        onInteractionUpdate: (details) {
          // If just starting to scale (from 1.0), ignore small changes
          // This prevents accidental zoom when placing second finger
          if (_scaleAtStart == 1.0 && details.pointerCount == 2) {
            final currentScale = transformController.value.getMaxScaleOnAxis();
            final scaleChange = (currentScale - _scaleAtStart).abs();
            if (scaleChange < _scaleThreshold) {
              // Reset to prevent micro-zooms while placing fingers
              transformController.value = Matrix4.identity();
            }
          }
        },
        onInteractionEnd: (_) {
          // Only update state if zoom status changed
          final scale = transformController.value.getMaxScaleOnAxis();
          final isNowZoomed = scale > 1.05;
          if (isNowZoomed != _isZoomed) {
            setState(() => _isZoomed = isNowZoomed);
          }
        },
        // Image fills viewport, constrained prevents panning outside
        child: Center(child: imageWidget),
      ),
    );

    if (isHero) {
      return Hero(tag: photo.heroTag, child: viewer);
    }
    return viewer;
  }

  Widget _buildTagsOverlay(PhotoData photo) {
    // Get unique detections that aren't already in tags
    final extraDetections = photo.allDetections
        .where(
          (d) =>
              !photo.tags.map((t) => t.toLowerCase()).contains(d.toLowerCase()),
        )
        .toList();

    if (photo.tags.isEmpty && extraDetections.isEmpty) {
      return const SizedBox.shrink();
    }

    // Get safe area padding for bottom navigation bar
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.black.withValues(alpha: 0.0),
            ],
          ),
        ),
        padding: EdgeInsets.fromLTRB(16, 48, 16, 128 + 32 + bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category tags
            if (photo.tags.isNotEmpty) ...[
              const Text(
                'Category',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: photo.tags.map((tag) {
                  final displayTag = _capitalizeTag(tag);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(displayTag),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getCategoryIcon(displayTag),
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          displayTag,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            // All detected objects
            if (extraDetections.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Detected Objects',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: extraDetections.map((obj) {
                  final displayObj = _capitalizeTag(obj);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      displayObj,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'people':
        return Colors.blue;
      case 'animals':
        return Colors.orange;
      case 'food':
        return Colors.green;
      case 'scenery':
        return Colors.teal;
      case 'document':
        return Colors.purple;
      case 'screenshot':
        return Colors.indigo;
      case 'other':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getCategoryIcon(String tag) {
    switch (tag.toLowerCase()) {
      case 'people':
        return Icons.people;
      case 'animals':
        return Icons.pets;
      case 'food':
        return Icons.restaurant;
      case 'scenery':
        return Icons.landscape;
      case 'document':
        return Icons.description;
      case 'screenshot':
        return Icons.screenshot;
      case 'other':
        return Icons.help_outline;
      default:
        return Icons.label;
    }
  }
}
