import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'album_screen.dart';
import 'pricing_screen.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';

class GalleryScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;
  final VoidCallback? onAlbumCreated;
  const GalleryScreen({super.key, this.onSettingsTap, this.onAlbumCreated});
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
  // Force showing device-local photos even when server images exist
  bool _forceDeviceView = false;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  int _crossAxisCount = 2;
  bool _isSelectMode = false;
  final Set<String> _selectedKeys = {};
  final Map<String, double> _textWidthCache = {};
  // Auto-scan state
  bool _scanning = false;
  double _scanProgress = 0.0; // 0.0-1.0
  int _scanTotal = 0;

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

    // If there are no chips (none fit or no short tags), show a 'None' placeholder when nothing else is present
    if (chips.isEmpty && hiddenCount == 0) {
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'None',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    // If chips is empty but we have hidden tags (e.g. long-only tags), show +N even if it might exceed width
    if (chips.isEmpty && hiddenCount > 0) {
      final plusStr = '+$hiddenCount';
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
    // Start automatic scan of local images when appropriate
    _startAutoScanIfNeeded();
  }

  void reload() => _loadAllImages();

  Future<void> _startAutoScanIfNeeded() async {
    // Only scan if there are local images and we aren't already scanning
    if (_scanning) return;
    final localUrls = imageUrls
        .where((u) => u.startsWith('local:') || u.startsWith('file:'))
        .toList();
    if (localUrls.isEmpty) return;

    // Only consider images that have no persisted scan entry.
    // Presence of a SharedPreferences key for the photo basename indicates
    // the image was scanned at least once (even if tags list is empty).
    final prefs = await SharedPreferences.getInstance();
    final missing = localUrls.where((u) {
      final key = p.basename(u);
      return !prefs.containsKey(key);
    }).toList();
    if (missing.isEmpty) return;

    // Start scanning (capped to avoid runaway uploads during development)
    // We default to scanning up to 300 images; adjust as needed.
    final toScan = missing.take(300).toList();
    _scanTotal = toScan.length;
    setState(() {
      _scanning = true;
      _scanProgress = 0.0;
    });

    await _scanImages(toScan);

    setState(() {
      _scanning = false;
      _scanProgress = 0.0;
      _scanTotal = 0;
    });
  }

  Future<void> _scanImages(List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < urls.length; i++) {
      final u = urls[i];
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
          final res = await ApiService.uploadImage(file);
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
              photoTags[p.basename(u)] = tags;
              await prefs.setString(p.basename(u), json.encode(tags));
            } catch (e) {
              // If parsing fails even though server returned 2xx, mark as scanned with empty tags
              developer.log('Failed parsing scan response for $u: $e');
              photoTags[p.basename(u)] = [];
              await prefs.setString(p.basename(u), json.encode([]));
            }
          } else {
            // Server error or rejection — do not persist so we can retry later
            developer.log('Scan failed for $u: status=${res.statusCode}');
          }
        }
      } catch (e) {
        developer.log('Auto-scan error for $u: $e');
      }

      // update progress
      setState(() {
        _scanProgress = (i + 1) / (_scanTotal == 0 ? 1 : _scanTotal);
      });
      // brief pause so UI updates smoothly and server isn't overwhelmed
      await Future.delayed(const Duration(milliseconds: 200));
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
          photoTags[p.basename(url)] = tags; // preload server tags
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

  Future<void> _loadTags() async {
    final prefs = await SharedPreferences.getInstance();
    for (final url in imageUrls) {
      final key = p.basename(url);
      if (photoTags.containsKey(key) && (photoTags[key]?.isNotEmpty ?? false)) {
        continue; // prefer server
      }
      final j = prefs.getString(key);
      if (j != null) {
        try {
          final tags = (json.decode(j) as List).cast<String>();
          photoTags[key] = tags;
        } catch (_) {}
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
      final tags = photoTags[p.basename(u)] ?? [];
      return searchQuery.isEmpty ||
          tags.any((t) => t.toLowerCase().contains(searchQuery.toLowerCase()));
    }).toList();
  }

  void _selectAllVisible() {
    final visible = _getFilteredImageUrls();
    setState(() {
      for (final url in visible) {
        _selectedKeys.add(p.basename(url));
      }
    });
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: widget.onSettingsTap,
        ),
        actions: [
          if (_isSelectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white),
              tooltip: 'Select all visible',
              onPressed: _selectAllVisible,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '${_selectedKeys.length} selected',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Cancel selection',
              onPressed: () => setState(() {
                _isSelectMode = false;
                _selectedKeys.clear();
              }),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.zoom_out, color: Colors.white),
              tooltip: 'Show more photos per row',
              onPressed: () => setState(() {
                if (_crossAxisCount < 5) _crossAxisCount++;
                developer.log('Grid columns increased: $_crossAxisCount');
              }),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in, color: Colors.white),
              tooltip: 'Show fewer photos per row',
              onPressed: () => setState(() {
                if (_crossAxisCount > 1) _crossAxisCount--;
                developer.log('Grid columns decreased: $_crossAxisCount');
              }),
            ),
            IconButton(
              icon: Icon(
                showDebug ? Icons.bug_report_sharp : Icons.bug_report,
                color: Colors.white,
              ),
              onPressed: () => setState(() => showDebug = !showDebug),
            ),
            IconButton(
              icon: Icon(
                _forceDeviceView ? Icons.phone_iphone : Icons.cloud,
                color: Colors.white,
              ),
              // Tooltip should describe the action that will happen when pressed.
              tooltip: _forceDeviceView
                  ? 'Show server photos'
                  : 'Show device photos',
              onPressed: () async {
                setState(() => _forceDeviceView = !_forceDeviceView);
                if (_forceDeviceView) {
                  await _loadDevicePhotos();
                } else {
                  await _loadAllImages();
                }
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.check_box_outline_blank,
                color: Colors.white,
              ),
              tooltip: 'Select items',
              onPressed: () => setState(() => _isSelectMode = true),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Gallery Screen',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
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
            : SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: (v) => setState(() => searchQuery = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search by tag...',
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      searchQuery = '';
                                    });
                                    // re-request focus so user can start typing immediately
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(_searchFocusNode);
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Color(0xFFF2F0EF).withAlpha(50),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                        ),
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
                      child: Builder(
                        builder: (context) {
                          final filtered = imageUrls.where((u) {
                            final tags = photoTags[p.basename(u)] ?? [];
                            return searchQuery.isEmpty ||
                                tags.any(
                                  (t) => t.toLowerCase().contains(
                                    searchQuery.toLowerCase(),
                                  ),
                                );
                          }).toList();
                          return GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _crossAxisCount,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
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
                              final visibleTags = shortTags.take(3).toList();

                              final isSelected = _selectedKeys.contains(key);
                              return GestureDetector(
                                onTap: () {
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
                                },
                                onLongPress: () {
                                  setState(() {
                                    _isSelectMode = true;
                                    _selectedKeys.add(key);
                                  });
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      url.startsWith('local:')
                                          ? FutureBuilder<Uint8List?>(
                                              future: _getThumbForAsset(
                                                url.substring(6),
                                              ),
                                              builder: (context, snap) {
                                                if (snap.hasData &&
                                                    snap.data != null) {
                                                  return Image.memory(
                                                    snap.data!,
                                                    fit: BoxFit.cover,
                                                  );
                                                }
                                                if (snap.connectionState ==
                                                    ConnectionState.waiting) {
                                                  return Container(
                                                    color: Colors.black26,
                                                  );
                                                }
                                                return Container(
                                                  color: Colors.black26,
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                    color: Colors.white54,
                                                  ),
                                                );
                                              },
                                            )
                                          : (url.startsWith('file:')
                                                ? (() {
                                                    final path = url.substring(
                                                      'file:'.length,
                                                    );
                                                    return ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      child: Image.file(
                                                        File(path),
                                                        fit: BoxFit.cover,
                                                      ),
                                                    );
                                                  })()
                                                : Image.network(
                                                    ApiService.resolveImageUrl(
                                                      url,
                                                    ),
                                                    fit: BoxFit.cover,
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
                                                                Icons
                                                                    .broken_image,
                                                                color: Colors
                                                                    .white54,
                                                                size: 36,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                  )),
                                      if (_isSelectMode)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isSelected
                                                  ? Colors.blueAccent
                                                  : Colors.black54,
                                            ),
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              isSelected
                                                  ? Icons.check
                                                  : Icons
                                                        .check_box_outline_blank,
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
                                          builder: (context, constraints) {
                                            final chips =
                                                _buildTagChipsForWidth(
                                                  visibleTags,
                                                  fullTags,
                                                  constraints.maxWidth,
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
                          );
                        },
                      ),
                    ),

                    // Show scanning progress when auto-scan is active
                    if (_scanning)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LinearProgressIndicator(
                              value: _scanTotal > 0 ? _scanProgress : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${(_scanProgress * 100).round()}% Scanning images...',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      // Pricing moved to Settings screen; FAB removed.
      bottomNavigationBar: _isSelectMode && _selectedKeys.isNotEmpty
          ? SafeArea(
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedKeys.length} selected',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _createAlbumFromSelection,
                      icon: const Icon(Icons.create_new_folder),
                      label: Text('Create Album (${_selectedKeys.length})'),
                    ),
                  ],
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
