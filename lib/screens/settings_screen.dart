import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pricing_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _isDarkMode;
  late bool _scanOnWifi;
  late bool _autoscanAutoStart;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.isDarkMode;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _scanOnWifi = prefs.getBool('scan_on_wifi_only') ?? true;
      _autoscanAutoStart = prefs.getBool('autoscan_auto_start') ?? false;
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
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Network',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
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
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text('1.0.0'),
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
