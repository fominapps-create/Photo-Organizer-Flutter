import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'dart:io';

class OrganizeProgressScreen extends StatefulWidget {
  final List<String> items; // urls (file:, asset:, or network)
  final List<String> categories;
  final int cap;

  const OrganizeProgressScreen({
    super.key,
    required this.items,
    required this.categories,
    required this.cap,
  });

  @override
  State<OrganizeProgressScreen> createState() => _OrganizeProgressScreenState();
}

class _OrganizeProgressScreenState extends State<OrganizeProgressScreen> {
  double _progress = 0.0;
  bool _paused = false;
  bool _canceled = false;
  int _current = 0;
  late final int _total;
  final Map<String, List<String>> _result = {};
  StreamSubscription<void>? _workerSub;
  final Map<String, double> _moduleAvgMs = {};
  static const int _samplePerModule = 3;

  @override
  void initState() {
    super.initState();
    _total = widget.items.length;
    for (final c in widget.categories) {
      _result[c] = [];
    }
    // Kick off measurement after build, then ask user to confirm before processing
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndPrompt());
  }

  Future<void> _measureAndPrompt() async {
    // start measurement (no UI bound to a measuring flag)

    // For each category/module, attempt to upload up to _samplePerModule local files
    for (final module in widget.categories) {
      double totalMs = 0.0;
      int counted = 0;

      for (
        int i = 0;
        i < widget.items.length && counted < _samplePerModule;
        i++
      ) {
        final item = widget.items[i];
        if (!item.startsWith('file:')) continue; // only sample local files
        final path = item.substring('file:'.length);
        final file = File(path);
        if (!await file.exists()) continue;

        final start = DateTime.now();
        try {
          final photoID = 'file://$path';
          await ApiService.uploadImage(file, photoID: photoID, module: module);
          final dur = DateTime.now().difference(start).inMilliseconds;
          totalMs += dur;
          counted++;
          // small delay between samples
          await Future.delayed(const Duration(milliseconds: 120));
        } catch (_) {
          // ignore sample errors, continue
        }
      }

      if (counted > 0) {
        _moduleAvgMs[module] = totalMs / counted;
      }
    }

    // If we couldn't measure any module (no local files), leave _moduleAvgMs empty
    // measurement finished

    // Show confirmation dialog summarizing estimate and asking to proceed
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        // compute estimate based on measured averages or fallback to defaults
        double avgMsPerImage;
        if (_moduleAvgMs.isNotEmpty) {
          avgMsPerImage =
              _moduleAvgMs.values.reduce((a, b) => a + b) / _moduleAvgMs.length;
        } else {
          // fallback conservative defaults (same as client-side estimates)
          final fallback = {
            'People': 800.0,
            'Pets': 700.0,
            'Scenery': 600.0,
            'Documents': 500.0,
          };
          final selected = widget.categories;
          avgMsPerImage =
              selected
                  .map((s) => fallback[s] ?? 600.0)
                  .reduce((a, b) => a + b) /
              selected.length;
        }

        final cap = widget.cap > 0 && widget.cap < widget.items.length
            ? widget.cap
            : widget.items.length;
        final estMs = avgMsPerImage * cap;
        final estMin = estMs / 60000.0;

        return AlertDialog(
          title: const Text('Estimated run time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Categories: ${widget.categories.join(', ')}'),
              const SizedBox(height: 8),
              Text('Images to process: $cap'),
              const SizedBox(height: 8),
              Text('Estimated time: ${estMin.toStringAsFixed(1)} minutes'),
              const SizedBox(height: 8),
              if (_moduleAvgMs.isNotEmpty) ...[
                const Text('Measured per-module averages:'),
                const SizedBox(height: 6),
                ..._moduleAvgMs.entries.map(
                  (e) => Text(
                    '${e.key}: ${(e.value / 1000.0).toStringAsFixed(2)}s',
                  ),
                ),
              ] else ...[
                const Text(
                  'Could not measure (no local samples). Using conservative defaults.',
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      // start actual processing
      await _startProcessing();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _startProcessing() async {
    // Process up to cap items and assign each image to one of the selected categories.
    final totalToProcess = widget.cap > 0 && widget.cap < widget.items.length
        ? widget.cap
        : widget.items.length;
    for (int i = 0; i < totalToProcess; i++) {
      if (_canceled) break;

      // Wait while paused
      while (_paused && !_canceled) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (_canceled) break;

      final item = widget.items[i];
      final cat = widget.categories[i % widget.categories.length];
      if (!_result.containsKey(cat)) _result[cat] = [];

      // If item is a local file (file:/...), upload it to server with module=cat
      try {
        if (item.startsWith('file:')) {
          final path = item.substring('file:'.length);
          final file = File(path);
          if (await file.exists()) {
            final photoID = 'file://$path';
            final res = await ApiService.uploadImage(
              file,
              photoID: photoID,
              module: cat,
            );
            try {
              final body = json.decode(res.body) as Map<String, dynamic>;
              // prefer server-provided url if any
              if (body.containsKey('url') && body['url'] != null) {
                _result[cat]!.add(body['url'] as String);
              } else {
                _result[cat]!.add(item);
              }
            } catch (_) {
              _result[cat]!.add(item);
            }
          } else {
            _result[cat]!.add(item);
          }
        } else if (item.startsWith('asset:')) {
          // Bundled asset; add as-is
          _result[cat]!.add(item);
        } else {
          // Network or server path: add as-is (cannot re-upload)
          _result[cat]!.add(item);
        }
      } catch (e) {
        // on error, preserve original item
        _result[cat]!.add(item);
      }

      _current = i + 1;
      setState(() {
        _progress = _current / (_total == 0 ? 1 : _total);
      });

      // Throttle a bit so UI remains responsive
      await Future.delayed(const Duration(milliseconds: 120));
    }

    if (_canceled) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Organization cancelled')));
      Navigator.of(context).pop();
      return;
    }

    // Save results to SharedPreferences as user-created albums
    try {
      final prefs = await SharedPreferences.getInstance();
      // If there are leftover items (not processed because of cap), persist them
      if (widget.items.length > widget.cap) {
        final remaining = widget.items.sublist(widget.cap);
        try {
          final pendingJson = prefs.getString('organize_pending_jobs');
          List<dynamic> pending = pendingJson != null
              ? (json.decode(pendingJson) as List)
              : [];
          pending.add({
            'categories': widget.categories,
            'items': remaining,
            'created_at': DateTime.now().toIso8601String(),
          });
          await prefs.setString('organize_pending_jobs', json.encode(pending));
        } catch (_) {}
      }
      // Load existing albums map
      Map<String, dynamic> albumsMap = {};
      final albumsJson = prefs.getString('albums');
      if (albumsJson != null) {
        try {
          albumsMap = json.decode(albumsJson) as Map<String, dynamic>;
        } catch (_) {
          albumsMap = {};
        }
      }

      for (final entry in _result.entries) {
        if (entry.value.isEmpty) continue;
        final baseName = entry.key;
        String name = baseName;
        int suffix = 1;
        while (albumsMap.containsKey(name)) {
          name = '$baseName ($suffix)';
          suffix++;
        }
        // Save as album_<name> and include in central 'albums' map
        await prefs.setString('album_$name', json.encode(entry.value));
        albumsMap[name] = entry.value;
      }

      await prefs.setString('albums', json.encode(albumsMap));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Organization complete')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save organized albums')),
      );
      Navigator.of(context).pop();
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  void _cancel() {
    setState(() => _canceled = true);
  }

  @override
  void dispose() {
    _workerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizing photos'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // treat top-left close as cancel
            _cancel();
            Navigator.of(context).maybePop();
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Organize Progress Screen',
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Categories: ${widget.categories.join(', ')}'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).round()}% • $_current/$_total'),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _togglePause,
                    icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                    label: Text(_paused ? 'Resume' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    _cancel();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.categories.map((c) {
                    final list = _result[c] ?? [];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('$c: ${list.length}'),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
