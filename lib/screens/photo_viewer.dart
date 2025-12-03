import 'dart:io';

import 'package:flutter/material.dart';

/// Fullscreen photo viewer with pinch-zoom using [InteractiveViewer].
/// Accepts either a file path (`filePath`) or a network URL (`networkUrl`).
class PhotoViewer extends StatelessWidget {
  final String? filePath;
  final String? networkUrl;
  final String heroTag;

  const PhotoViewer({
    super.key,
    this.filePath,
    this.networkUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (filePath != null) {
      content = Image.file(File(filePath!), fit: BoxFit.contain);
    } else if (networkUrl != null) {
      content = Image.network(networkUrl!, fit: BoxFit.contain);
    } else {
      content = const Center(child: Icon(Icons.broken_image, size: 64));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 1.0,
            maxScale: 5.0,
            child: content,
          ),
        ),
      ),
    );
  }
}
