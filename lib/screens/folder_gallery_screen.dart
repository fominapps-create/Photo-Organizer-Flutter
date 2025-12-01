// Folder-based Gallery screen.
// Shows device albums (via `photo_manager`) when available,
// otherwise falls back to `SharedPreferences`-saved albums (for emulator/dev testing).
// Provides a small developer helper to populate sample albums from bundled assets.
// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:photo_manager/photo_manager.dart';
import '../utils/app_colors.dart';

import '../services/api_service.dart';
import '../services/network_utils.dart';
import '../services/settings_utils.dart';
import 'organize_progress_screen.dart';

class FolderGalleryScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;
  final VoidCallback? onFolderSelected;

  const FolderGalleryScreen({
    super.key,
    this.onSettingsTap,
    this.onFolderSelected,
  });

  @override
  FolderGalleryScreenState createState() => FolderGalleryScreenState();
}

class FolderGalleryScreenState extends State<FolderGalleryScreen>
    with WidgetsBindingObserver {
  bool? _serverOnline;
  DateTime? _lastServerCheck;
  bool _serverChecking = false;

  Map<String, List<String>> albums = {};
  Map<String, List<String>> photoTags = {};
  // In-memory device-scan results (AssetEntity per album)
  Map<String, List<AssetEntity>> localAlbums = {};
  bool _loadingAlbums = true;
  // UI selection state for organizing folders (only for persisted `albums`)
  final Set<String> _selectedAlbums = {};
  bool _organizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkServer();
    _initializeOnStart();
  }

  // Perform startup steps in order: run device scan first so device
  // photos appear immediately, then load any SharedPreferences fallback.
  Future<void> _initializeOnStart() async {
    if (!mounted) {
      return;
    }
    setState(() => _loadingAlbums = true);
    try {
      // Remove any developer/sample `albums` entry so it doesn't
      // override or appear before device scan results.
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey('albums')) {
          await prefs.remove('albums');
        }
        // As a fallback on emulators where MediaStore/photo_manager may
        // not report albums reliably, detect files under /sdcard/Pictures
        // and immediately use them (and persist them) so the UI shows the
        // emulator photos right away.
        try {
          final pics = await _discoverPicturesFromFs();
          if (pics.isNotEmpty) {
            // Try to discover per-folder albums (Camera, WhatsApp, Downloads,
            // Screenshots, etc.). Prefer per-folder mapping when available so
            // the UI shows discrete folders rather than a single aggregated
            // "Device Pictures" entry on emulators.
            final per = await _discoverPicturesPerFolderFromFs();
            if (per.isNotEmpty) {
              // Do NOT persist filesystem-detected albums. These are a
              // temporary, in-memory fallback so the Gallery shows images
              // immediately on emulators. Persisted `albums` should only
              // contain user-created albums.
              if (mounted) {
                setState(() => albums = per);
              }
            } else {
              // Use aggregated in-memory fallback if per-folder not found.
              if (mounted) {
                setState(() => albums = {'Device Pictures': pics});
              }
            }
            // We keep going to run a real device scan so photo_manager can
            // still populate `localAlbums` when permissions and MediaStore
            // are available.
          }
        } catch (_) {}
      } catch (_) {}

      await _startScanIfNeeded();
      await _loadAlbums();
      // If we discovered device albums, show a brief SnackBar so the user
      // knows the scan ran and photos should be visible immediately.
      if (mounted && localAlbums.isNotEmpty) {
        final total = localAlbums.values.fold<int>(0, (p, e) => p + e.length);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Found $total device photos')));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAlbums = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When the app returns to the foreground, refresh server status
      // and re-run the device scan / reload persisted albums so the
      // gallery always reflects current device storage contents.
      _checkServer();
      _startScanIfNeeded();
      _loadAlbums();
    }
  }

  Future<void> _checkServer() async {
    if (!mounted) {
      return;
    }
    setState(() => _serverChecking = true);
    final ok = await ApiService.pingServer();
    if (!mounted) {
      return;
    }
    setState(() {
      _serverOnline = ok;
      _lastServerCheck = DateTime.now();
      _serverChecking = false;
    });
  }

  Future<void> _startScanIfNeeded() async {
    if (!mounted) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // During development/testing we default to false so emulator scans run
      // even when Wi‑Fi isn't available. In production this should remain true.
      final scanOnly = prefs.getBool('scan_on_wifi_only') ?? false;
      if (scanOnly && !(await NetworkUtils.isOnWifi())) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No Wi‑Fi detected'),
            content: const Text(
              "You're about to scan the device without Wi‑Fi; we suggest you turn it on.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'turn_on'),
                child: const Text('Turn on'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'scan_anyway'),
                child: const Text('Scan anyway'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );

        if (choice == 'turn_on') {
          await SettingsUtils.openWifiSettings();
          return;
        }

        if (choice != 'scan_anyway') {
          return;
        }
      }

      // Try to perform a real device scan using photo_manager
      final granted = await _scanDeviceAlbums();
      if (!granted) {
        // fallback to previous placeholder behavior
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan complete (placeholder)')),
        );
        await _loadAlbums();
      }
    } catch (_) {}
  }

  // Returns true if a real scan ran (permission granted and albums populated)
  Future<bool> _scanDeviceAlbums() async {
    try {
      final result = await PhotoManager.requestPermissionExtend();
      if (!result.isAuth) {
        return false;
      }

      // Prepare discovered map.
      final Map<String, List<AssetEntity>> discovered = {};

      // request image-only paths (albums)
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
      );

      // Also request the 'All' album explicitly to ensure we pick up
      // device images even if per-folder albums are empty or unavailable.
      try {
        final allList = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          onlyAll: true,
        );
        if (allList.isNotEmpty) {
          final allPath = allList.first;
          final totalAll = await allPath.assetCountAsync;
          final endAll = totalAll > 200 ? 200 : totalAll;
          final itemsAll = await allPath.getAssetListRange(
            start: 0,
            end: endAll,
          );
          if (itemsAll.isNotEmpty) {
            discovered[allPath.name.isNotEmpty ? allPath.name : 'All Photos'] =
                itemsAll;
            // ignore: avoid_print
            print(
              'DBG: album=${allPath.name} total=$totalAll loaded=${itemsAll.length} (all)',
            );
          }
        }
      } catch (_) {}
      for (final p in paths) {
        final total = await p.assetCountAsync;
        // Debug log helpful during testing
        // ignore: avoid_print
        print('DBG: album=${p.name} total=$total');
        final end = total > 50 ? 50 : total;
        final list = await p.getAssetListRange(start: 0, end: end);
        // ignore: avoid_print
        print('DBG: album=${p.name} loaded=${list.length}');
        if (list.isNotEmpty) {
          discovered[p.name] = list;
        }
      }

      if (mounted) {
        setState(() => localAlbums = discovered);
      }
      return discovered.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadAlbums() async {
    setState(() => _loadingAlbums = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final albumsJson = prefs.getString('albums');
      if (albumsJson != null) {
        final Map<String, dynamic> map = json.decode(albumsJson);
        albums = map.map((k, v) => MapEntry(k, List<String>.from(v)));
      } else {
        // discover per-album keys
        final keys = prefs.getKeys();
        final Map<String, List<String>> discovered = {};
        for (final k in keys) {
          if (k.startsWith('album_')) {
            try {
              final name = k.substring('album_'.length);
              final v = prefs.getString(k);
              if (v != null) {
                discovered[name] = (json.decode(v) as List).cast<String>();
              }
            } catch (_) {}
          }
        }
        if (discovered.isNotEmpty) albums = discovered;
      }

      // Load tags for album items
      final prefs2 = await SharedPreferences.getInstance();
      final keys2 = prefs2.getKeys();
      final Map<String, List<String>> tags = {};
      for (final key in keys2) {
        if (key == 'albums') {
          continue;
        }
        final v = prefs2.getString(key);
        if (v != null) {
          try {
            tags[key] = (json.decode(v) as List).cast<String>();
          } catch (_) {}
        }
      }
      photoTags = tags;
    } catch (_) {}
    // If no SharedPreferences albums and no photo_manager localAlbums,
    // try a filesystem fallback (emulator /sdcard/Pictures) so the app
    // shows device photos immediately on emulators where MediaStore
    // or permissions may be flaky.
    try {
      if (localAlbums.isEmpty && albums.isEmpty && Platform.isAndroid) {
        final pics = await _discoverPicturesFromFs();
        if (pics.isNotEmpty) {
          albums = {'Device Pictures': pics};
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loadingAlbums = false);
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

  // Discover images per common device folders so we can present
  // distinct album names (Camera, WhatsApp, Download, Screenshots)
  // when `photo_manager`/MediaStore doesn't enumerate them on emulators.
  Future<Map<String, List<String>>> _discoverPicturesPerFolderFromFs() async {
    final Map<String, List<String>> found = {};
    final candidates = <Map<String, String>>[
      {'path': '/sdcard/DCIM/Camera', 'name': 'Camera'},
      {'path': '/sdcard/Pictures/WhatsApp', 'name': 'WhatsApp'},
      {'path': '/sdcard/Download', 'name': 'Downloads'},
      {'path': '/sdcard/Pictures/Screenshots', 'name': 'Screenshots'},
      {'path': '/sdcard/Pictures', 'name': 'Pictures'},
    ];

    for (final c in candidates) {
      try {
        final dir = Directory(c['path']!);
        if (!await dir.exists()) continue;
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
        if (images.isNotEmpty) {
          found[c['name']!] = images;
        }
      } catch (_) {}
    }

    return found;
  }

  Widget _buildAssetThumb(AssetEntity asset, List<String> tags) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(400, 400)),
            builder: (context, snap) {
              if (snap.hasData && snap.data != null) {
                return Image.memory(snap.data!, fit: BoxFit.cover);
              }
              return Container(color: Colors.grey.shade300);
            },
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 2,
                children: tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 8)),
                        backgroundColor: Colors.black.withAlpha(178),
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Manual organize dialog removed — organization now runs through
  // the Sparks flow which navigates to `OrganizeProgressScreen`.

  /// Show category picker used by the Sparks flow.
  /// Returns null if cancelled, otherwise a map with keys `categories` (a list of strings) and `cap` (int).
  Future<Map<String, dynamic>?> _showCategoryPicker() async {
    if (!mounted) return null;
    final topics = ['People', 'Pets', 'Scenery', 'Documents'];
    final selected = <String>{};
    // selection for per-run cap (preset choices so users don't type)
    final capOptions = [50, 100, 200, 300, 500];
    int selectedCap = 300;
    // per-category estimated processing times (ms) — conservative client-side estimates
    final estimates = {
      'People': 800,
      'Pets': 700,
      'Scenery': 600,
      'Documents': 500,
    };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Select Categories'),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose one or more categories to organize into',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Per-run cap:'),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: selectedCap,
                          items: capOptions
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text('$c'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => selectedCap = v ?? selectedCap),
                        ),
                        const SizedBox(width: 8),
                        const Text('images'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (ctx) {
                        final cap = selectedCap;
                        // Assume each selected category's module will process every image
                        // so total per-image cost is the sum of selected module costs.
                        final totalPerImageMs = selected.isEmpty
                            ? (estimates.values.reduce((a, b) => a + b))
                            : (selected
                                  .map((s) => estimates[s] ?? 600)
                                  .reduce((a, b) => a + b));
                        final estTimeMs = (totalPerImageMs * cap).round();
                        final estMinutes = estTimeMs <= 0
                            ? 0.0
                            : (estTimeMs / 60000.0);
                        final estText = estMinutes <= 0
                            ? '—'
                            : '${estMinutes.toStringAsFixed(1)} min (est for $cap)';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text('Estimated run time: $estText'),
                        );
                      },
                    ),
                    ListTile(
                      title: const Text('All'),
                      leading: Icon(
                        selected.length == topics.length
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: selected.length == topics.length
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onTap: () => setState(() {
                        if (selected.length == topics.length) {
                          selected.clear();
                        } else {
                          selected.addAll(topics);
                        }
                      }),
                    ),
                    const SizedBox(height: 6),
                    ...topics.map((t) {
                      final sel = selected.contains(t);
                      return CheckboxListTile(
                        value: sel,
                        title: Text(t),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selected.add(t);
                          } else {
                            selected.remove(t);
                          }
                        }),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx, {
                          'categories': selected.toList(),
                          'cap': selectedCap,
                        });
                      },
                child: const Text('Start'),
              ),
            ],
          );
        },
      ),
    );

    return result;
  }

  // Direct organization helper removed; use the organized flow implemented
  // in `OrganizeProgressScreen` which handles batching, measurement and
  // persistence of user-created albums.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Menu', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('Server'),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                _serverOnline == true ? Icons.cloud_done : Icons.cloud_off,
                color: _serverOnline == true
                    ? Colors.green
                    : Colors.grey.shade600,
              ),
              title: Text(
                _serverOnline == null
                    ? 'Server: Unknown'
                    : _serverOnline == true
                    ? 'Server: Online'
                    : 'Server: Offline',
              ),
              subtitle: _lastServerCheck != null
                  ? Text('Last checked: ${_lastServerCheck!.toLocal()}')
                  : null,
              trailing: IconButton(
                icon: _serverChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _serverChecking ? null : _checkServer,
              ),
            ),
            // Manual scan removed: scanning now runs automatically on
            // startup and whenever the app is resumed. The developer
            // manual scan button was intentionally removed per UX request.
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                widget.onSettingsTap?.call();
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('Gallery'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Folder Gallery Screen',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Show inline organizing progress when the organize flow is active.
            if (_organizing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: const [
                    LinearProgressIndicator(),
                    SizedBox(height: 6),
                    Text(
                      'Organizing and scanning tags…',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Builder(
                builder: (ctx) {
                  if (_loadingAlbums) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (localAlbums.isEmpty && albums.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            'Scanning device for photo folders...',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'This runs automatically on app start; give it a moment.',
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 20),
                          SizedBox(height: 12),
                          SizedBox(height: 12),
                        ],
                      ),
                    );
                  }

                  // Default: show albums list
                  return ListView.builder(
                    itemCount: (localAlbums.isNotEmpty
                        ? localAlbums.length
                        : albums.length),
                    itemBuilder: (context, index) {
                      final bool useLocal = localAlbums.isNotEmpty;
                      final name = useLocal
                          ? localAlbums.keys.elementAt(index)
                          : albums.keys.elementAt(index);

                      if (useLocal) {
                        final items = localAlbums[name]!;
                        return Card(
                          child: ExpansionTile(
                            leading: Tooltip(
                              message:
                                  'Organize not available for live device albums',
                              child: Checkbox(value: false, onChanged: null),
                            ),
                            initiallyExpanded: index == 0,
                            title: Text(name),
                            subtitle: Text('${items.length} photos'),
                            children: items.isEmpty
                                ? [const ListTile(title: Text('No photos'))]
                                : [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              childAspectRatio: 1,
                                            ),
                                        itemCount: items.length,
                                        itemBuilder: (ctx2, idx) {
                                          final asset = items[idx];
                                          final tags =
                                              photoTags[asset.id] ?? [];
                                          return Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: _buildAssetThumb(
                                              asset,
                                              tags,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                          ),
                        );
                      } else {
                        final items = albums[name]!;
                        return Card(
                          child: ExpansionTile(
                            leading: Checkbox(
                              value: _selectedAlbums.contains(name),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedAlbums.add(name);
                                  } else {
                                    _selectedAlbums.remove(name);
                                  }
                                });
                              },
                            ),
                            initiallyExpanded: index == 0,
                            title: Text(name),
                            subtitle: Text('${items.length} photos'),
                            children: items.isEmpty
                                ? [const ListTile(title: Text('No photos'))]
                                : [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              childAspectRatio: 1,
                                            ),
                                        itemCount: items.length,
                                        itemBuilder: (ctx2, idx) {
                                          final url = items[idx];
                                          final tags = photoTags[url] ?? [];
                                          Widget imageWidget;
                                          if (url.startsWith('asset:')) {
                                            final assetPath = url.substring(
                                              'asset:'.length,
                                            );
                                            imageWidget = ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.asset(
                                                assetPath,
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          } else if (url.startsWith('file:')) {
                                            final path = url.substring(
                                              'file:'.length,
                                            );
                                            imageWidget = ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.file(
                                                File(path),
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          } else {
                                            imageWidget = ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.network(
                                                ApiService.resolveImageUrl(url),
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          }

                                          return Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Container(
                                                margin: const EdgeInsets.all(4),
                                                child: imageWidget,
                                              ),
                                              Align(
                                                alignment: Alignment.bottomLeft,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: Wrap(
                                                    spacing: 2,
                                                    children: tags
                                                        .map(
                                                          (tag) => Chip(
                                                            label: Text(
                                                              tag,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize: 8,
                                                                  ),
                                                            ),
                                                            backgroundColor:
                                                                Colors.black
                                                                    .withAlpha(
                                                                      178,
                                                                    ),
                                                            labelStyle:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                          ),
                                                        )
                                                        .toList(),
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
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _selectedAlbums.isEmpty
            ? null
            : (_organizing
                  ? null
                  : () async {
                      // Ask the user which categories to use for organizing
                      final pick = await _showCategoryPicker();
                      if (pick == null) return;
                      final categories = List<String>.from(
                        pick['categories'] ?? <String>[],
                      );
                      final cap = pick['cap'] as int? ?? 300;
                      if (categories.isEmpty) return;

                      // Gather all selected album item URLs
                      final prefs = await SharedPreferences.getInstance();
                      final Map<String, List<String>> current = Map.from(
                        albums,
                      );
                      final List<String> items = [];
                      for (final name in _selectedAlbums) {
                        if (current.containsKey(name)) {
                          items.addAll(current[name]!);
                        } else {
                          // fallback: try individual album_ pref
                          try {
                            final v = prefs.getString('album_$name');
                            if (v != null) {
                              items.addAll(
                                (json.decode(v) as List).cast<String>(),
                              );
                            }
                          } catch (_) {}
                        }
                      }

                      if (items.isEmpty) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No photos found in selected folders',
                            ),
                          ),
                        );
                        return;
                      }

                      // Navigate to progress screen to perform organization
                      setState(() => _organizing = true);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => OrganizeProgressScreen(
                            items: items,
                            categories: categories,
                            cap: cap,
                          ),
                        ),
                      );

                      // After returning, refresh albums and clear selection
                      await _loadAlbums();
                      setState(() {
                        _selectedAlbums.clear();
                        _organizing = false;
                      });
                    }),
        tooltip: _selectedAlbums.isEmpty
            ? 'Select folders to organize'
            : 'Organize selected folders',
        backgroundColor: _selectedAlbums.isEmpty
            ? Colors.grey
            : AppColors.sparkleDark,
        child: const Icon(Icons.auto_awesome),
      ),
    );
  }
}
