import 'dart:io';
import 'dart:developer' as developer;

void main() {
  final projectRoot = Directory.current;
  final stats = <String, int>{'Dart': 0, 'Kotlin': 0, 'XML': 0, 'Python': 0};

  final extensions = {
    '.dart': 'Dart',
    '.kt': 'Kotlin',
    '.xml': 'XML',
    '.py': 'Python',
  };

  void countLines(Directory dir) {
    try {
      for (var entity in dir.listSync()) {
        if (entity is File) {
          final ext = entity.path.substring(entity.path.lastIndexOf('.'));
          if (extensions.containsKey(ext)) {
            final lines = entity.readAsLinesSync().length;
            stats[extensions[ext]!] = (stats[extensions[ext]!] ?? 0) + lines;
          }
        } else if (entity is Directory) {
          final name = entity.path.split(Platform.pathSeparator).last;
          // Skip common directories
          if (![
            'build',
            '.dart_tool',
            '.git',
            'node_modules',
            'yolovenv',
            'backend',
          ].contains(name)) {
            countLines(entity);
          }
        }
      }
    } catch (_) {}
  }

  countLines(projectRoot);

  developer.log('\n╔═══════════════════════════════════════╗');
  developer.log('║       📊 CODE LINE COUNTER 📊        ║');
  developer.log('╠═══════════════════════════════════════╣');

  var total = 0;
  stats.forEach((lang, lines) {
    if (lines > 0) {
      total += lines;
      developer.log(
        '║ ${lang.padRight(10)} │ ${lines.toString().padLeft(8)} lines ║',
      );
    }
  });

  developer.log('╠═══════════════════════════════════════╣');
  developer.log('║ TOTAL      │ ${total.toString().padLeft(8)} lines ║');
  developer.log('╚═══════════════════════════════════════╝\n');
}
