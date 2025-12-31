import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';
import '../services/trash_store.dart';
import '../utils/snackbar_helper.dart';
import 'dart:developer' as developer;

class TrashScreen extends StatefulWidget {
  final VoidCallback? onRestored;

  const TrashScreen({super.key, this.onRestored});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _trashItems = [];
  bool _loading = true;
  final Set<String> _selectedIds = {};
  String _dateFilter = 'all'; // 'all', 'today', 'week', 'month'

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _loading = true);
    final trash = await TrashStore.getTrash();
    // Sort by deletion date DESC (most recent first)
    trash.sort((a, b) {
      final aDate = DateTime.parse(a['deletedAt'] as String);
      final bDate = DateTime.parse(b['deletedAt'] as String);
      return bDate.compareTo(aDate); // Newest first
    });
    setState(() {
      _trashItems = trash;
      _loading = false;
    });
  }

  String _formatDaysRemaining(String deletedAtStr) {
    final deletedAt = DateTime.parse(deletedAtStr);
    final daysInTrash = DateTime.now().difference(deletedAt).inDays;
    final daysRemaining = 30 - daysInTrash;

    if (daysRemaining <= 0) return 'Expires today';
    if (daysRemaining == 1) return '1 day left';
    return '$daysRemaining days left';
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}K';
    }
    return count.toString();
  }

  Future<void> _restoreSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    for (final id in _selectedIds) {
      await TrashStore.restore(id);
    }

    setState(() => _selectedIds.clear());
    await _loadTrash();

    // Notify parent to refresh gallery
    widget.onRestored?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        createStyledSnackBar('Restored $count photo${count > 1 ? 's' : ''}'),
      );
    }
  }

  Future<void> _deleteSelectedPermanently() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently Delete?'),
        content: Text(
          'This will permanently delete ${_selectedIds.length} photo${_selectedIds.length > 1 ? 's' : ''}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final count = _selectedIds.length;
    for (final id in _selectedIds) {
      await TrashStore.permanentlyDelete(id);
      // Note: We don't delete physical files for local: URLs
      // Photos remain on device, we just remove trash tracking
    }

    setState(() => _selectedIds.clear());
    await _loadTrash();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        createStyledSnackBar(
          'Permanently deleted $count photo${count > 1 ? 's' : ''}',
        ),
      );
    }
  }

  Future<void> _emptyTrash() async {
    if (_trashItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: Text(
          'Permanently delete all ${_trashItems.length} photo${_trashItems.length > 1 ? 's' : ''} in trash? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // FIX #11: Delete all files using PhotoManager (works with MediaStore)
    final idsToDelete = <String>[];
    for (final item in _trashItems) {
      final id = item['id'] as String;
      // Extract the asset ID from 'local:XXXX' format
      if (id.startsWith('local:')) {
        idsToDelete.add(id.substring('local:'.length));
      }
    }

    if (idsToDelete.isNotEmpty) {
      try {
        // Request permanent deletion via PhotoManager
        final deletedIds = await PhotoManager.editor.deleteWithIds(idsToDelete);
        developer.log(
          '🗑️ Permanently deleted ${deletedIds.length} files via PhotoManager',
        );
      } catch (e) {
        developer.log('❌ Error deleting files via PhotoManager: $e');
      }
    }

    await TrashStore.emptyTrash();
    await _loadTrash();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(createStyledSnackBar('Trash emptied'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter trash items by date
    final now = DateTime.now();
    final filteredItems = _trashItems.where((item) {
      if (_dateFilter == 'all') return true;

      final deletedAt = DateTime.parse(item['deletedAt'] as String);
      final difference = now.difference(deletedAt);

      switch (_dateFilter) {
        case 'today':
          return difference.inHours < 24;
        case 'week':
          return difference.inDays < 7;
        case 'month':
          return difference.inDays < 30;
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trash'),
            if (_trashItems.isNotEmpty)
              Text(
                _dateFilter == 'all'
                    ? '${_formatCount(_trashItems.length)} photo${_trashItems.length > 1 ? 's' : ''}'
                    : 'Showing ${_formatCount(filteredItems.length)} of ${_formatCount(_trashItems.length)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if (_trashItems.isNotEmpty)
            TextButton.icon(
              onPressed: _emptyTrash,
              icon: const Icon(Icons.delete_forever, size: 20),
              label: const Text('Empty'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trashItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Trash is empty',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Date filter chips
                if (_trashItems.length > 10)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All', 'all', _trashItems.length),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'Today',
                            'today',
                            _trashItems.where((item) {
                              final deletedAt = DateTime.parse(
                                item['deletedAt'] as String,
                              );
                              return DateTime.now()
                                      .difference(deletedAt)
                                      .inHours <
                                  24;
                            }).length,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'This Week',
                            'week',
                            _trashItems.where((item) {
                              final deletedAt = DateTime.parse(
                                item['deletedAt'] as String,
                              );
                              return DateTime.now()
                                      .difference(deletedAt)
                                      .inDays <
                                  7;
                            }).length,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'This Month',
                            'month',
                            _trashItems.where((item) {
                              final deletedAt = DateTime.parse(
                                item['deletedAt'] as String,
                              );
                              return DateTime.now()
                                      .difference(deletedAt)
                                      .inDays <
                                  30;
                            }).length,
                          ),
                        ],
                      ),
                    ),
                  ),
                // Grid
                Expanded(
                  child: filteredItems.isEmpty
                      ? Center(
                          child: Text(
                            'No photos deleted ${_dateFilter == 'today'
                                ? 'today'
                                : _dateFilter == 'week'
                                ? 'this week'
                                : _dateFilter == 'month'
                                ? 'this month'
                                : ''}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 4,
                              ),
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final photoId = item['id'] as String;
                            final isSelected = _selectedIds.contains(photoId);
                            final daysLeft = _formatDaysRemaining(
                              item['deletedAt'] as String,
                            );

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIds.remove(photoId);
                                  } else {
                                    _selectedIds.add(photoId);
                                  }
                                });
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildThumbnail(photoId),
                                  if (isSelected)
                                    Container(
                                      color: Colors.blue.withValues(alpha: 0.5),
                                      child: const Center(
                                        child: Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.7),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                      child: Text(
                                        daysLeft,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedIds.length} selected',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _restoreSelected,
                      icon: const Icon(Icons.restore, size: 20),
                      label: const Text('Restore'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _deleteSelectedPermanently,
                      icon: const Icon(Icons.delete_forever, size: 20),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _dateFilter == value;
    return FilterChip(
      label: Text('$label (${_formatCount(count)})'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _dateFilter = value;
        });
      },
      backgroundColor: Colors.grey.shade200,
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue.shade700,
    );
  }

  /// Build thumbnail for trash item - handles both local: and file: URLs
  Widget _buildThumbnail(String photoId) {
    // For local: URLs, load from AssetEntity
    if (photoId.startsWith('local:')) {
      final assetId = photoId.substring(6); // Remove "local:" prefix
      return FutureBuilder<AssetEntity?>(
        future: AssetEntity.fromId(assetId),
        builder: (context, assetSnapshot) {
          if (assetSnapshot.connectionState == ConnectionState.waiting) {
            return Container(
              color: Colors.grey.shade300,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          if (!assetSnapshot.hasData || assetSnapshot.data == null) {
            return Container(
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          }

          final asset = assetSnapshot.data!;
          // Load thumbnail data
          return FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize.square(200),
            ),
            builder: (context, thumbSnapshot) {
              if (thumbSnapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  color: Colors.grey.shade300,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              if (!thumbSnapshot.hasData || thumbSnapshot.data == null) {
                return Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                );
              }

              return Image.memory(
                thumbSnapshot.data!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              );
            },
          );
        },
      );
    } else if (photoId.startsWith('file:')) {
      final path = photoId.substring(5); // Remove "file:" prefix
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } else {
      // Unknown format
      return Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.help_outline, color: Colors.grey),
      );
    }
  }
}
