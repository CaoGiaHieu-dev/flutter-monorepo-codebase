import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/constants.dart';
import '../core/enums.dart';
import 'git_helper.dart';

/// Utility class for analyzing file types and architecture layers
class FileAnalyzer {
  /// Get file type based on path and naming conventions
  static FileType getFileType(String filePath) {
    final fileName = path.basename(filePath);
    final dirPath = path.dirname(filePath);

    if (fileName.endsWith('_page.dart')) return FileType.page;
    if (fileName.endsWith('_widget.dart')) return FileType.widget;
    if (fileName.endsWith('_provider.dart')) return FileType.provider;
    if (fileName.endsWith('_entity.dart')) return FileType.entity;
    if (fileName.endsWith('_usecase.dart')) return FileType.useCase;
    if (fileName.endsWith('_repository.dart')) return FileType.repository;
    if (fileName.endsWith('_repository_impl.dart'))
      return FileType.repositoryImpl;
    if (fileName.endsWith('_data_source.dart')) return FileType.dataSource;
    if (fileName.contains('constants')) return FileType.constants;
    if (fileName.contains('config')) return FileType.config;
    if (dirPath.contains('models')) return FileType.model;
    if (dirPath.contains('params')) return FileType.parameters;

    return FileType.dartFile;
  }

  /// Get architecture layer from where the file sits in the workspace:
  /// `modules/<name>/{domain,data,feature}`, `platform/<pkg>`, `apps/<id>`.
  static ArchitectureLayer getArchitectureLayer(String filePath) {
    final p = filePath.replaceAll('\\', '/');
    if (p.contains('/gen/') || p.contains('/generated/')) {
      return ArchitectureLayer.generated;
    }
    final module = RegExp(r'(^|/)modules/[^/]+/(domain|data|feature)/')
        .firstMatch(p);
    if (module != null) {
      return switch (module.group(2)) {
        'domain' => ArchitectureLayer.domain,
        'data' => ArchitectureLayer.data,
        _ => ArchitectureLayer.presentation,
      };
    }
    if (RegExp(r'(^|/)platform/').hasMatch(p)) return ArchitectureLayer.core;
    if (RegExp(r'(^|/)apps/').hasMatch(p))
      return ArchitectureLayer.presentation;
    return ArchitectureLayer.unknown;
  }

  /// Source roots of the workspace, scanned when run from the repository
  /// root (which has no `lib/` of its own).
  static const List<String> workspaceRoots = ['apps', 'modules', 'platform'];

  /// Check if file matches a pattern (supports * wildcard)
  static bool matchesPattern(String text, String pattern) {
    final regexPattern = pattern
        .replaceAll('**/', '.*/')
        .replaceAll('*', '[^/]*')
        .replaceAll('?', '.');
    return RegExp(regexPattern).hasMatch(text);
  }

  /// Validate that we're in a Flutter project
  static Future<bool> validateFlutterProject() async {
    final pubspecFile = File('pubspec.yaml');
    if (!await pubspecFile.exists()) {
      return false;
    }

    final pubspecContent = await pubspecFile.readAsString();
    // The workspace root: no `lib/`, its packages live under the roots.
    if (pubspecContent.contains('\nworkspace:')) return true;

    if (!await Directory('lib').exists()) return false;
    return pubspecContent.contains('flutter:') ||
        pubspecContent.contains('flutter_');
  }

  /// Get all Dart files in the project: a package's `lib/`, or — from the
  /// workspace root — every `lib/` under [workspaceRoots].
  static Future<List<String>> getAllDartFiles() async {
    final files = <String>[];
    final libDir = Directory('lib');

    if (await libDir.exists()) {
      files.addAll(await getDartFilesInFolder('lib'));
      return files;
    }

    for (final root in workspaceRoots) {
      for (final file in await getDartFilesInFolder(root)) {
        final p = file.replaceAll('\\', '/');
        if (p.contains('/lib/') &&
            !p.contains('/.dart_tool/') &&
            !p.contains('/build/')) {
          files.add(file);
        }
      }
    }
    return files;
  }

  /// Get all Dart files in a specific folder
  static Future<List<String>> getDartFilesInFolder(String folderPath) async {
    final files = <String>[];
    final folder = Directory(folderPath);

    if (!await folder.exists()) {
      return files;
    }

    await for (final entity in folder.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity.path);
      }
    }

    return files;
  }

  /// Whether [filePath] is generated code or a test — excluded always.
  static bool isGeneratedOrTest(String filePath) {
    final p = '/${filePath.replaceAll('\\', '/')}';
    final name = path.posix.basename(p);
    return CodeReviewConstants.generatedSuffixes.any(name.endsWith) ||
        CodeReviewConstants.generatedFilePrefixes.any(name.startsWith) ||
        CodeReviewConstants.excludedPathSegments.any(p.contains);
  }

  /// Drops generated files and tests, gitignored files, and anything
  /// matching [excludePatterns].
  ///
  /// The built-in exclusions used to apply only when no `--exclude` was
  /// given, so adding one pattern put every `*.g.dart` back in the review.
  static Future<List<String>> filterFiles(
    List<String> files,
    List<String> excludePatterns,
  ) async {
    final kept = files.where((file) {
      if (isGeneratedOrTest(file)) return false;
      for (final pattern in excludePatterns) {
        if (matchesPattern(file, pattern)) return false;
      }
      return true;
    }).toList();
    final ignored = await GitHelper.ignoredFiles(kept);
    return kept.where((f) => !ignored.contains(f)).toList();
  }
}
