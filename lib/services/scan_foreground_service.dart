import 'dart:developer' as developer;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as local_notif;

/// Manages foreground service for background photo scanning.
/// Shows a persistent notification with progress while scanning.
class ScanForegroundService {
  static bool _isInitialized = false;
  static bool _isRunning = false;
  static bool _isAppInForeground = true; // Track if app is visible

  /// Check if app is currently in foreground
  static bool get isAppInForeground => _isAppInForeground;

  // Track progress for graceful shutdown notification
  static int _lastScanned = 0;
  static int _lastTotal = 0;
  static bool _isShuttingDown = false;

  // Local notifications plugin for post-shutdown messages
  static local_notif.FlutterLocalNotificationsPlugin? _localNotifications;

  /// Set app foreground state (call from app lifecycle observer)
  static void setAppInForeground(bool inForeground) {
    _isAppInForeground = inForeground;
    developer.log('📱 App foreground state: $inForeground');
  }

  /// Initialize the foreground task system (call once at app start)
  static Future<void> init() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'photo_scan_channel',
        channelName: 'Photo Scanning',
        channelDescription: 'Shows progress while scanning photos',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    _isInitialized = true;
    developer.log('📱 Foreground service initialized');
  }

  /// Start the foreground service with initial notification
  /// Only shows notification when app is in background
  static Future<void> startService({
    required int total,
    int scanned = 0,
  }) async {
    // Don't start foreground service if app is in foreground
    // We only need it to keep the process alive when in background
    if (_isAppInForeground) {
      // Just track progress without starting service
      _lastScanned = scanned;
      _lastTotal = total;
      developer.log('📱 Skipping foreground service - app in foreground');
      return;
    }

    if (_isRunning) {
      // Already running, just update
      await updateProgress(scanned: scanned, total: total);
      return;
    }

    await init();

    // Initialize local notifications for post-shutdown messages
    await _initLocalNotifications();

    // Request notification permission on Android 13+
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final pct = total > 0 ? (scanned / total * 100).toInt() : 0;

    // Track progress for graceful shutdown
    _lastScanned = scanned;
    _lastTotal = total;
    _isShuttingDown = false;

    await FlutterForegroundTask.startService(
      notificationTitle: 'Scanning photos...',
      notificationText: '$scanned / $total ($pct%)',
      notificationButtons: [
        const NotificationButton(id: 'pause', text: 'Pause'),
      ],
      callback: _startCallback,
    );

    _isRunning = true;
    developer.log('🚀 Foreground service started');
  }

  /// Update the notification with current progress
  static Future<void> updateProgress({
    required int scanned,
    required int total,
  }) async {
    if (!_isRunning) return;

    // Track progress for graceful shutdown
    _lastScanned = scanned;
    _lastTotal = total;

    final pct = total > 0 ? (scanned / total * 100).toInt() : 0;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Scanning photos...',
      notificationText: '$scanned / $total ($pct%)',
    );
  }

  /// Update notification to show paused state
  static Future<void> showPaused({
    required int scanned,
    required int total,
  }) async {
    if (!_isRunning) return;

    final pct = total > 0 ? (scanned / total * 100).toInt() : 0;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Scanning paused',
      notificationText: '$scanned / $total ($pct%) - Tap to resume',
      notificationButtons: [
        const NotificationButton(id: 'resume', text: 'Resume'),
      ],
    );
  }

  /// Update notification to show resumed/scanning state
  static Future<void> showResumed({
    required int scanned,
    required int total,
  }) async {
    if (!_isRunning) return;

    final pct = total > 0 ? (scanned / total * 100).toInt() : 0;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Scanning photos...',
      notificationText: '$scanned / $total ($pct%)',
      notificationButtons: [
        const NotificationButton(id: 'pause', text: 'Pause'),
      ],
    );
  }

  /// Stop the foreground service
  static Future<void> stopService() async {
    if (!_isRunning) return;

    await FlutterForegroundTask.stopService();
    _isRunning = false;
    _isShuttingDown = false;
    developer.log('🛑 Foreground service stopped');
  }

  /// Check if service is currently running
  static bool get isRunning => _isRunning;

  /// Check if graceful shutdown is in progress
  static bool get isShuttingDown => _isShuttingDown;

  /// Get current progress for graceful shutdown
  static int get lastScanned => _lastScanned;
  static int get lastTotal => _lastTotal;

  /// Show completion notification briefly, then stop service
  static Future<void> showComplete({required int total}) async {
    if (!_isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Scan complete',
      notificationText: '$total photos scanned ✓',
      notificationButtons: [],
    );

    // Keep notification visible for 2 seconds, then dismiss
    await Future.delayed(const Duration(seconds: 2));
    await stopService();
  }

  /// Initialize local notifications for post-shutdown messages
  static Future<void> _initLocalNotifications() async {
    if (_localNotifications != null) return;

    _localNotifications = local_notif.FlutterLocalNotificationsPlugin();

    const androidSettings = local_notif.AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = local_notif.DarwinInitializationSettings();
    const initSettings = local_notif.InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications!.initialize(initSettings);
    developer.log('📱 Local notifications initialized');
  }

  /// Mark that graceful shutdown is starting
  static void beginGracefulShutdown() {
    _isShuttingDown = true;
    developer.log(
      '🛑 Graceful shutdown started at $_lastScanned / $_lastTotal',
    );
  }

  /// Show a notification about interrupted scan progress (survives app death)
  static Future<void> showInterruptedNotification() async {
    await _initLocalNotifications();

    const androidDetails = local_notif.AndroidNotificationDetails(
      'photo_scan_interrupted',
      'Scan Interrupted',
      channelDescription: 'Notification when photo scan is interrupted',
      importance: local_notif.Importance.defaultImportance,
      priority: local_notif.Priority.defaultPriority,
      autoCancel: true,
    );

    const notificationDetails = local_notif.NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications?.show(
      1001, // Unique ID for interrupted notification
      'Photo scan',
      'Saving and closing...',
      notificationDetails,
    );

    developer.log('📱 Showed interrupted notification');
  }
}

/// This callback runs in an isolate - we don't need it to do anything
/// since our scanning happens in the main isolate. This just keeps
/// the service alive.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_ScanTaskHandler());
}

/// Minimal task handler - scanning happens in main isolate
class _ScanTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    developer.log('📱 Foreground task handler started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Not used - we update manually from main isolate
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    developer.log('📱 Foreground task handler destroyed (timeout: $isTimeout)');
  }

  @override
  void onNotificationButtonPressed(String id) {
    developer.log('📱 Notification button pressed: $id');
    // Send data to main isolate to handle pause/resume
    FlutterForegroundTask.sendDataToMain({'action': id});
  }

  @override
  void onNotificationPressed() {
    developer.log('📱 Notification pressed - bringing app to foreground');
    FlutterForegroundTask.launchApp();
  }
}
