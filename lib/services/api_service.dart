import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'dart:developer' as developer;
import 'dart:convert';

// Conditional import: use real platform detection on native builds, stub on web.
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';

class ApiService {
  // Current active base URL
  static String _baseUrl = ""; // empty means disabled until user opts-in
  static String get baseUrl => _baseUrl;
  static bool _isInitialized = false;
  static String? _uploadToken;
  static String? _workingUrl;

  /// Call this to override the base URL (useful for emulator/device testing).
  static void setBaseUrl(String url) {
    _baseUrl = url;
    _workingUrl = url;
  }

  /// Set upload token for server (optional). We no longer require an upload toggle.
  static void setUploadToken(String? token) {
    _uploadToken = token;
  }

  /// Get list of possible server URLs to try based on platform
  static List<String> _getPossibleUrls() {
    if (kIsWeb) {
      return ['http://localhost:8000', 'http://127.0.0.1:8000'];
    }

    if (PlatformInfo.isAndroid) {
      return [
        'http://10.0.2.2:8000', // Android emulator -> host
        'http://192.168.1.100:8000', // Common local IP patterns
        'http://192.168.0.100:8000',
        'http://192.168.1.1:8000',
        'http://127.0.0.1:8000',
      ];
    }

    if (PlatformInfo.isIOS) {
      return [
        'http://localhost:8000', // iOS simulator
        'http://127.0.0.1:8000',
        'http://192.168.1.100:8000', // Physical device on same network
        'http://192.168.0.100:8000',
      ];
    }

    return ['http://127.0.0.1:8000', 'http://localhost:8000'];
  }

  /// Helper to compute a reasonable default for the current platform.
  static String defaultBaseUrlForPlatform() {
    if (kIsWeb) return 'http://localhost:8000';
    if (PlatformInfo.isAndroid) return 'http://10.0.2.2:8000';
    if (PlatformInfo.isIOS) return 'http://localhost:8000';
    return 'http://127.0.0.1:8000';
  }

  /// Initialize by finding a working server URL
  static Future<bool> initialize() async {
    if (_isInitialized && _workingUrl != null) {
      _baseUrl = _workingUrl!;
      return true;
    }

    developer.log('🔍 ApiService: Searching for server...');
    final urls = _getPossibleUrls();

    for (final url in urls) {
      developer.log('  Trying: $url');
      try {
        final uri = Uri.parse('$url/');
        final res = await http.get(uri).timeout(const Duration(seconds: 3));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          developer.log('✅ Found server at: $url');
          _baseUrl = url;
          _workingUrl = url;
          _isInitialized = true;
          return true;
        }
      } catch (e) {
        developer.log('  ❌ Failed: $e');
        continue;
      }
    }

