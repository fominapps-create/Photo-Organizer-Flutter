import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class PhotoOrganizerApp extends StatefulWidget {
  const PhotoOrganizerApp({super.key});

  @override
  State<PhotoOrganizerApp> createState() => _PhotoOrganizerAppState();
}

class _PhotoOrganizerAppState extends State<PhotoOrganizerApp> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  void _updateTheme(bool isDark) {
    setState(() {
      _isDarkMode = isDark;
    });
  }

  @override
  Widget build(BuildContext context) {
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
      home: HomeScreen(isDarkMode: _isDarkMode, onThemeChanged: _updateTheme),
    );
  }
}
