/// Sync versions from docs/version.json to app code and pubspec.yaml
///
/// Run this after editing docs/version.json:
///   dart tools/sync_versions.dart
///
/// This updates:
///   - docs/version.json (lastUpdated timestamp)
///   - lib/config/app_config.dart (appVersion, scanLogicVersion)
///   - pubspec.yaml (version line)

import 'dart:convert';
import 'dart:io';

void main() async {
  final projectRoot = Directory.current.path;

  // Read version.json
  final versionFile = File('$projectRoot/docs/version.json');
  if (!versionFile.existsSync()) {
    print('❌ docs/version.json not found!');
    exit(1);
  }

  final versionData =
      jsonDecode(versionFile.readAsStringSync()) as Map<String, dynamic>;
  final appVersion = versionData['appVersion'] as String;
  final buildNumber = versionData['buildNumber'] as int;
  final scanLogicVersion = versionData['scanLogicVersion'] as int;

  // Update lastUpdated timestamp to now
  final now = DateTime.now();
  final timestamp =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';
  versionData['lastUpdated'] = timestamp;

  // Write back version.json with updated timestamp
  const encoder = JsonEncoder.withIndent('  ');
  versionFile.writeAsStringSync(encoder.convert(versionData));

  print('📋 Version info:');
  print('   App Version: $appVersion');
  print('   Build Number: $buildNumber');
  print('   Scan Logic: $scanLogicVersion');
  print('   Timestamp: $timestamp');
  print('');

  print('✅ Updated docs/version.json (timestamp)');

  // Update app_config.dart
  final configFile = File('$projectRoot/lib/config/app_config.dart');
  if (configFile.existsSync()) {
    var content = configFile.readAsStringSync();

    // Update appVersion
    content = content.replaceAllMapped(
      RegExp(r"static const String appVersion = '[^']+';"),
      (m) => "static const String appVersion = '$appVersion';",
    );

    // Update scanLogicVersion
    content = content.replaceAllMapped(
      RegExp(r'static const int scanLogicVersion = \d+;'),
      (m) => 'static const int scanLogicVersion = $scanLogicVersion;',
    );

    configFile.writeAsStringSync(content);
    print('✅ Updated lib/config/app_config.dart');
  } else {
    print('⚠️ lib/config/app_config.dart not found, skipping');
  }

  // Update pubspec.yaml
  final pubspecFile = File('$projectRoot/pubspec.yaml');
  if (pubspecFile.existsSync()) {
    var content = pubspecFile.readAsStringSync();

    // Update version line (format: version: X.Y.Z-stage+buildNumber)
    content = content.replaceAllMapped(
      RegExp(r'version: [^\n]+'),
      (m) => 'version: $appVersion+$buildNumber',
    );

    pubspecFile.writeAsStringSync(content);
    print('✅ Updated pubspec.yaml');
  } else {
    print('⚠️ pubspec.yaml not found, skipping');
  }

  print('');
  print('🎉 Done! All versions synced from docs/version.json');
  print('');
  print('Next steps:');
  print('  1. Build your app: flutter build apk');
  print('  2. Copy APK to docs/filtored-v$appVersion.apk');
  print('  3. Commit and push to update website');
}