    developer.log(
      '⚠️ No server found, using default: ${defaultBaseUrlForPlatform()}',
    );
    _baseUrl = defaultBaseUrlForPlatform();
    return false;
  }

  static Uri _endpointUri([String path = '/process-image/']) {
    final base = _baseUrl.isNotEmpty ? _baseUrl : defaultBaseUrlForPlatform();
    return Uri.parse(base + path);
  }

  /// Resolve an image URL returned by the server or stored locally.
  /// If [url] already looks like an absolute URL (starts with http),
  /// return it as-is. Otherwise prefix with the configured base URL
  /// taking care to avoid duplicate slashes.
  static String resolveImageUrl(String url) {
    if (url.isEmpty) return url;
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = _baseUrl.isNotEmpty ? _baseUrl : defaultBaseUrlForPlatform();
    // Ensure there's exactly one slash between base and path
    if (base.endsWith('/') && trimmed.startsWith('/')) {
      return base + trimmed.substring(1);
    }
    if (!base.endsWith('/') && !trimmed.startsWith('/')) {
      return '$base/$trimmed';
    }
    return base + trimmed;
  }

  /// Simple connectivity check with retry logic
  static Future<bool> pingServer({
    Duration timeout = const Duration(seconds: 5),
    int retries = 2,
  }) async {
    // Try current URL first
    for (int i = 0; i < retries; i++) {
      final uri = _endpointUri('/');
      try {
        final res = await http.get(uri).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return true;
        }
      } catch (e) {
        developer.log('Ping attempt ${i + 1} failed: $e');
        if (i < retries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
        }
      }
    }

    // If all retries failed, try to reinitialize
    developer.log('Server ping failed, attempting to find server again...');
    final found = await initialize();
    if (found) {
      // Try one more time with new URL
      try {
        final uri = _endpointUri('/');
        final res = await http.get(uri).timeout(timeout);
        return res.statusCode >= 200 && res.statusCode < 300;
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  static Future<http.Response> uploadImage(
    dynamic file, {
    String? module,
    Duration timeout = const Duration(seconds: 30),
    int retries = 2,
  }) async {
    // Uploads are always enabled for local/dev use; the server may still reject requests.
    Exception? lastError;

    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        final uri = _endpointUri('/process-image/');

        if (kIsWeb) {
          var request = http.MultipartRequest('POST', uri);
          if (_uploadToken != null && _uploadToken!.isNotEmpty) {
            request.headers['X-Upload-Token'] = _uploadToken!;
          }
          // Include module as a form field so server can route to the correct AI module
          if (module != null && module.isNotEmpty) {
            request.fields['module'] = module;
          }
          request.files.add(
            http.MultipartFile.fromBytes('file', file, filename: 'upload.png'),
          );
          final streamed = await request.send().timeout(timeout);
          final response = await http.Response.fromStream(streamed);

          if (response.statusCode >= 200 && response.statusCode < 300) {
            return response;
          }

          if (response.statusCode >= 500) {
            throw Exception('Server error: ${response.statusCode}');
          }

          return response;
        } else {
          var request = http.MultipartRequest('POST', uri);
          if (_uploadToken != null && _uploadToken!.isNotEmpty) {
            request.headers['X-Upload-Token'] = _uploadToken!;
          }
          // Include module as a form field so server can route to the correct AI module
          if (module != null && module.isNotEmpty) {
            request.fields['module'] = module;
          }
          request.files.add(
            await http.MultipartFile.fromPath(
              'file',
              file.path,
              filename: p.basename(file.path),
            ),
          );
          final streamed = await request.send().timeout(timeout);
          final response = await http.Response.fromStream(streamed);

          if (response.statusCode >= 200 && response.statusCode < 300) {
            return response;
          }

          if (response.statusCode >= 500) {
            throw Exception('Server error: ${response.statusCode}');
          }

          return response;
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        developer.log('Upload attempt ${attempt + 1} failed: $e');

        if (attempt < retries - 1) {
          await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
          // Try to reinitialize connection
          await initialize();
        }
      }
    }

    throw lastError ?? Exception('Upload failed after $retries attempts');
  }

  static Future<List<http.Response>> uploadImages(List<dynamic> files) async {
    List<http.Response> responses = [];
    for (var file in files) {
      final res = await uploadImage(file);
      responses.add(res);
    }
    return responses;
  }

  static Future<http.Response> getAllOrganizedImages() async {
    final url = Uri.parse('$_baseUrl/all-organized-images/');
    final response = await http.get(url);
    return response;
  }

  static Future<http.Response> getAllOrganizedImagesWithTags() async {
    final url = Uri.parse('$_baseUrl/all-organized-images-with-tags/');
    final response = await http.get(url).timeout(const Duration(seconds: 5));
    return response;
  }

  static Future<List<String>> getAllTags() async {
    try {
      final url = Uri.parse('$_baseUrl/all-tags/');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData['tags'] is List) {
          return List<String>.from(jsonData['tags']);
        }
      }
      return [];
    } catch (e) {
      developer.log('Failed to fetch tags: $e');
      return [];
    }
  }
}
