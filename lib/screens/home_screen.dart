// Allow using BuildContext after async gaps in this file where we've
// guarded usage tightly or used localContext. Suppress the lint to keep
// the code straightforward for the current UX changes.
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'gallery_screen.dart';
import 'folder_gallery_screen.dart';
import 'settings_screen.dart';
import 'album_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const HomeScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final GlobalKey<FolderGalleryScreenState> _folderKey =
      GlobalKey<FolderGalleryScreenState>();
  final GlobalKey<GalleryScreenState> _galleryKey =
      GlobalKey<GalleryScreenState>();
  final GlobalKey<AlbumScreenState> _albumKey = GlobalKey<AlbumScreenState>();

  late final List<Widget> _screens;

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          isDarkMode: widget.isDarkMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Show the photo-based organized gallery as the default tab so the
    // device opens to populated photos instead of the folder list.
    _screens = [
      GalleryScreen(
        key: _galleryKey,
        onSettingsTap: _openSettings,
        onAlbumCreated: () {
          _albumKey.currentState?.reload();
        },
      ),
      FolderGalleryScreen(
        key: _folderKey,
        onFolderSelected: () {
          setState(() {});
          _galleryKey.currentState?.reload();
        },
        onSettingsTap: _openSettings,
      ),
      AlbumScreen(key: _albumKey),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 2) {
      _albumKey.currentState?.reload();
    }
  }

  // Sparks-by-album flow moved into the Gallery screen.

  @override
  Widget build(BuildContext context) {
    // (explorer state is accessible from the screens when needed)

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 20,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Text(
              'Home Screen',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        elevation: 0,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _onItemTapped(0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        color: _selectedIndex == 0
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Gallery',
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedIndex == 0
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          fontWeight: _selectedIndex == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _onItemTapped(1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedIndex == 1
                            ? Icons.photo_library
                            : Icons.photo_library_outlined,
                        color: _selectedIndex == 1
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Organized',
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedIndex == 1
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          fontWeight: _selectedIndex == 1
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _onItemTapped(2),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedIndex == 2
                            ? Icons.photo_album
                            : Icons.photo_album_outlined,
                        color: _selectedIndex == 2
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Albums',
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedIndex == 2
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          fontWeight: _selectedIndex == 2
                              ? FontWeight.bold
                              : FontWeight.normal,
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
    );
  }
}
