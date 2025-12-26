// Allow using BuildContext after async gaps in this file where we've
// guarded usage tightly or used localContext. Suppress the lint to keep
// the code straightforward for the current UX changes.
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:developer' as developer;
import 'gallery_screen.dart';
import 'settings_screen.dart';
import 'album_screen.dart';
import 'search_screen.dart';

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
        onSearchChanged: () {
          setState(() {}); // Rebuild to show/hide + button
        },
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

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 80,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(20),
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          border: Border.all(
            color: isSelected
                ? (widget.isDarkMode
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.2))
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Colors.orange.shade400
                    : (widget.isDarkMode
                          ? Colors.white.withValues(alpha: 0.85)
                          : Colors.black87.withValues(alpha: 0.85)),
                size: 22,
                shadows: widget.isDarkMode
                    ? (isSelected
                          ? [
                              const Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ]
                          : [
                              const Shadow(
                                color: Colors.black38,
                                offset: Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ])
                    : null,
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.orange.shade400
                      : (widget.isDarkMode
                            ? Colors.white.withValues(alpha: 0.85)
                            : Colors.black87.withValues(alpha: 0.85)),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  shadows: widget.isDarkMode
                      ? [
                          const Shadow(
                            color: Colors.black54,
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Sparks-by-album flow moved into the Gallery screen.

  @override
  Widget build(BuildContext context) {
    // Update system UI colors on every build to maintain correct appearance
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: widget.isDarkMode
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: widget.isDarkMode
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: widget.isDarkMode
            ? Colors.black.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.85),
        systemNavigationBarIconBrightness: widget.isDarkMode
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          IndexedStack(index: _selectedIndex, children: _screens),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isDarkMode
                        ? Colors.black.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.85),
                    border: Border(
                      top: BorderSide(
                        color: widget.isDarkMode
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.1),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: SafeArea(top: false, child: Container(height: 48)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 1, left: 6, right: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.folder_outlined, 'Gallery'),
                  _buildNavItem(1, Icons.photo_album_outlined, 'Albums'),
                ],
              ),
            ),
          ),
          // Floating + button (add more filters) - shows when filters are active
          if (_selectedIndex == 0 &&
              (_galleryKey.currentState?.searchQuery ?? '').isNotEmpty)
            Positioned(
              right: 24,
              bottom: 176 + MediaQuery.of(context).padding.bottom,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.lightBlue.shade300,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    // Get actual current tags from loaded photos
                    final currentTags =
                        _galleryKey.currentState?.getAllCurrentTags() ??
                        <String>{};
                    final availableTags = currentTags.toList()..sort();

                    // Debug: log what tags we're passing
                    developer.log('Available tags for search: $availableTags');

                    // Get current search terms to exclude already selected tags
                    final currentSearch =
                        _galleryKey.currentState?.searchQuery ?? '';
                    final existingTags = currentSearch
                        .split(' ')
                        .where((t) => t.isNotEmpty)
                        .toSet();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SearchScreen(
                          recommendedTags: availableTags,
                          excludeTags: existingTags,
                          onTagSelected: (tag) {
                            // Append to existing search
                            if (_selectedIndex == 0) {
                              final newSearch = currentSearch.isEmpty
                                  ? tag
                                  : '$currentSearch $tag';
                              _galleryKey.currentState?.searchByTag(newSearch);
                            }
                          },
                        ),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.add,
                    color: widget.isDarkMode
                        ? Colors.grey.shade900
                        : Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          // Floating search button
          Positioned(
            right: 16,
            bottom: 135,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isDarkMode ? Colors.grey.shade900 : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  Icons.search,
                  color: widget.isDarkMode
                      ? Colors.lightBlue.shade300
                      : Colors.blue.shade700,
                  size: 28,
                ),
                onPressed: () {
                  // Get actual tags from photos
                  final currentTags =
                      _galleryKey.currentState?.getAllCurrentTags() ??
                      <String>{};
                  final availableTags = currentTags.toList()..sort();

                  // Open search screen with actual photo tags
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SearchScreen(
                        recommendedTags: availableTags,
                        onTagSelected: (tag) {
                          // Apply search filter in gallery
                          if (_selectedIndex == 0) {
                            _galleryKey.currentState?.searchByTag(tag);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
