import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/photo_id.dart';
import '../services/tag_store.dart';
import 'dart:io';
import 'album_screen.dart';
import 'pricing_screen.dart';
import 'package:path/path.dart' as p;
import '../services/photo_id.dart';
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
  // Keys currently being scanned in the active scan session
  final Set<String> _scanningKeys = {};
  // Recent save events for visual debugging (most recent first)
  final List<String> _recentSaves = [];
  bool loading = true;
  // Device-local asset storage and thumbnail cache for local view
  final Map<String, AssetEntity> _localAssets = {};
  final Map<String, Uint8List> _thumbCache = {};
  Map<String, List<String>> albums = {};
  String searchQuery = '';
  bool showDebug = false;
  bool _showSearchBar = true;
  // Force showing device-local photos even when server images exist
  bool _forceDeviceView = false;
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
    setState(() => loading = true);
    await _loadOrganizedImages();
    await _loadTags();
    developer.log('Total photos in gallery: ${imageUrls.length}');
    setState(() => loading = false);
    // Start automatic scan of local images is disabled — require manual
    // trigger via the Scan button to avoid unexpected uploads on open.
    await _updateUnscannedCount();
    try {
      final prefs = await SharedPreferences.getInstance();
      final auto = prefs.getBool('autoscan_auto_start') ?? false;
      if (auto) {
        _startAutoScanIfNeeded();
      }
    } catch (_) {}
  }

  Future<void> _updateUnscannedCount() async {
    try {
      final localUrls = imageUrls
          .where((u) => u.startsWith('local:') || u.startsWith('file:'))
          .toList();
      int unscanned = 0;
      for (final u in localUrls) {
        final key = _keyForUrl(u);
        final t = await TagStore.loadLocalTags(key);
        if (t == null) unscanned++;
      }
      if (mounted) setState(() => _currentUnscannedCount = unscanned);
    } catch (_) {
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
      final key = _keyForUrl(url);
      final tags = photoTags[key] ?? [];
      allTags.addAll(tags);
    }
    return allTags;
  }

  Future<void> _startAutoScanIfNeeded() async {
    // Only scan if there are local images and we aren't already scanning
    if (_scanning) return;
    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();
    if (localUrls.isEmpty) return;

    // Only consider images that have no persisted scan entry.
    // Use TagStore to check for local tags (async-safe canonical keys).
    final missing = <String>[];
    for (final u in localUrls) {
      final key = _keyForUrl(u);
      final t = await TagStore.loadLocalTags(key);
      if (t == null) missing.add(u);
    }
    if (missing.isEmpty) return;

    // Start scanning (capped to avoid runaway uploads during development)
    // We default to scanning up to 300 images; adjust as needed.
    final toScan = missing.take(300).toList();
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
    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();
    if (localUrls.isEmpty) return;

    List<String> toScan = [];
    if (force) {
      toScan = localUrls;
    } else {
      for (final u in localUrls) {
        final key = _keyForUrl(u);
        final t = await TagStore.loadLocalTags(key);
        if (t == null) toScan.add(u);
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

    // Update unscanned count after scanning completes
    await _updateUnscannedCount();

    setState(() {
      _scanning = false;
      _scanProgress = 0.0;
      _scanTotal = 0;
      _scanProcessed = 0;
    });
  }

  Future<void> _scanImages(List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < urls.length; i++) {
      final u = urls[i];
      final loopKey = _keyForUrl(u);
      // mark this key as scanning so UI can show a temporary indicator
      if (!mounted) return;
      setState(() {
        _scanningKeys.add(loopKey);
      });

      // Cooperative pause: wait while paused
      while (_scanPaused) {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 200));
      }
      try {
        // Get a file reference for upload
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

        if (file == null || !await file.exists()) {
          // File not available for upload — do not persist tags so it can be retried later
          developer.log('Skipping scan for $u: file not found');
        } else {
          // Determine canonical photoID: use asset id when available, otherwise file:// path
          String photoID;
          if (u.startsWith('local:')) {
            photoID = u.substring('local:'.length);
          } else if (u.startsWith('file:')) {
            final path = u.substring('file:'.length);
            photoID = 'file://' + path;
          } else {
            photoID = _keyForUrl(u);
          }

          final res = await ApiService.uploadImage(file, photoID: photoID);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            try {
              final body = json.decode(res.body);
              List<String> tags = [];
              if (body is Map && body['tags'] is List) {
                tags = (body['tags'] as List).cast<String>();
              } else if (body is Map && body['labels'] is List) {
                tags = (body['labels'] as List).cast<String>();
              }
              // Persist the tags (may be empty) to mark this image as scanned
              final key = PhotoId.canonicalId(photoID);
              // Update UI immediately for this photo and clear scanning flag
              setState(() {
                photoTags[key] = tags;
                _scanningKeys.remove(key);
              });
              developer.log(
                'Scan result for $u -> key=$key tags=${tags.join(', ')}',
              );
              await TagStore.saveLocalTags(key, tags);
              developer.log('Saved local tags for $key');
              // Add to recent saves for on-screen debug
              if (mounted) {
                setState(() {
                  _recentSaves.insert(0, '$key: ${tags.join(', ')}');
                  if (_recentSaves.length > 8) _recentSaves.removeLast();
                });
              }
            } catch (e) {
              // If parsing fails even though server returned 2xx, mark as scanned with empty tags
              developer.log('Failed parsing scan response for $u: $e');
              final key = PhotoId.canonicalId(photoID);
              setState(() {
                photoTags[key] = [];
                _scanningKeys.remove(key);
              });
              developer.log('Saving empty tags for $key after parse error');
              await TagStore.saveLocalTags(key, []);
              if (mounted) {
                setState(() {
                  _recentSaves.insert(0, '$key: (empty)');
                  if (_recentSaves.length > 8) _recentSaves.removeLast();
                });
              }
            }
          } else {
            // Server error or rejection — do not persist so we can retry later
            developer.log('Scan failed for $u: status=${res.statusCode}');
          }
        }
      } catch (e) {
        developer.log('Auto-scan error for $u: $e');
      }

      // Ensure scanningKeys is cleaned up if an exception occurred before removal
      if (mounted && _scanningKeys.contains(loopKey)) {
        setState(() {
          _scanningKeys.remove(loopKey);
        });
      }

      // update progress and processed count
      setState(() {
        _scanProcessed = (i + 1);
        _scanProgress = (i + 1) / (_scanTotal == 0 ? 1 : _scanTotal);
      });
      // brief pause so UI updates smoothly and server isn't overwhelmed
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _loadOrganizedImages() async {
    try {
      final res = await ApiService.getAllOrganizedImagesWithTags();
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final arr = List<dynamic>.from(data['images'] ?? []);
        final urls = <String>[];
        for (final item in arr) {
          final url = item['url'] as String;
          final tags = List<String>.from(item['tags'] ?? []);
          urls.add(url);
          photoTags[_keyForUrl(url)] = tags; // preload server tags
        }
        if (urls.isNotEmpty) {
          setState(() => imageUrls = urls);
          return;
        }
        // If server returned an empty list, fall back to device-local photos
        developer.log(
          'Server returned 0 images — falling back to device photos',
        );
      }
    } catch (e) {
      developer.log('Failed to load images: $e');
    }
    // If server returned nothing or failed, fall back to device-local photos
    await _loadDevicePhotos();
  }

  Future<void> _loadDevicePhotos() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        developer.log('Photo permission denied when loading device photos');
        // Try filesystem fallback even if PhotoManager permission denied (helpful on emulators)
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
      final albums = await PhotoManager.getAssetPathList(onlyAll: true);
      if (albums.isEmpty) {
        // Try filesystem fallback (emulator/device files under /sdcard/Pictures)
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
      final all = albums.first;
      final total = await all.assetCountAsync;
      final cap = total < 500 ? total : 500;
      final assets = await all.getAssetListRange(start: 0, end: cap);

      final urls = <String>[];
      _localAssets.clear();
      _thumbCache.clear();
      for (final a in assets) {
        final id = a.id;
        _localAssets[id] = a;
        urls.add('local:$id');
      }
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
    } catch (e) {
      developer.log('Error loading device photos: $e');
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

  String _keyForUrl(String url) {
    try {
      return PhotoId.canonicalId(url);
    } catch (_) {
      if (url.startsWith('local:')) return url.substring('local:'.length);
      if (url.startsWith('file:'))
        return 'file://' + url.substring('file:'.length);
      return url;
    }
  }

  Future<void> _loadTags() async {
    for (final url in imageUrls) {
      final key = _keyForUrl(url);
      if (photoTags.containsKey(key) && (photoTags[key]?.isNotEmpty ?? false)) {
        continue; // prefer server
      }
      final local = await TagStore.loadLocalTags(key);
      if (local != null) {
        developer.log('Loaded local tags for $key: ${local.join(', ')}');
        setState(() {
          photoTags[key] = local;
        });
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

  List<String> _getFilteredImageUrls() {
    return imageUrls.where((u) {
      final tags = photoTags[_keyForUrl(u)] ?? [];
      if (searchQuery.isEmpty) return true;

      // Split search query into individual search terms
      final searchTerms = searchQuery
          .split(' ')
          .where((term) => term.isNotEmpty)
          .map((term) => term.toLowerCase())
          .toList();

      // Check if any photo tag contains any of the search terms
      return searchTerms.any(
        (searchTerm) => tags.any((t) => t.toLowerCase().contains(searchTerm)),
      );
    }).toList();
  }

  void _selectAllVisible() {
    final visible = _getFilteredImageUrls();
    setState(() {
      for (final url in visible) {
        _selectedKeys.add(_keyForUrl(url));
      }
    });
  }

  Future<void> _createAlbumFromSelection() async {
    if (_selectedKeys.isEmpty) return;
    final selectedUrls = imageUrls
        .where((u) => _selectedKeys.contains(_keyForUrl(u)))
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
    final unscanned = <String>[];
    for (final u in imageUrls) {
      if (!(u.startsWith('local:') || u.startsWith('file:'))) continue;
      final key = _keyForUrl(u);
      final t = await TagStore.loadLocalTags(key);
      if (t == null) unscanned.add(u);
    }
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
                final key = _keyForUrl(url);
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
        .where((u) => (photoTags[_keyForUrl(u)] ?? []).contains(tag))
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
      extendBodyBehindAppBar: true,
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
                  const SizedBox(height: 20),
                  // Gallery title and Credits
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                    child: SizedBox(
                      height: 50,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Three dots menu and scan stats on the left
                          Positioned(
                            left: -15,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
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
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _currentUnscannedCount == 0
                                            ? Icons.check_circle
                                            : Icons.pending_outlined,
                                        color: _currentUnscannedCount == 0
                                            ? Colors.green.shade600
                                            : Colors.orange.shade700,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _currentUnscannedCount == 0
                                            ? '${imageUrls.length}'
                                            : '${imageUrls.length - _currentUnscannedCount}/${imageUrls.length}',
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Scanned',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
                              bottom: 0,
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
                        ],
                      ),
                    ),

                  // Show album chips (horizontal) when albums exist.
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
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                            // Calculate the scale change since last update
                            final scaleDelta = details.scale - _lastScale;

                            // Only update if there's a significant change (threshold to prevent jitter)
                            if (scaleDelta.abs() > 0.15) {
                              setState(() {
                                if (scaleDelta > 0) {
                                  // Pinch out - zoom in (fewer columns)
                                  if (_crossAxisCount > 1) _crossAxisCount--;
                                } else {
                                  // Pinch in - zoom out (more columns)
                                  if (_crossAxisCount < 5) _crossAxisCount++;
                                }
                              });
                              _lastScale = details.scale;
                            }
                          },
                          onScaleEnd: (details) {
                            _lastScale = 1.0;
                          },
                          child: Builder(
                            builder: (context) {
                              final filtered = imageUrls.where((u) {
                                final tags = photoTags[_keyForUrl(u)] ?? [];
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

                              // Adjust spacing based on column count - fewer columns = more spacing
                              final spacing = _crossAxisCount <= 2
                                  ? 4.0
                                  : (_crossAxisCount == 3 ? 3.0 : 2.0);

                              return Column(
                                children: [
                                  // Select All button row
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
                                              // Select all visible photos
                                              if (_selectedKeys.length ==
                                                      filtered.length &&
                                                  _selectedKeys.isNotEmpty) {
                                                // Deselect all and exit select mode
                                                _selectedKeys.clear();
                                                _isSelectMode = false;
                                              } else {
                                                // Enter select mode and select all
                                                _isSelectMode = true;
                                                _selectedKeys.clear();
                                                for (final url in filtered) {
                                                  _selectedKeys.add(
                                                    _keyForUrl(url),
                                                  );
                                                }
                                              }
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  _isSelectMode &&
                                                      _selectedKeys.isNotEmpty
                                                  ? Colors.blue.shade50
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color:
                                                    _isSelectMode &&
                                                        _selectedKeys.isNotEmpty
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
                                                  _selectedKeys.length ==
                                                              filtered.length &&
                                                          _selectedKeys
                                                              .isNotEmpty
                                                      ? Icons.check_box
                                                      : Icons
                                                            .check_box_outline_blank,
                                                  color:
                                                      _isSelectMode &&
                                                          _selectedKeys
                                                              .isNotEmpty
                                                      ? Colors.blue.shade700
                                                      : Colors.grey.shade600,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _selectedKeys.length ==
                                                              filtered.length &&
                                                          _selectedKeys
                                                              .isNotEmpty
                                                      ? 'Deselect All'
                                                      : 'Select All',
                                                  style: TextStyle(
                                                    color:
                                                        _isSelectMode &&
                                                            _selectedKeys
                                                                .isNotEmpty
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
                                        final key = _keyForUrl(url);
                                        final fullTags = photoTags[key] ?? [];
                                        // If this photo is currently being scanned and has no tags yet,
                                        // show a temporary scanning indicator. Otherwise prefer short tags
                                        // (<=8 chars). If no short tags exist but full tags do, show the
                                        // first available tag truncated so the UI visibly changes.
                                        List<String> visibleTags;
                                        if (fullTags.isEmpty &&
                                            _scanningKeys.contains(key)) {
                                          visibleTags = ['Scanning...'];
                                        } else {
                                          final shortTags = fullTags
                                              .where((t) => t.length <= 8)
                                              .toList();
                                          if (shortTags.isNotEmpty) {
                                            visibleTags = shortTags
                                                .take(3)
                                                .toList();
                                          } else if (fullTags.isNotEmpty) {
                                            final first = fullTags.first;
                                            final tr = first.length > 10
                                                ? (first.substring(0, 10) + '…')
                                                : first;
                                            visibleTags = [tr];
                                          } else {
                                            visibleTags = [];
                                          }
                                        }

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
                                                  Navigator.push(
                                                    context,
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
                                                    final prefs =
                                                        await SharedPreferences.getInstance();
                                                    for (final u in imageUrls) {
                                                      final key = _keyForUrl(u);
                                                      await TagStore.removeLocalTags(
                                                        key,
                                                      );
                                                      photoTags.remove(key);
                                                    }
                                                    if (mounted)
                                                      setState(() {});
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'All persisted tags removed',
                                                        ),
                                                      ),
                                                    );
                                                  } catch (e) {
                                                    developer.log(
                                                      'Failed to remove tags: $e',
                                                    );
                                                    if (mounted)
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Failed to remove tags',
                                                          ),
                                                        ),
                                                      );
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
                        // On-screen recent save debug panel (bottom-left)
                        Positioned(
                          bottom: 80,
                          left: 8,
                          child: _recentSaves.isEmpty
                              ? const SizedBox.shrink()
                              : Container(
                                  width: 220,
                                  constraints: const BoxConstraints(
                                    maxHeight: 220,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Recent saves',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Flexible(
                                        child: SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: _recentSaves
                                                .map(
                                                  (s) => Text(
                                                    s,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
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
                                                Text(
                                                  'Scanning images',
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
                                      IconButton(
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
                    child: Container(
                      height: 64,
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
