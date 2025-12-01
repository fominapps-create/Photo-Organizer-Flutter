import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // When showing device-local assets we store them here keyed by asset id
  final Map<String, AssetEntity> _localAssets = {};
  // Cache thumbnails for local assets to avoid repeated work
  final Map<String, Uint8List> _thumbCache = {};
  Map<String, List<String>> photoTags = {};
  bool loading = true;
  // Autoscan state
  bool _autoscanRunning = false;
  int _autoscanProgress = 0;
  int _autoscanTotal = 0;
  int _autoscanSaved = 0;
  String searchQuery = '';
  bool showDebug = false;
  // When true, force showing device-local photos instead of server-organized folders
  bool _forceDeviceView = false;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  int _crossAxisCount = 2;
  bool _isSelectMode = false;
  final Set<String> _selectedKeys = {};
  final Map<String, double> _textWidthCache = {};

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
      final bool isPremium = t.startsWith('premium:');
      final displayText = isPremium ? t.replaceFirst('premium:', '') : t;
      final textWidth = _measureTextWidth(displayText, style);
      final w = textWidth + horizontalPadding + (isPremium ? 18.0 : 0.0);
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
                color: isPremium ? Colors.amber.shade700 : _colorForTag(t),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPremium) ...[
                    const Icon(Icons.star, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                  ],
                  Text(displayText, style: style),
                ],
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
    _loadAllImages().then((_) => _maybeStartAutoScan());
  }

  Future<void> _maybeStartAutoScan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('autoscan_enabled') ?? true;
      final wifiOnly = prefs.getBool('autoscan_wifi_only') ?? true;
      final lastMs = prefs.getInt('last_autoscan_ms') ?? 0;
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      // Do not autoscan more than once per 24 hours by default
      if (!enabled) return;
      if (DateTime.now().difference(last).inHours < 24) return;

      if (wifiOnly) {
        final conn = await Connectivity().checkConnectivity();
        if (conn != ConnectivityResult.wifi) {
          developer.log('Autoscan skipped: not on Wi‑Fi');
          return;
        }
      }

      // Request permissions to access photos
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        developer.log('Autoscan skipped: permission denied');
        return;
      }

      // Enumerate assets and run a capped sample autoscan (default 200)
      const sampleLimit = 200;
      final albums = await PhotoManager.getAssetPathList(onlyAll: true);
      if (albums.isEmpty) return;
      final all = albums.first;
      final total = await all.assetCountAsync;
      final take = total < sampleLimit ? total : sampleLimit;
      final assets = await all.getAssetListRange(start: 0, end: take);

      // Start scanning in background
      _runAutoScan(assets);
    } catch (e) {
      developer.log('Autoscan failed to start: $e');
    }
  }

  Future<void> _runAutoScan(List<AssetEntity> assets) async {
    if (_autoscanRunning) return;
    setState(() {
      _autoscanRunning = true;
      _autoscanProgress = 0;
      _autoscanTotal = assets.length;
      _autoscanSaved = 0;
    });

    final prefs = await SharedPreferences.getInstance();
    bool completed = true;
    for (final asset in assets) {
      if (!_autoscanRunning) {
        completed = false;
        break;
      }
      try {
        final key = p.basename(asset.title ?? asset.id);
        // Skip if we already have server tags persisted
        if (prefs.getString(key) != null) {
          setState(() => _autoscanProgress++);
          continue;
        }

        // Get a reasonably sized thumbnail (long edge ~768)
        final thumb = await asset.thumbnailDataWithSize(
          const ThumbnailSize(768, 768),
          quality: 80,
        );
        if (thumb == null) {
          setState(() => _autoscanProgress++);
          continue;
        }

        // Write to a temp file and upload
        final tmp = File('${Directory.systemTemp.path}/${asset.id}.jpg');
        await tmp.writeAsBytes(thumb);

        final res = await ApiService.uploadImage(tmp, module: 'preview');
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            final data = json.decode(res.body);
            final tags = (data['tags'] as List?)?.cast<String>() ?? [];
            if (tags.isNotEmpty) {
              await prefs.setString(key, json.encode(tags));
              // also update in-memory map so UI refreshes immediately
              setState(() {
                photoTags[key] = tags;
                _autoscanSaved++;
              });
            }
          } catch (_) {}
        }

        // cleanup
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      } catch (e) {
        developer.log('Autoscan upload failed for asset ${asset.id}: $e');
      }

      setState(() => _autoscanProgress++);
    }

    await prefs.setInt(
      'last_autoscan_ms',
      DateTime.now().millisecondsSinceEpoch,
    );
    if (completed) {
      await prefs.setInt(
        'last_autoscan_ms',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    setState(() {
      _autoscanRunning = false;
      _autoscanProgress = 0;
      _autoscanTotal = 0;
    });

    // notify user (only if still mounted)
    if (!mounted) return;
    if (completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Autoscan complete — scanned ${assets.length}, saved $_autoscanSaved tags',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Autoscan canceled — progress $_autoscanProgress/${assets.length}, saved $_autoscanSaved tags',
          ),
        ),
      );
    }
  }

  Future<void> _startManualAutoScan() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photos permission is required for autoscan'),
            ),
          );
        }
        return;
      }
      // smaller sample for manual tests
      const manualLimit = 50;
      final albums = await PhotoManager.getAssetPathList(onlyAll: true);
      if (albums.isEmpty) return;
      final all = albums.first;
      final total = await all.assetCountAsync;
      final take = total < manualLimit ? total : manualLimit;
      final assets = await all.getAssetListRange(start: 0, end: take);
      await _runAutoScan(assets);
    } catch (e) {
      developer.log('Manual autoscan failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Manual autoscan failed: $e')));
      }
    }
  }

  Future<void> _loadAllImages() async {
    setState(() => loading = true);
    await _loadOrganizedImages();
    await _loadTags();
    developer.log('Total photos in gallery: ${imageUrls.length}');
    setState(() => loading = false);
  }

  void reload() => _loadAllImages();

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
        setState(() => imageUrls = urls);
        return;
      }
    } catch (e) {
      developer.log('Failed to load images: $e');
    }
    // If server returned nothing / failed, fall back to device-local photos
    await _loadDevicePhotos();
  }

  Future<void> _loadDevicePhotos() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        developer.log('Photo permission denied when loading device photos');
        setState(() => imageUrls = []);
        return;
      }

      final albums = await PhotoManager.getAssetPathList(onlyAll: true);
      if (albums.isEmpty) {
        setState(() => imageUrls = []);
        return;
      }
      final all = albums.first;
      final total = await all.assetCountAsync;
      // Avoid loading excessively many assets in the UI — cap at 500 for safety
      final cap = total < 500 ? total : 500;
      final assets = await all.getAssetListRange(start: 0, end: cap);

      final urls = <String>[];
      _localAssets.clear();
      _thumbCache.clear();
      for (final a in assets) {
        final id = a.id;
        _localAssets[id] = a;
        // Use a special marker so builders can tell local assets from server URLs
        urls.add('local:$id');
      }

      setState(() => imageUrls = urls);
    } catch (e) {
      developer.log('Error loading device photos: $e');
      setState(() => imageUrls = []);
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
                Row(
                  children: [
                    if (tag.startsWith('premium:'))
                      const Icon(Icons.star, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tag: ${tag.startsWith('premium:') ? tag.replaceFirst('premium:', '') : tag}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    if (tag.startsWith('premium:'))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
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
                      leading: t.startsWith('premium:')
                          ? const Icon(Icons.star, color: Colors.amber)
                          : const Icon(Icons.label),
                      title: Text(
                        t.startsWith('premium:')
                            ? t.replaceFirst('premium:', '')
                            : t,
                      ),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Gallery Screen (fixed)',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
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
              tooltip: _forceDeviceView
                  ? 'Show device photos'
                  : 'Show server photos',
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
              icon: const Icon(Icons.cached, color: Colors.white),
              tooltip: 'Start Autoscan (manual)',
              onPressed: () => _startManualAutoScan(),
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
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Stack(
          children: [
            loading
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
                            ), // end InputDecoration
                          ), // end TextField
                        ), // end Padding
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
                                  final key = url.startsWith('local:')
                                      ? url.substring(6)
                                      : p.basename(url);
                                  final fullTags = photoTags[key] ?? [];
                                  // Only show tags <= 8 characters in the grid
                                  final shortTags = fullTags
                                      .where((t) => t.length <= 8)
                                      .toList();
                                  final visibleTags = shortTags
                                      .take(3)
                                      .toList();
                                  // No need to build manual tagChips here: the LayoutBuilder below will call
                                  // _buildTagChipsForWidth and render the visible / +N / None chips appropriately.

                                  final isSelected = _selectedKeys.contains(
                                    key,
                                  );
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
                                                        ConnectionState
                                                            .waiting) {
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
                                              : Image.network(
                                                  '${ApiService.baseUrl}$url',
                                                  fit: BoxFit.cover,
                                                ),
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
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
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
                      ],
                    ),
                  ),
            if (_autoscanRunning)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Autoscan: $_autoscanProgress / $_autoscanTotal',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                // cancel the autoscan
                                setState(() {
                                  _autoscanRunning = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Autoscan cancel requested'),
                                  ),
                                );
                              },
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _autoscanTotal > 0
                              ? _autoscanProgress / _autoscanTotal
                              : null,
                          color: Colors.amber,
                          backgroundColor: Colors.white24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      // Bottom debug FAB removed: top AppBar icon toggles debug overlay now.
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
