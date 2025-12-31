// Allow using BuildContext after async gaps in this file where we've
// guarded usage tightly or used localContext. Suppress the lint to keep
// the code straightforward for the current UX changes.
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:ui';
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
  final ValueNotifier<bool> _showNavBar = ValueNotifier<bool>(true);
  final ValueNotifier<int> _selectionCount = ValueNotifier<int>(0);

  late final List<Widget> _screens;

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          isDarkMode: widget.isDarkMode,
          onThemeChanged: widget.onThemeChanged,
          onTrashRestored: () {
            // Refresh gallery's trashed IDs when photos are restored from trash
            _galleryKey.currentState?.refreshTrashedIds();
          },
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
        showNavBar: _showNavBar,
        selectionCount: _selectionCount,
      ),
      AlbumScreen(key: _albumKey),
    ];

    // Request notification permission after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
  }

  /// Request permission for background scanning
  Future<void> _requestNotificationPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAsked = prefs.getBool('hasAskedBackgroundScan') ?? false;
    final backgroundScanEnabled =
        prefs.getBool('background_scan_enabled') ?? false;

    // Check current permission status
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();

    // If already granted and enabled, or we've asked before, skip
    if ((permission == NotificationPermission.granted &&
            backgroundScanEnabled) ||
        hasAsked) {
      return;
    }

    // Mark that we've asked
    await prefs.setBool('hasAskedBackgroundScan', true);

    if (!mounted) return;

    // Simple question about background scanning
    final wantsBackground = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Background Scanning'),
        content: const Text(
          'Continue scanning photos when the app is minimized?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (wantsBackground == true) {
      // Save preference then request system permission
      await prefs.setBool('background_scan_enabled', true);
      await FlutterForegroundTask.requestNotificationPermission();
    } else {
      await prefs.setBool('background_scan_enabled', false);
    }
  }

  @override
  void dispose() {
    _showNavBar.dispose();
    _selectionCount.dispose();
    super.dispose();
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

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 80,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: widget.isDarkMode
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.2),
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
                color: color,
                size: 18,
                shadows: widget.isDarkMode
                    ? [
                        const Shadow(
                          color: Colors.black26,
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ]
                    : null,
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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
          // Bottom blur background - animates height on scroll
          ValueListenableBuilder<bool>(
            valueListenable: _showNavBar,
            builder: (context, showNavBar, _) {
              return Positioned(
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
                      child: SafeArea(
                        top: false,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: showNavBar ? 48 : 0,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Nav items / Action buttons - switch based on selection
          ValueListenableBuilder<bool>(
            valueListenable: _showNavBar,
            builder: (context, showNavBar, _) {
              return ValueListenableBuilder<int>(
                valueListenable: _selectionCount,
                builder: (context, selectionCount, _) {
                  final hasSelection = selectionCount > 0;
                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: 48,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: showNavBar ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !showNavBar,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: 1,
                            left: 6,
                            right: 6,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: hasSelection
                                ? Row(
                                    key: const ValueKey('action_buttons'),
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildActionButton(
                                        Icons.photo_album,
                                        'Album',
                                        Colors.orange,
                                        () => _galleryKey.currentState
                                            ?.showAlbumOptions(),
                                      ),
                                      _buildActionButton(
                                        Icons.share,
                                        'Share',
                                        Colors.orange,
                                        () => _galleryKey.currentState
                                            ?.shareSelected(),
                                      ),
                                      _buildActionButton(
                                        Icons.delete,
                                        'Delete',
                                        Colors.orange,
                                        () => _galleryKey.currentState
                                            ?.deleteSelected(),
                                      ),
                                    ],
                                  )
                                : Row(
                                    key: const ValueKey('nav_buttons'),
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildNavItem(
                                        0,
                                        Icons.folder_outlined,
                                        'Gallery',
                                      ),
                                      _buildNavItem(
                                        1,
                                        Icons.photo_album_outlined,
                                        'Albums',
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
          ),
          // Floating Filto button - hides when scrolling
          ValueListenableBuilder<bool>(
            valueListenable: _showNavBar,
            builder: (context, showNavBar, child) {
              return Positioned(
                right: 16,
                bottom: 135,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  opacity: showNavBar ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !showNavBar,
                    child: GestureDetector(
                      onTap: () {
                        // Get tags sorted by popularity (most common first)
                        final suggestionsByPopularity =
                            _galleryKey.currentState?.getSearchSuggestions(
                              limit: 100,
                            ) ??
                            <String>[];

                        // Open search screen with tags sorted by popularity
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SearchScreen(
                              recommendedTags: suggestionsByPopularity,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Background button circle
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.isDarkMode
                                      ? Colors.grey.shade900
                                      : Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                              // Omni button icon on top
                              Image.asset(
                                'assets/omni-button.png',
                                width: 72,
                                height: 72,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
