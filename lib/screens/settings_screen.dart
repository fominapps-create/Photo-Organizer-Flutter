import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pricing_screen.dart';
import 'trash_screen.dart';
import 'privacy_policy_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../config/app_links.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  final VoidCallback? onTrashRestored;

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
    this.onTrashRestored,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _isDarkMode;
  late bool _scanOnWifi;
  late bool _autoscanAutoStart;
  late bool _backgroundScanEnabled;
  // Note: Server-related fields commented out for free tier
  // bool _uploadConsent = false;
  // bool _serverOnline = false;
  // bool _checkingServer = false;
  // String _serverUrl = '';
  bool _showDevButtons = false; // Developer tools (camera/bug buttons)

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.isDarkMode;
    _loadSettings();
    _checkServerStatus();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _scanOnWifi = prefs.getBool('scan_on_wifi_only') ?? true;
      _autoscanAutoStart =
          prefs.getBool('autoscan_auto_start') ??
          true; // Default ON for free tier
      _backgroundScanEnabled =
          prefs.getBool('background_scan_enabled') ?? false;
      _showDevButtons = prefs.getBool('show_dev_buttons') ?? false;
    });
  }

  Future<void> _saveScanOnWifi(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scan_on_wifi_only', val);
  }

  Future<void> _saveAutoscanAutoStart(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoscan_auto_start', val);
  }

  Future<void> _saveBackgroundScan(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_scan_enabled', val);
  }

  // Note: Commented out for free tier - no server uploads
  // Future<void> _saveUploadConsent(bool val) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.setBool('server_upload_consent', val);
  // }

  Future<void> _saveDevButtons(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_dev_buttons', val);
  }

  // Note: Server status check commented out for free tier
  // ignore: unused_element
  Future<void> _checkServerStatus() async {
    // Server functionality disabled for free tier
    // This method is kept for potential future premium tier
  }

  Future<void> _toggleTheme(bool value) async {
    setState(() {
      _isDarkMode = value;
    });
    widget.onThemeChanged(value);

    // Save preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Settings Screen',
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
      body: ListView(
        children: [
          // Server section hidden for free tier (on-device only)
          // const Padding(
          //   padding: EdgeInsets.all(16.0),
          //   child: Text(
          //     'Network',
          //     style: TextStyle(
          //       fontSize: 14,
          //       fontWeight: FontWeight.w600,
          //       color: Colors.grey,
          //     ),
          //   ),
          // ),
          // Server Status Indicator - hidden for free tier
          // Container(
          //   margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          //   padding: const EdgeInsets.all(16),
          //   decoration: BoxDecoration(
          //     color: _serverOnline
          //         ? Colors.green.withValues(alpha: 0.1)
          //         : Colors.red.withValues(alpha: 0.1),
          //     border: Border.all(
          //       color: _serverOnline ? Colors.green : Colors.red,
          //       width: 1.5,
          //     ),
          //     borderRadius: BorderRadius.circular(12),
          //   ),
          //   child: Column(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       Row(
          //         children: [
          //           Icon(
          //             _checkingServer
          //                 ? Icons.sync
          //                 : (_serverOnline ? Icons.check_circle : Icons.error),
          //             color: _checkingServer
          //                 ? Colors.orange
          //                 : (_serverOnline ? Colors.green : Colors.red),
          //             size: 24,
          //           ),
          //           const SizedBox(width: 12),
          //           Expanded(
          //             child: Column(
          //               crossAxisAlignment: CrossAxisAlignment.start,
          //               children: [
          //                 Text(
          //                   _checkingServer
          //                       ? 'Checking server...'
          //                       : (_serverOnline
          //                             ? 'Server Online'
          //                             : 'Server Offline'),
          //                   style: const TextStyle(
          //                     fontWeight: FontWeight.bold,
          //                     fontSize: 16,
          //                   ),
          //                 ),
          //                 const SizedBox(height: 4),
          //                 Text(
          //                   _serverUrl,
          //                   style: TextStyle(
          //                     fontSize: 12,
          //                     color: Colors.grey[600],
          //                   ),
          //                 ),
          //               ],
          //             ),
          //           ),
          //           IconButton(
          //             icon: const Icon(Icons.refresh),
          //             onPressed: _checkingServer ? null : _checkServerStatus,
          //             tooltip: 'Test connection',
          //           ),
          //         ],
          //       ),
          //     ],
          //   ),
          // ),
          // if (_serverUrl.startsWith('http://') &&
          //     !(_serverUrl.contains('localhost') ||
          //         _serverUrl.contains('127.0.0.1') ||
          //         _serverUrl.contains('10.0.2.2') ||
          //         _serverUrl.contains('192.168.')))
          //   Container(
          //     margin: const EdgeInsets.symmetric(horizontal: 16),
          //     padding: const EdgeInsets.all(12),
          //     decoration: BoxDecoration(
          //       color: Colors.orange.withValues(alpha: 0.1),
          //       border: Border.all(color: Colors.orange),
          //       borderRadius: BorderRadius.circular(8),
          //     ),
          //     child: const Text(
          //       'Warning: Using an HTTP server on the public internet. For Play Store compliance and security, prefer HTTPS for remote servers.',
          //       style: TextStyle(fontSize: 12),
          //     ),
          //   ),
          SwitchListTile(
            title: const Text('Scan photos only on Wi‑Fi'),
            subtitle: const Text(
              'Only scan/download images when connected to Wi‑Fi',
            ),
            value: _scanOnWifi,
            onChanged: (v) async {
              setState(() => _scanOnWifi = v);
              await _saveScanOnWifi(v);
            },
            secondary: const Icon(Icons.wifi),
          ),
          SwitchListTile(
            title: const Text('Start autoscan on app open'),
            subtitle: const Text(
              'Automatically start autoscan when gallery opens',
            ),
            value: _autoscanAutoStart,
            onChanged: (v) async {
              setState(() => _autoscanAutoStart = v);
              await _saveAutoscanAutoStart(v);
            },
            secondary: const Icon(Icons.playlist_play),
          ),
          SwitchListTile(
            title: const Text('Background scanning'),
            subtitle: const Text('Continue scanning when app is minimized'),
            value: _backgroundScanEnabled,
            onChanged: (v) async {
              setState(() => _backgroundScanEnabled = v);
              await _saveBackgroundScan(v);
            },
            secondary: const Icon(Icons.sync),
          ),
          // Server upload toggle hidden for free tier (no server-based features)
          // SwitchListTile(
          //   title: const Text('Allow server uploads'),
          //   subtitle: const Text(
          //     'Upload selected photos to your configured server for enhanced AI tags',
          //   ),
          //   value: _uploadConsent,
          //   onChanged: (v) async {
          //     setState(() => _uploadConsent = v);
          //     await _saveUploadConsent(v);
          //   },
          //   secondary: const Icon(Icons.cloud_upload_outlined),
          // ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Developer',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Show developer buttons'),
            subtitle: const Text(
              'Show camera and debug buttons in gallery (for testers)',
            ),
            value: _showDevButtons,
            onChanged: (v) async {
              setState(() => _showDevButtons = v);
              await _saveDevButtons(v);
            },
            secondary: const Icon(Icons.bug_report),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Appearance',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Use dark theme'),
            value: _isDarkMode,
            onChanged: _toggleTheme,
            secondary: Icon(_isDarkMode ? Icons.dark_mode : Icons.light_mode),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'About',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            subtitle: const Text('Learn how your data is handled'),
            onTap: () async {
              final url = AppLinks.kPrivacyPolicyUrl.trim();
              // Capture navigator before async gap to avoid use_build_context_synchronously
              final navigator = Navigator.of(context);

              if (url.isNotEmpty) {
                final uri = Uri.parse(url);
                try {
                  final ok = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && mounted) {
                    navigator.push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  }
                } catch (_) {
                  if (!mounted) return;
                  navigator.push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  );
                }
              } else {
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Trash'),
            subtitle: const Text('View and manage deleted photos'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TrashScreen(onRestored: widget.onTrashRestored),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App Version'),
            subtitle: Text(AppConfig.appVersion),
          ),
          ListTile(
            leading: const Icon(Icons.analytics_outlined),
            title: const Text('Scan Logic Version'),
            subtitle: Text('${AppConfig.scanLogicVersion}'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.local_offer),
            title: const Text('Pricing'),
            subtitle: const Text('View pricing and subscription options'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PricingScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
