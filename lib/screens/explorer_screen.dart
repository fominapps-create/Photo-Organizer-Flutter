// Allow using captured BuildContext after awaited calls in this file where
// we've carefully captured `localContext` and checked `mounted`.
// Ignoring the lint here keeps the code concise while retaining safety checks.
// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tag_store.dart';
import '../services/photo_id.dart';
import '../services/network_utils.dart';
import '../services/settings_utils.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart'; // adjust path if needed
import 'custom_image_picker.dart';

// Helper to get current memory usage (best effort, platform-dependent)
int _getCurrentMemoryMB() {
  try {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final info = ProcessInfo.currentRss;
      return (info / (1024 * 1024)).round();
    }
  } catch (_) {}
  return 0; // Return 0 if unable to get memory info
}

class ExplorerScreen extends StatefulWidget {
  final VoidCallback? onImagesChanged;
  final VoidCallback? onUploadStateChanged;
  final VoidCallback? onSettingsTap;

  const ExplorerScreen({
    super.key,
    this.onImagesChanged,
    this.onUploadStateChanged,
    this.onSettingsTap,
  });

  @override
  State<ExplorerScreen> createState() => ExplorerScreenState();
}

class ExplorerScreenState extends State<ExplorerScreen>
    with SingleTickerProviderStateMixin {
  String currentPath = 'No folder selected';
  List<File> images = [];
  List<String> imagePhotoIds = [];
  List<Uint8List> webImages = [];
  List<String> webImageNames = [];
  bool isLoading = false;
  double progress = 0.0;
  bool uploading = false;
  bool paused = false;
  double uploadProgress = 0.0;
  String serverStatus = 'Unknown';
  DateTime? lastServerCheck;
  bool cancelUpload = false;
  int lastProcessedIndex = -1;
  int totalImagesToLoad = 0;
  AnimationController? _animationController;
  Animation<double>? _shimmer;

  // Organize dialog selection saved per-upload
  String? _organizeTopic;
  String? _organizeScope;
  String? _organizeAlbum;

  @override
  Widget build(BuildContext context) {
    final hasImages = kIsWeb ? webImages.isNotEmpty : images.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onSettingsTap,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Explorer Screen',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    serverStatus == 'Reachable'
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    color: serverStatus == 'Reachable'
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _checkServer,
                    child: Text(
                      serverStatus,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          if (hasImages && !uploading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withAlpha(20),
              child: Row(
                children: [
                  Text(
                    '${kIsWeb ? webImages.length : images.length} photos selected',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      if (!mounted) return;
                      setState(() {
                        images.clear();
                        webImages.clear();
                        webImageNames.clear();
                        currentPath = 'No folder selected';
                        uploadProgress = 0.0;
                      });
                      widget.onImagesChanged?.call();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cleared selected images'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.cancel, color: Color(0xFFD32F2F)),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(color: Color(0xFFD32F2F)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (uploading || paused)
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withAlpha((0.6 * 255).round()),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Full-width green progress bar with shimmer
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fullWidth = constraints.maxWidth;
                      final filledWidth =
                          (uploadProgress.clamp(0.0, 1.0).toDouble()) *
                          fullWidth;
                      return Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withAlpha((0.14 * 255).round()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: filledWidth,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF2E7D32),
                                      Color(0xFF81C784),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            if (filledWidth > 12 && _shimmer != null)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                width: filledWidth,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: AnimatedBuilder(
                                    animation: _shimmer!,
                                    builder: (ctx, child) {
                                      final shimmerWidth = fullWidth * 0.22;
                                      final dx = _shimmer!.value * fullWidth;
                                      return Transform.translate(
                                        offset: Offset(dx, 0),
                                        child: Container(
                                          width: shimmerWidth,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.white.withAlpha(0),
                                                Colors.white.withAlpha(120),
                                                Colors.white.withAlpha(0),
                                              ],
                                              stops: const [0.0, 0.5, 1.0],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
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
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          paused ? 'Paused' : 'Uploading',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${(uploadProgress * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (uploading || paused)
                        ElevatedButton.icon(
                          onPressed: paused ? resumeUpload : pauseUpload,
                          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                          label: Text(paused ? 'Resume' : 'Pause'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(
                              0xFFF9A825,
                            ), // amber/yellow
                            foregroundColor: Colors.white,
                            minimumSize: const Size(80, 40),
                          ),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          final messenger = ScaffoldMessenger.of(context);
                          if (uploading) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Stopping upload…'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(milliseconds: 800),
                              ),
                            );
                            stopUpload();
                          } else {
                            stopUpload();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Cleared selected images'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(
                            0xFFD32F2F,
                          ), // material red
                          foregroundColor: Colors.white,
                          minimumSize: const Size(80, 40),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: hasImages
                ? GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: kIsWeb ? webImages.length : images.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Scaffold(
                                backgroundColor: Colors.black,
                                body: Stack(
                                  children: [
                                    Center(
                                      child: InteractiveViewer(
                                        child: kIsWeb
                                            ? Image.memory(webImages[index])
                                            : Image.file(images[index]),
                                      ),
                                    ),
                                    Positioned(
                                      top: 40,
                                      left: 16,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              kIsWeb
                                  ? Image.memory(
                                      webImages[index],
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      images[index],
                                      fit: BoxFit.cover,
                                    ),
                              Positioned(
                                top: 4,
                                left: 4,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (kIsWeb) {
                                        webImages.removeAt(index);
                                      } else {
                                        images.removeAt(index);
                                      }
                                    });
                                    widget.onImagesChanged?.call();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(77),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No images selected',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to add photos',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: pickFilesOrFolder,
        tooltip: 'Add Images',
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.linear),
    );
    // Check server connectivity on init
    _checkServer();
  }

  Future<void> _checkServer() async {
    setState(() {
      serverStatus = 'Checking...';
    });
    // Ping the API server and report status

    final ok = await ApiService.pingServer();
    if (!mounted) return;
    setState(() {
      serverStatus = ok ? 'Reachable' : 'Unreachable';
      lastServerCheck = DateTime.now();
    });
  }

  // _confirmUploadAndProceed removed — uploads proceed without an extra confirmation.

  Future<void> pickFilesOrFolder() async {
    final localContext = context;
    setState(() {
      isLoading = true;
      progress = 0.0;
      totalImagesToLoad = 0;
    });

    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
      );

      if (result == null) {
        setState(() => isLoading = false);
        return;
      }

      final validFiles = result.files.where((f) => f.bytes != null);

      final validImages = validFiles.map((f) => f.bytes!).toList();
      final validNames = validFiles.map((f) => f.name).toList();

      setState(() {
        final totalCount = webImages.length + validImages.length;
        currentPath = 'Selected $totalCount images';
        totalImagesToLoad = validImages.length;
        webImages.addAll(validImages);
        webImageNames.addAll(validNames);
        progress = 1.0;
        isLoading = false;
      });
      widget.onImagesChanged?.call();
      setState(() {
        currentPath = 'Selected ${images.length} images';
      });

      setState(() => isLoading = false);
      widget.onImagesChanged?.call();
    } else if (Platform.isAndroid || Platform.isIOS) {
      // Mobile platforms: use custom image picker with Select All
      final selectedFiles = await Navigator.push<List<File>>(
        localContext,
        MaterialPageRoute(builder: (context) => const CustomImagePicker()),
      );

      if (!mounted) {
        setState(() => isLoading = false);
        return;
      }

      if (selectedFiles == null || selectedFiles.isEmpty) {
        setState(() => isLoading = false);
        return;
      }

      final imageFiles = selectedFiles;

      // Check Wi‑Fi preference before adding files
      try {
        final prefs = await SharedPreferences.getInstance();
        final scanOnly = prefs.getBool('scan_on_wifi_only') ?? true;
        if (scanOnly && !(await NetworkUtils.isOnWifi())) {
          if (!mounted) {
            setState(() => isLoading = false);
            return;
          }
          final choice = await showDialog<String>(
            context: localContext,
            builder: (ctx) => AlertDialog(
              title: const Text('No Wi‑Fi detected'),
              content: const Text(
                "You're about to use the service without Wi‑Fi; we suggest you turn it on.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'turn_on'),
                  child: const Text('Turn on'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'upload_anyway'),
                  child: const Text('Upload anyway'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );

          if (!mounted) {
            setState(() => isLoading = false);
            return;
          }

          if (choice == 'turn_on') {
            await SettingsUtils.openWifiSettings();
            setState(() => isLoading = false);
            return;
          }

          if (choice != 'upload_anyway') {
            setState(() => isLoading = false);
            return;
          }
        }
      } catch (_) {}

      setState(() {
        final totalCount = images.length + imageFiles.length;
        currentPath = 'Selected $totalCount images';
        totalImagesToLoad = imageFiles.length;
        for (final f in imageFiles) {
          images.add(f);
          imagePhotoIds.add(PhotoId.canonicalId(f));
        }
        progress = 1.0;
        isLoading = false;
      });

      widget.onImagesChanged?.call();
    }
  }

  Future<void> uploadSelectedImages() async {
    // Ask the user which category/topic to organize under before uploading
    final choice = await _showOrganizeDialog();
    if (choice == null) {
      developer.log('📤 Upload cancelled by user at organize dialog');
      return;
    }

    _organizeTopic = choice['topic'];
    _organizeScope = choice['scope'];
    _organizeAlbum = choice['album'];

    developer.log(
      '📤 Starting upload - topic=$_organizeTopic scope=$_organizeScope album=$_organizeAlbum',
    );
    setState(() {
      uploading = true;
      uploadProgress = 0.0;
      cancelUpload = false;
      paused = false;
      lastProcessedIndex = -1;
    });
    developer.log('📤 Upload state: uploading=$uploading, paused=$paused');
    widget.onUploadStateChanged?.call();
    await _continueUpload();
  }

  Future<Map<String, String?>?> _showOrganizeDialog() async {
    if (!mounted) return null;
    final prefs = await SharedPreferences.getInstance();
    String? albumsJson = prefs.getString('albums');
    List<String> albums = [];
    if (albumsJson != null) {
      try {
        final Map<String, dynamic> map = json.decode(albumsJson);
        albums = map.keys.toList();
      } catch (_) {}
    }

    final topics = ['People', 'Animals', 'Documents', 'Scenery'];

    final selectedTopics = <String>{};
    String? selectedAlbum = albums.isNotEmpty ? albums.first : null;

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Select Categories'),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show the current selected folder/path so user knows what they're
                    // organizing. This is a safe, non-invasive UI improvement.
                    if (currentPath.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Folder: $currentPath',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    const Text('Choose topics'),
                    const SizedBox(height: 8),
                    ListTile(
                      title: const Text('All'),
                      leading: Icon(
                        selectedTopics.length == topics.length
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: selectedTopics.length == topics.length
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onTap: () => setState(() {
                        if (selectedTopics.length == topics.length) {
                          selectedTopics.clear();
                        } else {
                          selectedTopics.addAll(topics);
                        }
                      }),
                    ),
                    const SizedBox(height: 6),
                    // Vertical list of checkboxes for categories
                    ...topics.map((t) {
                      final sel = selectedTopics.contains(t);
                      return CheckboxListTile(
                        value: sel,
                        title: Text(t),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selectedTopics.add(t);
                          } else {
                            selectedTopics.remove(t);
                          }
                        }),
                      );
                    }),
                    const SizedBox(height: 8),
                    if (albums.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          const Text('Album (optional)'),
                          DropdownButton<String>(
                            value: selectedAlbum,
                            items: albums
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a,
                                    child: Text(a),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => selectedAlbum = v),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                  'topic': selectedTopics.join(','),
                  'album': selectedAlbum,
                }),
                child: const Text('Start'),
              ),
            ],
          );
        },
      ),
    );

    return result;
  }

  Future<void> _continueUpload() async {
    // Capture the messenger before any awaits so we don't use BuildContext
    // after asynchronous gaps.
    final messenger = ScaffoldMessenger.of(context);

    final filesToUpload = kIsWeb ? webImages : images;
    final total = filesToUpload.length;

    // Batch by size: process up to 25MB at a time to limit temp disk usage
    const maxBatchSizeBytes = 25 * 1024 * 1024; // 25MB
    int currentBatchSize = 0;
    List<dynamic> currentBatch = [];
    int processedCount = lastProcessedIndex + 1;
    int batchNumber = 0;

    for (int i = lastProcessedIndex + 1; i < total; i++) {
      // Check if user requested pause or cancellation
      if (paused) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Upload paused ($processedCount/$total processed)'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          lastProcessedIndex = i - 1;
        });
        return;
      }

      if (cancelUpload) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Upload stopped by user ($processedCount/$total processed)',
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          uploading = false;
          uploadProgress = 0.0;
          cancelUpload = false;
          lastProcessedIndex = -1;
          images.clear();
          webImages.clear();
          webImageNames.clear();
        });
        widget.onUploadStateChanged?.call();
        widget.onImagesChanged?.call();
        return;
      }

      final file = filesToUpload[i];
      String photoIdForThis;
      if (kIsWeb) {
        photoIdForThis = webImageNames[i];
      } else {
        photoIdForThis = PhotoId.canonicalId(file as File);
      }
      int fileSize;

      // Get file size
      if (kIsWeb) {
        fileSize = (file as Uint8List).length;
      } else {
        fileSize = await (file as File).length();
      }

      // If adding this file exceeds batch size and we have files in batch, process batch first
      if (currentBatch.isNotEmpty &&
          currentBatchSize + fileSize > maxBatchSizeBytes) {
        // Log batch start
        batchNumber++;
        final batchSizeMB = (currentBatchSize / (1024 * 1024)).toStringAsFixed(
          2,
        );
        final batchStartTime = DateTime.now();
        final memoryBeforeMB = _getCurrentMemoryMB();
        developer.log(
          '📦 Batch $batchNumber: ${currentBatch.length} files, ${batchSizeMB}MB total | Memory: ${memoryBeforeMB}MB',
        );

        // proceed with the current batch without asking for confirmation

        // Process current batch
        for (final batchFile in currentBatch) {
          // Check for pause
          if (paused) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Upload paused ($processedCount/$total processed)',
                ),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                duration: const Duration(seconds: 2),
              ),
            );
            setState(() {
              lastProcessedIndex = processedCount - 1;
            });
            return;
          }

          // Check for cancellation
          if (cancelUpload) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Upload stopped by user ($processedCount/$total processed)',
                ),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                duration: const Duration(seconds: 2),
              ),
            );
            setState(() {
              uploading = false;
              uploadProgress = 0.0;
              cancelUpload = false;
              lastProcessedIndex = -1;
              images.clear();
              webImages.clear();
              webImageNames.clear();
            });
            widget.onUploadStateChanged?.call();
            widget.onImagesChanged?.call();
            return;
          }

          // Additional pause check right before upload
          if (paused) {
            developer.log('🔶 Paused during batch upload');
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Upload paused ($processedCount/$total processed)',
                ),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                duration: const Duration(seconds: 2),
              ),
            );
            setState(() {
              lastProcessedIndex = processedCount - 1;
            });
            return;
          }

          try {
            final fileObj = batchFile as Map;
            final batchFileRef = fileObj['file'];
            final batchPhotoID = fileObj['photoID'];
            final res = await ApiService.uploadImage(
              batchFileRef,
              photoID: batchPhotoID,
            );
            if (!mounted) return;

            developer.log(
              'Uploaded $processedCount/$total: ${res.statusCode} - ${res.body}',
            );

            setState(() {
              lastProcessedIndex = processedCount - 1;
              uploadProgress = processedCount / total;
            });

            if (res.statusCode >= 200 && res.statusCode < 300) {
              try {
                developer.log('Response body: ${res.body}');
                Map<String, dynamic> response = json.decode(res.body);
                List<String> tags = List<String>.from(response['tags'] ?? []);
                // Normalize tags
                tags = tags
                    .map((t) => t.trim())
                    .where((t) => t.isNotEmpty)
                    .toList();
                // Ensure uniqueness while preserving order
                final seen = <String>{};
                tags = tags.where((t) => seen.add(t)).toList();
                // Limit to 3 tags only
                if (tags.length > 3) {
                  final removedCount = tags.length - 3;
                  tags = tags.sublist(0, 3);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Only the first 3 tags were saved; $removedCount tags were dropped.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(
                        bottom: 80,
                        left: 16,
                        right: 16,
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
                developer.log('Parsed tags: $tags');
                try {
                  String photoID;
                  // Prefer explicit photoID returned by the server
                  if (response.containsKey('photoID') &&
                      response['photoID'] != null) {
                    photoID = response['photoID'];
                  } else if (kIsWeb) {
                    final webIndex = processedCount - images.length;
                    photoID = webImageNames[webIndex];
                  } else {
                    photoID = batchPhotoID;
                  }
                  await TagStore.saveLocalTags(photoID, tags);
                  developer.log('Saved tags for $photoID: $tags');
                } catch (e) {
                  developer.log('Failed saving tags to TagStore: $e');
                }
              } catch (e) {
                developer.log('Failed to save tags: $e');
              }
            }

            processedCount++;

            if (res.statusCode < 200 || res.statusCode >= 300) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Upload failed for $processedCount/$total: ${res.statusCode}',
                  ),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.only(
                    bottom: 80,
                    left: 16,
                    right: 16,
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
              setState(() {
                uploading = false;
                uploadProgress = 0.0;
                lastProcessedIndex = -1;
              });
              return;
            }
          } catch (e, st) {
            if (!mounted) return;
            developer.log(
              'Upload error for $processedCount: $e',
              error: e,
              stackTrace: st,
            );
            messenger.showSnackBar(
              SnackBar(
                content: Text('Upload error for $processedCount: $e'),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                duration: const Duration(seconds: 3),
              ),
            );
            setState(() {
              uploading = false;
              uploadProgress = 0.0;
              lastProcessedIndex = -1;
            });
            return;
          }
        }

        // Log batch completion
        final batchEndTime = DateTime.now();
        final batchDuration = batchEndTime
            .difference(batchStartTime)
            .inMilliseconds;
        final memoryAfterMB = _getCurrentMemoryMB();
        final memoryDelta = memoryAfterMB - memoryBeforeMB;
        developer.log(
          '✅ Batch $batchNumber completed in ${batchDuration}ms (${(batchDuration / 1000).toStringAsFixed(1)}s) | Memory: ${memoryAfterMB}MB (${memoryDelta >= 0 ? '+' : ''}${memoryDelta}MB)',
        );

        // Reset batch
        currentBatch.clear();
        currentBatchSize = 0;
      }

      // Add file (and precomputed photoID) to current batch
      currentBatch.add({'file': file, 'photoID': photoIdForThis});
      currentBatchSize += fileSize;
    }

    // Process remaining files in last batch
    if (currentBatch.isNotEmpty) {
      batchNumber++;
      final batchSizeMB = (currentBatchSize / (1024 * 1024)).toStringAsFixed(2);
      final batchStartTime = DateTime.now();
      final memoryBeforeMB = _getCurrentMemoryMB();
      developer.log(
        '📦 Batch $batchNumber (final): ${currentBatch.length} files, ${batchSizeMB}MB total | Memory: ${memoryBeforeMB}MB',
      );

      // proceed with the final batch without asking for confirmation

      for (final batchFile in currentBatch) {
        // Check for pause
        if (paused) {
          developer.log('🔶 Paused during final batch');
          messenger.showSnackBar(
            SnackBar(
              content: Text('Upload paused ($processedCount/$total processed)'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              duration: const Duration(seconds: 2),
            ),
          );
          setState(() {
            lastProcessedIndex = processedCount - 1;
          });
          return;
        }

        // Check for cancellation
        if (cancelUpload) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Upload stopped by user ($processedCount/$total processed)',
              ),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              duration: const Duration(seconds: 2),
            ),
          );
          setState(() {
            uploading = false;
            uploadProgress = 0.0;
            cancelUpload = false;
            images.clear();
            webImages.clear();
            webImageNames.clear();
          });
          widget.onUploadStateChanged?.call();
          widget.onImagesChanged?.call();
          return;
        }

        try {
          final fileObj = batchFile as Map;
          final batchFileRef = fileObj['file'];
          final batchPhotoID = fileObj['photoID'];
          final res = await ApiService.uploadImage(
            batchFileRef,
            photoID: batchPhotoID,
          );
          if (!mounted) return;

          processedCount++;
          developer.log(
            'Uploaded $processedCount/$total: ${res.statusCode} - ${res.body}',
          );

          if (res.statusCode < 200 || res.statusCode >= 300) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Upload failed for $processedCount/$total: ${res.statusCode}',
                ),
              ),
            );
            setState(() {
              uploading = false;
              uploadProgress = 0.0;
            });
            return;
          }
        } catch (e, st) {
          if (!mounted) return;
          developer.log(
            'Upload error for $processedCount: $e',
            error: e,
            stackTrace: st,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text('Upload error for $processedCount: $e'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() {
            uploading = false;
            uploadProgress = 0.0;
          });
          return;
        }

        setState(() {
          uploadProgress = processedCount / total;
        });
      }

      // Log final batch completion
      final batchEndTime = DateTime.now();
      final batchDuration = batchEndTime
          .difference(batchStartTime)
          .inMilliseconds;
      final memoryAfterMB = _getCurrentMemoryMB();
      final memoryDelta = memoryAfterMB - memoryBeforeMB;
      developer.log(
        '✅ Batch $batchNumber completed in ${batchDuration}ms (${(batchDuration / 1000).toStringAsFixed(1)}s) | Memory: ${memoryAfterMB}MB (${memoryDelta >= 0 ? '+' : ''}${memoryDelta}MB)',
      );
    }

    if (!mounted) return;

    setState(() {
      uploading = false;
      uploadProgress = 0.0;
      images.clear();
      webImages.clear();
      webImageNames.clear();
    });
    widget.onUploadStateChanged?.call();
    widget.onImagesChanged?.call();

    // Use mounted check before showing SnackBar
    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('All images uploaded!'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void pauseUpload() {
    if (!mounted) return;
    setState(() {
      paused = true;
    });
    widget.onUploadStateChanged?.call();
  }

  Future<void> resumeUpload() async {
    if (!mounted) return;
    setState(() {
      paused = false;
    });
    widget.onUploadStateChanged?.call();
    // Continue where we left off
    await _continueUpload();
  }

  void stopUpload() {
    if (!mounted) return;

    // If not currently uploading, treat Cancel as "clear selection" immediately.
    if (!uploading) {
      setState(() {
        cancelUpload = false;
        uploading = false;
        paused = false;
        uploadProgress = 0.0;
        lastProcessedIndex = -1;
        images.clear();
        webImages.clear();
        webImageNames.clear();
      });
      widget.onUploadStateChanged?.call();
      widget.onImagesChanged?.call();
      return;
    }

    // If an upload is in progress but currently paused, treat Cancel as
    // an immediate clear (user expects Cancel to clear selection while paused).
    if (paused) {
      setState(() {
        cancelUpload = false;
        uploading = false;
        paused = false;
        uploadProgress = 0.0;
        lastProcessedIndex = -1;
        images.clear();
        webImages.clear();
        webImageNames.clear();
      });
      widget.onUploadStateChanged?.call();
      widget.onImagesChanged?.call();
      return;
    }

    // Otherwise (uploading and not paused), signal cancellation so the loop can stop cleanly.
    setState(() {
      cancelUpload = true;
    });
    widget.onUploadStateChanged?.call();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }
}
