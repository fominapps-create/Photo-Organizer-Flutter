import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:developer' as developer;
import 'screens/home_screen.dart';
import 'screens/intro_video_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/api_service.dart';
import 'services/local_tagging_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-warm ML Kit labeler in background (prevents 30-60s delay on first gallery load)
  // This starts model loading immediately so it's ready when scanning starts
  _preWarmMLKit();

  // Set system UI overlay style (status bar and navigation bar)
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // Transparent status bar
      statusBarIconBrightness: Brightness.dark, // Dark icons for light mode
      statusBarBrightness: Brightness.light, // For iOS
      systemNavigationBarColor: Colors.white.withValues(
        alpha: 0.85,
      ), // Light mode navigation bar (85% opacity)
      systemNavigationBarIconBrightness: Brightness.dark, // Dark icons
      systemNavigationBarContrastEnforced: false, // Allow transparency
    ),
  );

  // Enable edge-to-edge display
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Allow overriding the API base URL at runtime (useful for running on a real device)
  const dartApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  if (dartApiBaseUrl.isNotEmpty) {
    ApiService.setBaseUrl(dartApiBaseUrl);
  }

  // The app defaults to a platform-friendly server base URL (Emulator: 10.0.2.2:8000). To auto-discover attempts,
  // call `ApiService.initialize()` if desired. For release builds, ensure auto-discovery is disabled to avoid accidental uploads.

  // Load persisted upload token (optional) and set it for ApiService.
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('upload_token') ?? '';
    if (savedToken.isNotEmpty) {
      ApiService.setUploadToken(savedToken);
    }
  } catch (e) {
    // ignore prefs errors here
  }

  // Ensure the base URL defaults to the platform's emulator-friendly value
  ApiService.setBaseUrl(ApiService.defaultBaseUrlForPlatform());

  runApp(const PhotoOrganizerApp());
}

/// Pre-warm ML Kit labeler in background to avoid 30-60s delay on first scan
/// This runs asynchronously so it doesn't block app startup
void _preWarmMLKit() {
  Future(() async {
    try {
      final startTime = DateTime.now();
      developer.log('🔥 Pre-warming ML Kit labeler...');
      
      // Access the labeler singleton - this triggers model loading
      final _ = LocalTaggingService.labeler;
      
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      developer.log('✅ ML Kit labeler pre-warmed in ${elapsed}ms');
    } catch (e) {
      developer.log('⚠️ ML Kit pre-warm error (non-fatal): $e');
    }
  });
}

class PhotoOrganizerApp extends StatefulWidget {
  const PhotoOrganizerApp({super.key});

  @override
  State<PhotoOrganizerApp> createState() => _PhotoOrganizerAppState();
}

class _PhotoOrganizerAppState extends State<PhotoOrganizerApp> {
  bool _isDarkMode = false;
  bool _isFirstLaunch = true;
  bool _isCheckingFirstLaunch = true;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();

    // Use versioned key to ensure onboarding shows after major updates
    // Increment this version when onboarding content changes significantly
    const onboardingVersion = 2; // Bumped to force onboarding for current users
    final hasSeenOnboarding =
        prefs.getBool('hasSeenOnboarding_v$onboardingVersion') ?? false;

    // Clean up old keys on first check
    if (!hasSeenOnboarding) {
      // Check if we need to show onboarding (fresh install or major update)
      // For fresh installs, no old key exists. For updates, we've incremented version.
      await prefs.remove('hasSeenOnboarding'); // Clean up legacy key
    }

    setState(() {
      _isFirstLaunch = !hasSeenOnboarding;
      _isCheckingFirstLaunch = false;
    });
  }

  Future<void> _markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    const onboardingVersion = 2;
    await prefs.setBool('hasSeenOnboarding_v$onboardingVersion', true);
    setState(() {
      _isFirstLaunch = false;
    });
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    setState(() {
      _isDarkMode = isDark;
    });

    // Update system UI colors on app start
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isDark
            ? Colors.black.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.95),
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  void _updateTheme(bool isDark) {
    setState(() {
      _isDarkMode = isDark;
    });

    // Update system UI colors based on theme
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isDark
            ? Colors.black.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.85),
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking first launch status
    if (_isCheckingFirstLaunch) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    return MaterialApp(
      title: 'Photo Organizer',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.light().textTheme),
        // Use a subtle off-white for light mode backgrounds to reduce
        // glare compared to pure white. Use #F2F0EF as requested.
        scaffoldBackgroundColor: const Color(0xFFF2F0EF),
        cardColor: const Color(0xFFF2F0EF),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFF2F0EF),
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: GoogleFonts.roboto(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: GoogleFonts.roboto(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        cardColor: const Color(0xFF1E1E1E),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: _isFirstLaunch
          ? _FirstLaunchFlow(
              isDarkMode: _isDarkMode,
              onThemeChanged: _updateTheme,
              onComplete: _markOnboardingComplete,
            )
          : HomeScreen(isDarkMode: _isDarkMode, onThemeChanged: _updateTheme),
    );
  }
}

class _FirstLaunchFlow extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  final VoidCallback onComplete;

  const _FirstLaunchFlow({
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.onComplete,
  });

  @override
  State<_FirstLaunchFlow> createState() => _FirstLaunchFlowState();
}

class _FirstLaunchFlowState extends State<_FirstLaunchFlow> {
  bool _showVideo = true;
  bool _showOnboarding = false;

  void _onVideoFinished() {
    setState(() {
      _showVideo = false;
      _showOnboarding = true;
    });
  }

  void _onOnboardingComplete() {
    widget.onComplete();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          isDarkMode: widget.isDarkMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showVideo) {
      return IntroVideoScreen(onVideoFinished: _onVideoFinished);
    } else if (_showOnboarding) {
      return OnboardingScreen(onGetStarted: _onOnboardingComplete);
    }

    // Fallback (shouldn't reach here)
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
