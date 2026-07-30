import 'dart:io';

/// Utility class for consistent and beautiful output formatting across all unused checker tools
class OutputFormatter {
  static const String _reset = '\x1B[0m';
  static const String _bold = '\x1B[1m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _blue = '\x1B[34m';
  static const String _magenta = '\x1B[35m';
  static const String _cyan = '\x1B[36m';
  static const String _white = '\x1B[37m';

  /// Print a header with title and optional subtitle
  static void printHeader(String title, {String? subtitle}) {
    final titleLine = '🔍 $title';
    final border = '═' * (titleLine.length + 4);

    stdout.writeln('\n$_cyan$_bold$border$_reset');
    stdout.writeln('$_cyan$_bold  $titleLine  $_reset');
    if (subtitle != null) {
      stdout.writeln('$_cyan  📋 $subtitle  $_reset');
    }
    stdout.writeln('$_cyan$_bold$border$_reset\n');
  }

  /// Print a section header
  static void printSection(String title, {String? icon}) {
    final displayIcon = icon ?? '📂';
    stdout.writeln('$_blue$_bold$displayIcon $title$_reset');
    stdout.writeln('$_blue${'─' * (title.length + 3)}$_reset');
  }

  /// Print success message
  static void printSuccess(String message, {String? icon}) {
    final displayIcon = icon ?? '✅';
    stdout.writeln('$_green$_bold$displayIcon $message$_reset');
  }

  /// Print warning message
  static void printWarning(String message, {String? icon}) {
    final displayIcon = icon ?? '⚠️';
    stdout.writeln('$_yellow$_bold$displayIcon $message$_reset');
  }

  /// Print error message
  static void printError(String message, {String? icon}) {
    final displayIcon = icon ?? '❌';
    stdout.writeln('$_red$_bold$displayIcon $message$_reset');
  }

  /// Print info message
  static void printInfo(String message, {String? icon}) {
    final displayIcon = icon ?? 'ℹ️';
    stdout.writeln('$_cyan$displayIcon $message$_reset');
  }

  /// Print a list of items with bullets
  static void printList(
    List<String> items, {
    String bullet = '•',
    String? color,
  }) {
    final colorCode = _getColorCode(color);
    for (final item in items) {
      stdout.writeln('$colorCode  $bullet $item$_reset');
    }
  }

  /// Print a numbered list
  static void printNumberedList(List<String> items, {String? color}) {
    final colorCode = _getColorCode(color);
    for (int i = 0; i < items.length; i++) {
      stdout.writeln('$colorCode  ${i + 1}. ${items[i]}$_reset');
    }
  }

  /// Print statistics in a formatted table
  static void printStats(Map<String, dynamic> stats) {
    stdout.writeln('\n$_magenta$_bold📊 Statistics:$_reset');
    stdout.writeln('$_magenta┌${'─' * 30}┐$_reset');

    stats.forEach((key, value) {
      final paddedKey = key.padRight(20);
      stdout.writeln(
        '$_magenta│ $paddedKey: $_white$_bold$value$_reset$_magenta │$_reset',
      );
    });

    stdout.writeln('$_magenta└${'─' * 30}┘$_reset');
  }

  /// Print a summary box
  static void printSummary({
    required String title,
    required List<String> items,
    bool isSuccess = true,
  }) {
    final icon = isSuccess ? '✅' : '❌';
    final color = isSuccess ? _green : _red;
    final border = isSuccess ? '═' : '═';

    stdout.writeln(
      '\n$color$_bold$border$border$border Summary: $title $border$border$border$_reset',
    );

    if (items.isEmpty) {
      stdout.writeln('$color  🎉 No issues found!$_reset');
    } else {
      for (final item in items) {
        stdout.writeln('$color  $icon $item$_reset');
      }
    }

    stdout.writeln('$color$_bold${'═' * (title.length + 20)}$_reset\n');
  }

  /// Print progress indicator
  static void printProgress(String message, {int? current, int? total}) {
    if (current != null && total != null) {
      final percentage = ((current / total) * 100).round();
      final progressBar = _createProgressBar(percentage);
      stdout.writeln(
        '$_cyan⏳ $message [$progressBar] $current/$total ($percentage%)$_reset',
      );
    } else {
      stdout.writeln('$_cyan⏳ $message...$_reset');
    }
  }

  /// Print command execution
  static void printCommand(String command, List<String> args) {
    stdout.writeln(
      '$_magenta💻 Executing: $_white$command ${args.join(' ')}$_reset',
    );
  }

  /// Print file path with highlighting
  static void printFilePath(String path, {String? prefix, String? color}) {
    final colorCode = _getColorCode(color ?? 'cyan');
    final displayPrefix = prefix ?? '📄';
    stdout.writeln('$colorCode$displayPrefix $path$_reset');
  }

  /// Print separator line
  static void printSeparator({String char = '─', int length = 60}) {
    stdout.writeln('$_blue${char * length}$_reset');
  }

  /// Print timing information
  static void printTiming(String operation, Duration duration) {
    final ms = duration.inMilliseconds;
    final seconds = duration.inSeconds;

    String timeStr;
    if (ms < 1000) {
      timeStr = '${ms}ms';
    } else if (seconds < 60) {
      timeStr = '${(ms / 1000).toStringAsFixed(1)}s';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      timeStr = '${minutes}m ${remainingSeconds}s';
    }

    stdout.writeln(
      '$_magenta⏱️  $operation completed in $_white$_bold$timeStr$_reset',
    );
  }

  /// Create a progress bar string
  static String _createProgressBar(int percentage, {int width = 20}) {
    final filled = (width * percentage / 100).round();
    final empty = width - filled;
    return '${'█' * filled}${'░' * empty}';
  }

  /// Get color code from string
  static String _getColorCode(String? color) {
    switch (color?.toLowerCase()) {
      case 'red':
        return _red;
      case 'green':
        return _green;
      case 'yellow':
        return _yellow;
      case 'blue':
        return _blue;
      case 'magenta':
        return _magenta;
      case 'cyan':
        return _cyan;
      case 'white':
        return _white;
      default:
        return '';
    }
  }

  /// Print a box with content
  static void printBox(String title, List<String> content, {String? color}) {
    final colorCode = _getColorCode(color ?? 'blue');
    final maxLength = [
      title,
      ...content,
    ].map((s) => s.length).reduce((a, b) => a > b ? a : b);
    final width = maxLength + 4;

    stdout.writeln('$colorCode┌${'─' * width}┐$_reset');
    stdout.writeln('$colorCode│ ${title.padRight(width - 2)} │$_reset');
    stdout.writeln('$colorCode├${'─' * width}┤$_reset');

    for (final line in content) {
      stdout.writeln('$colorCode│ ${line.padRight(width - 2)} │$_reset');
    }

    stdout.writeln('$colorCode└${'─' * width}┘$_reset');
  }

  /// Print final result with emoji and color
  static void printFinalResult({
    required bool success,
    required String message,
    Map<String, dynamic>? stats,
  }) {
    final icon = success ? '🎉' : '💥';
    final color = success ? _green : _red;

    stdout.writeln('\n$color$_bold${'═' * 60}$_reset');
    stdout.writeln('$color$_bold$icon FINAL RESULT: $message $icon$_reset');

    if (stats != null && stats.isNotEmpty) {
      printStats(stats);
    }

    stdout.writeln('$color$_bold${'═' * 60}$_reset\n');
  }
}
