import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class CustomImagePicker extends StatefulWidget {
  const CustomImagePicker({super.key});

  @override
  State<CustomImagePicker> createState() => _CustomImagePickerState();
}

class _CustomImagePickerState extends State<CustomImagePicker> {
  List<AssetEntity> _mediaList = [];
  Set<AssetEntity> _selectedMedia = {};
  bool _loading = true;
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final permitted = await PhotoManager.requestPermissionExtend();

    // Check if we have limited access (some photos selected)
    if (permitted.isAuth || permitted == PermissionState.limited) {
      // Permission granted or limited access - continue loading
    } else {
      if (!mounted) return;

      // Show dialog to open settings
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission Required'),
          content: Text(
            'Photo access: ${permitted.name}\nThis app needs access to your photos. Please grant permission in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await PhotoManager.openSetting();
        // After returning from settings, check permission again
        if (!mounted) return;
        final newPermission = await PhotoManager.requestPermissionExtend();
        if (newPermission.isAuth || newPermission == PermissionState.limited) {
          // Permission granted, reload photos
          _loadPhotos();
          return;
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final recentAlbum = albums.first;
    final media = await recentAlbum.getAssetListRange(start: 0, end: 1000);

    setState(() {
      _mediaList = media;
      _loading = false;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedMedia = Set.from(_mediaList);
      } else {
        _selectedMedia.clear();
      }
    });
  }

  void _setSelectAll() {
    setState(() {
      _selectedMedia = Set.from(_mediaList);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMedia.clear();
    });
  }

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      if (_selectedMedia.contains(asset)) {
        _selectedMedia.remove(asset);
      } else {
        _selectedMedia.add(asset);
      }
      _selectAll = _selectedMedia.length == _mediaList.length;
    });
  }

  Future<void> _previewImage(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(child: InteractiveViewer(child: Image.file(file))),
        ),
      ),
    );
  }

  Future<void> _confirmSelection() async {
    if (_selectedMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one image')),
      );
      return;
    }

    // Convert selected assets to File objects
    final files = <File>[];
    for (final asset in _selectedMedia) {
      final file = await asset.file;
      if (file != null) {
        files.add(file);
      }
    }

    if (!mounted) return;
    Navigator.pop(context, files);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu),
          onSelected: (value) {
            switch (value) {
              case 'select_all':
                _setSelectAll();
                break;
              case 'clear_selection':
                _clearSelection();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'select_all', child: Text('Select All')),
            const PopupMenuItem(
              value: 'clear_selection',
              child: Text('Clear Selection'),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Custom Image Picker',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
        title: Text(
          _selectedMedia.isEmpty
              ? 'Select Photos'
              : '${_selectedMedia.length} selected',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton.icon(
            onPressed: _toggleSelectAll,
            icon: Icon(
              _selectAll ? Icons.check_box : Icons.check_box_outline_blank,
              color: Colors.blue,
            ),
            label: const Text(
              'Select All',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mediaList.isEmpty
          ? const Center(child: Text('No images found'))
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: _mediaList.length,
              itemBuilder: (context, index) {
                final asset = _mediaList[index];
                final isSelected = _selectedMedia.contains(asset);

                return GestureDetector(
                  onTap: () => _toggleSelection(asset),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<Uint8List?>(
                        future: asset.thumbnailDataWithSize(
                          const ThumbnailSize(200, 200),
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              snapshot.hasData) {
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                            );
                          }
                          return Container(color: Colors.grey[300]);
                        },
                      ),
                      if (isSelected)
                        Container(color: Colors.blue.withAlpha(77)),
                      // Checkbox overlay in top-left corner
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.white,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(77),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : null,
                        ),
                      ),
                      // Preview button in bottom-right corner
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _previewImage(asset),
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(102),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.fullscreen,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: _selectedMedia.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(26),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: _confirmSelection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B025),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Done (${_selectedMedia.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
