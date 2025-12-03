import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key});

  @override
  State<AlbumScreen> createState() => AlbumScreenState();
}

class AlbumScreenState extends State<AlbumScreen> {
  Map<String, List<String>> albums = {};
  Map<String, List<String>> photoTags = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    _loadTags();
  }

  // Helper: build year-grouped widgets for an album's image list.
  List<Widget> _buildYearGroupedViews(List<String> imageUrls) {
    final Map<String, List<String>> byYear = {};
    final yearReg = RegExp(r'(19\d{2}|20\d{2})');
    for (final url in imageUrls) {
      final name = p.basename(url);
      final match = yearReg.firstMatch(name);
      final year = match?.group(0) ?? 'Unknown';
      byYear.putIfAbsent(year, () => []).add(url);
    }

    // Sort years newest-first where possible, Unknown last
    final years = byYear.keys.toList()
      ..sort((a, b) {
        if (a == 'Unknown') return 1;
        if (b == 'Unknown') return -1;
        return int.parse(b).compareTo(int.parse(a));
      });

    return years.map((year) {
      final items = byYear[year]!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Spacer(),
                Text(
                  '$year (${items.length})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, idx) {
                final url = items[idx];
                final tags = photoTags[p.basename(url)] ?? [];
                return Container(
                  width: 140,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    image: DecorationImage(
                      image: NetworkImage('${ApiService.baseUrl}$url'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Wrap(
                        spacing: 2,
                        children: tags
                            .map(
                              (tag) => Chip(
                                label: Text(
                                  tag,
                                  style: const TextStyle(fontSize: 8),
                                ),
                                backgroundColor: Colors.black.withAlpha(178),
                                labelStyle: const TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }).toList();
  }

  Future<void> _loadAlbums() async {
    setState(() => loading = true);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? albumsJson = prefs.getString('albums');
    if (albumsJson != null) {
      Map<String, dynamic> albumsMap = json.decode(albumsJson);
      setState(() {
        albums = albumsMap.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      });
      setState(() => loading = false);
      return;
    }

    // Fallback: discover per-album keys with `album_` prefix and load them
    Set<String> keys = prefs.getKeys();
    Map<String, List<String>> discovered = {};
    for (var key in keys) {
      if (key.startsWith('album_')) {
        final name = key.substring('album_'.length);
        final albumJson = prefs.getString(key);
        if (albumJson != null) {
          try {
            discovered[name] = (json.decode(albumJson) as List).cast<String>();
          } catch (_) {}
        }
      }
    }
    if (discovered.isNotEmpty) {
      setState(() {
        albums = discovered;
      });
    }
    setState(() {
      loading = false;
    });
  }

  /// Public reload API used by HomeScreen to refresh albums when tab is selected
  void reload() {
    _loadAlbums();
    _loadTags();
  }

  Future<void> _loadTags() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Set<String> keys = prefs.getKeys();
    for (var key in keys) {
      if (key != 'albums') {
        final dynamic value = prefs.get(key);
        if (value is String) {
          try {
            final List<dynamic> tagsList = json.decode(value);
            photoTags[key] = tagsList.cast<String>();
          } catch (_) {}
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Album Screen',
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
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: loading
            ? Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).appBarTheme.foregroundColor,
                ),
              )
            : albums.isEmpty
            ? Center(
                child: Text(
                  'No albums created yet.\nCreate albums from tags in Gallery.',
                  style: TextStyle(
                    color: Theme.of(context).appBarTheme.foregroundColor,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  String albumName = albums.keys.elementAt(index);
                  List<String> imageUrls = albums[albumName]!;
                  return Card(
                    // Use themed card color so dark mode matches the rest of the app
                    color: Theme.of(context).cardColor,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ExpansionTile(
                      title: Text(
                        albumName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${imageUrls.length} photos',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      children: [
                        // Group images by year extracted from filename (best-effort).
                        // This is a lightweight frontend-only grouping that avoids
                        // adding platform dependencies. Filenames containing a
                        // 4-digit year (19xx or 20xx) will be grouped accordingly.
                        ..._buildYearGroupedViews(imageUrls),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
