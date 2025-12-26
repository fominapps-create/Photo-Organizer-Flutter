import 'package:flutter/material.dart';
import 'dart:io';
import '../services/trash_store.dart';
import 'dart:developer' as developer;

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _trashItems = [];
  bool _loading = true;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _loading = true);
    final trash = await TrashStore.getTrash();
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

  Future<void> _restoreSelected() async {
    if (_selectedPaths.isEmpty) return;

    final count = _selectedPaths.length;
    for (final path in _selectedPaths) {
      await TrashStore.restore(path);
    }

    setState(() => _selectedPaths.clear());
    await _loadTrash();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored $count photo${count > 1 ? 's' : ''}')),
      );
    }
  }

  Future<void> _deleteSelectedPermanently() async {
    if (_selectedPaths.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently Delete?'),
        content: Text(
          'Permanently delete ${_selectedPaths.length} photo${_selectedPaths.length > 1 ? 's' : ''}? This cannot be undone.',
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

    final count = _selectedPaths.length;
    for (final path in _selectedPaths) {
      await TrashStore.permanentlyDelete(path);
      // Actually delete the file
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          developer.log('🗑️ Deleted file: $path');
        }
      } catch (e) {
        developer.log('❌ Error deleting file: $e');
      }
    }

    setState(() => _selectedPaths.clear());
    await _loadTrash();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Permanently deleted $count photo${count > 1 ? 's' : ''}',
          ),
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

    // Delete all files
    for (final item in _trashItems) {
      final path = item['path'] as String;
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          developer.log('🗑️ Deleted file: $path');
        }
      } catch (e) {
        developer.log('❌ Error deleting file: $e');
      }
    }

    await TrashStore.emptyTrash();
    await _loadTrash();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trash emptied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
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
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Deleted photos appear here for 30 days',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: _trashItems.length,
              itemBuilder: (context, index) {
                final item = _trashItems[index];
                final path = item['path'] as String;
                final isSelected = _selectedPaths.contains(path);
                final daysLeft = _formatDaysRemaining(
                  item['deletedAt'] as String,
                );

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedPaths.remove(path);
                      } else {
                        _selectedPaths.add(path);
                      }
                    });
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                          ),
                        ),
                      ),
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
      bottomNavigationBar: _selectedPaths.isNotEmpty
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
                        '${_selectedPaths.length} selected',
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
}
