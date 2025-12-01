import 'dart:io';
//import 'dart:typed_data';
//import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class FileService {
  static final List<String> imageExtensions = ['.jpg', '.jpeg', '.png', '.gif'];

  static Future<List<dynamic>> pickFilesOrFolder({required bool isWeb}) async {
    List<dynamic> files = [];

    if (isWeb) {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: imageExtensions,
        withData: true,
      );
      if (result != null) {
        files = result.files
            .where((f) => f.bytes != null)
            .map((f) => f.bytes!)
            .toList();
      }
    } else {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        final dir = Directory(selectedDirectory);
        final allFiles = dir.listSync(recursive: true);
        files = allFiles.whereType<File>().where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return imageExtensions.contains(ext);
        }).toList();
      }
    }

    return files;
  }
}
