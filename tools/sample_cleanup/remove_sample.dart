import 'dart:io';

import 'package:yaml/yaml.dart';

/// Removes a sample bundle — the feature package *and* everything that travels
/// with it (domain/data pairs, workspace entries, DI registrations).
///
/// The template ships working reference features. Deleting one by hand is where
/// people get hurt: `auth` is not just `packages/features/auth`, it is also
/// `domain_auth`, `data_auth`, six contracts in `core_di`, and three shared
/// files. Miss one and the workspace stops resolving.
///
/// Usage:
///   dart tools/sample_cleanup/remove_sample.dart --list
///   dart tools/sample_cleanup/remove_sample.dart auth           # preview
///   dart tools/sample_cleanup/remove_sample.dart auth --apply   # do it
const String _manifestPath = 'tools/sample_manifest.yaml';

/// Shared files every removal rewrites in place.
///
/// Snapshotted before the first mutation so a failure partway through restores
/// them rather than leaving a workspace that references a deleted package.
/// Same contract as `CommonHelpers.sharedMutatedFiles` in the module generator.
const List<String> _sharedMutatedFiles = [
  'pubspec.yaml',
  'app/pubspec.yaml',
  'app/lib/di/injection.dart',
];

final Map<String, String?> _snapshots = {};
final List<String> _deletedDirs = [];

Future<void> main(List<String> args) async {
  if (!File(_manifestPath).existsSync()) {
    stderr.writeln('[ERROR] Không tìm thấy $_manifestPath. '
        'Hãy chạy lệnh này từ thư mục gốc của repo.');
    exitCode = 1;
    return;
  }

  final manifest = loadYaml(File(_manifestPath).readAsStringSync()) as YamlMap;

  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  if (args.contains('--list')) {
    _printClassification(manifest);
    return;
  }

  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.isEmpty) {
    stderr.writeln('[ERROR] Thiếu tên bundle. Xem "--list" để biết các lựa chọn.');
    exitCode = 1;
    return;
  }

  final bundleName = positional.first;
  final bundles = manifest['bundles'] as YamlMap;
  if (!bundles.containsKey(bundleName)) {
    stderr.writeln('[ERROR] Không có bundle "$bundleName". '
        'Các bundle hợp lệ: ${bundles.keys.join(', ')}');
    exitCode = 1;
    return;
  }

  // Dry-run is the default on purpose: this deletes whole package directories,
  // and the repo may well have uncommitted work, so an accidental run must not
  // be destructive. Writing requires opting in with --apply.
  final apply = args.contains('--apply');
  await _removeBundle(
    manifest: manifest,
    bundleName: bundleName,
    bundle: bundles[bundleName] as YamlMap,
    apply: apply,
  );
}

void _printUsage() {
  stdout.writeln('''
Gỡ một bundle code mẫu khỏi template.

  dart tools/sample_cleanup/remove_sample.dart --list
      In bảng phân loại sample / framework / shell.

  dart tools/sample_cleanup/remove_sample.dart <bundle>
      Xem trước (dry-run) — KHÔNG ghi gì. Đây là mặc định.

  dart tools/sample_cleanup/remove_sample.dart <bundle> --apply
      Thực hiện gỡ thật, có rollback nếu bước nào lỗi.

Nguồn phân loại: $_manifestPath
''');
}

void _printClassification(YamlMap manifest) {
  final packages = manifest['packages'] as YamlMap;

  final byKind = <String, List<MapEntry<String, YamlMap>>>{
    'framework': [],
    'shell': [],
    'sample': [],
  };
  packages.forEach((name, value) {
    final entry = value as YamlMap;
    final kind = entry['kind'] as String;
    byKind.putIfAbsent(kind, () => []).add(MapEntry(name as String, entry));
  });

  stdout.writeln('');
  stdout.writeln('PHÂN LOẠI PACKAGE  (nguồn: $_manifestPath)');
  stdout.writeln('=' * 78);

  const labels = {
    'framework': 'FRAMEWORK — giữ lại. Xoá là vỡ template.',
    'shell': 'SHELL — giữ lại, nhưng sửa khi thêm/bớt feature.',
    'sample': 'SAMPLE — xoá thoải mái sau khi đã hiểu.',
  };

  for (final kind in const ['framework', 'shell', 'sample']) {
    final entries = byKind[kind] ?? [];
    if (entries.isEmpty) continue;
    stdout.writeln('');
    stdout.writeln(labels[kind] ?? kind);
    stdout.writeln('-' * 78);
    for (final e in entries) {
      stdout.writeln('  ${e.key.padRight(28)} ${e.value['path']}');
    }
  }

  final embedded = manifest['embedded_samples'] as YamlMap?;
  if (embedded != null) {
    stdout.writeln('');
    stdout.writeln('SAMPLE NẰM TRONG PACKAGE FRAMEWORK — xoá theo FILE, không xoá package');
    stdout.writeln('-' * 78);
    embedded.forEach((name, value) {
      final entry = value as YamlMap;
      final files = (entry['files'] as YamlList?)?.length ?? 0;
      stdout.writeln('  ${(name as String).padRight(28)} '
          '$files file trong ${(entry['lives_in'] as YamlList).join(', ')}');
      stdout.writeln('  ${' '.padRight(28)} ${entry['warning']}');
    });
  }

  final bundles = manifest['bundles'] as YamlMap;
  stdout.writeln('');
  stdout.writeln('BUNDLE GỠ ĐƯỢC: ${bundles.keys.join(', ')}');
  stdout.writeln('  Xem trước: dart tools/sample_cleanup/remove_sample.dart <bundle>');
  stdout.writeln('');
}

Future<void> _removeBundle({
  required YamlMap manifest,
  required String bundleName,
  required YamlMap bundle,
  required bool apply,
}) async {
  final packages = manifest['packages'] as YamlMap;
  final pkgNames = (bundle['packages'] as YamlList).cast<String>();

  final mode = apply ? 'ÁP DỤNG THẬT' : 'XEM TRƯỚC (dry-run — không ghi gì)';
  stdout.writeln('');
  stdout.writeln('Gỡ bundle "$bundleName"  —  $mode');
  stdout.writeln('=' * 78);

  // --- 1. Directories ------------------------------------------------------
  stdout.writeln('');
  stdout.writeln('Xoá thư mục package:');
  final dirs = <String>[];
  for (final name in pkgNames) {
    final entry = packages[name] as YamlMap?;
    if (entry == null) {
      stderr.writeln('  [WARN] "$name" không có trong manifest, bỏ qua.');
      continue;
    }
    final path = entry['path'] as String;
    final exists = Directory(path).existsSync();
    stdout.writeln('  ${exists ? '-' : 'x'} $path'
        '${exists ? '' : '   (không tồn tại, bỏ qua)'}');
    if (exists) dirs.add(path);
  }

  // --- 2. Shared file edits ------------------------------------------------
  stdout.writeln('');
  stdout.writeln('Sửa file dùng chung:');
  final edits = _planSharedEdits(pkgNames, packages);
  if (edits.isEmpty) {
    stdout.writeln('  (không có dòng nào khớp)');
  }
  for (final edit in edits) {
    stdout.writeln('  ${edit.file}');
    for (final line in edit.removedLines) {
      stdout.writeln('      - ${line.trim()}');
    }
  }

  // --- 3. Consequences the docs never covered ------------------------------
  final breaks = bundle['breaks'] as YamlList?;
  if (breaks != null && breaks.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('!! SAMPLE KHÁC SẼ VỠ — phải xử lý bằng tay:');
    for (final b in breaks) {
      final m = b as YamlMap;
      stdout.writeln('  * ${m['sample']}  (${m['at']})');
      stdout.writeln('      vì  : ${m['why']}');
      stdout.writeln('      sửa : ${m['fix']}');
    }
  }

  final orphans = bundle['orphaned_contracts'] as YamlList?;
  if (orphans != null && orphans.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Contract ở core_di trở thành code chết (tự quyết định xoá):');
    for (final o in orphans) {
      stdout.writeln('  ? $o');
    }
  }

  final keys = bundle['orphaned_keys'] as YamlList?;
  if (keys != null && keys.isNotEmpty) {
    for (final k in keys) {
      stdout.writeln('  ? $k');
    }
  }

  final safe = bundle['safe_couplings'] as YamlList?;
  if (safe != null && safe.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Liên kết an toàn (getItOrNull + fallback, tự suy biến):');
    for (final s in safe) {
      stdout.writeln('  ok $s');
    }
  }

  final note = bundle['note'] as String?;
  if (note != null) {
    stdout.writeln('');
    stdout.writeln('Ghi chú: $note');
  }

  // --- 4. Execute ----------------------------------------------------------
  if (!apply) {
    stdout.writeln('');
    stdout.writeln('Chưa có gì bị thay đổi. Thêm --apply để thực hiện thật.');
    stdout.writeln('');
    return;
  }

  stdout.writeln('');
  stdout.writeln('Đang áp dụng...');
  _snapshotSharedFiles();
  try {
    for (final edit in edits) {
      File(edit.file).writeAsStringSync(edit.newContent);
      stdout.writeln('  đã sửa ${edit.file}');
    }
    for (final dir in dirs) {
      Directory(dir).deleteSync(recursive: true);
      _deletedDirs.add(dir);
      stdout.writeln('  đã xoá  $dir');
    }
  } catch (e) {
    stderr.writeln('[ERROR] Thất bại giữa chừng: $e');
    stderr.writeln('[INFO] Đang khôi phục các file dùng chung...');
    _rollback();
    stderr.writeln('[INFO] Đã khôi phục file dùng chung. '
        'Thư mục đã xoá KHÔNG khôi phục được — dùng git để lấy lại.');
    exitCode = 1;
    return;
  }

  stdout.writeln('');
  stdout.writeln('Xong. Bước tiếp theo:');
  stdout.writeln('  flutter pub get');
  stdout.writeln('  dart run build_runner build -d --workspace');
  stdout.writeln('  flutter analyze');
  stdout.writeln('');
}

class _FileEdit {
  _FileEdit(this.file, this.removedLines, this.newContent);

  final String file;
  final List<String> removedLines;
  final String newContent;
}

/// Works out which lines each shared file loses, without writing anything.
///
/// Line-oriented rather than YAML/AST-aware on purpose: these files carry
/// comments and grouping that a re-serialise would flatten, and the module
/// generator already edits them the same way.
List<_FileEdit> _planSharedEdits(List<String> pkgNames, YamlMap packages) {
  final edits = <_FileEdit>[];

  final paths = <String, String>{};
  for (final name in pkgNames) {
    final entry = packages[name] as YamlMap?;
    if (entry != null) paths[name] = entry['path'] as String;
  }

  for (final file in _sharedMutatedFiles) {
    final f = File(file);
    if (!f.existsSync()) continue;

    final lines = f.readAsLinesSync();
    final keep = <String>[];
    final removed = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var drop = false;

      for (final name in pkgNames) {
        // injection.dart: `import 'package:feature_auth/di/module.module.dart';`
        if (line.contains('package:$name/di/module.module.dart')) drop = true;

        // injection.dart: `  ExternalModule(FeatureAuthPackageModule),`
        if (line.contains('ExternalModule(${_moduleClass(name)})')) drop = true;

        // root pubspec: `  - packages/features/auth`
        final path = paths[name];
        if (path != null && RegExp('^\\s*-\\s+$path\\s*\$').hasMatch(line)) {
          drop = true;
        }

        // app/pubspec.yaml: `  feature_auth:` followed by `    path: ...`
        if (RegExp('^\\s{2}$name:\\s*\$').hasMatch(line)) {
          drop = true;
          if (i + 1 < lines.length &&
              lines[i + 1].trim().startsWith('path:')) {
            removed.add(lines[i + 1]);
            i++; // consume the path line with it
          }
        }
      }

      if (drop) {
        removed.add(line);
      } else {
        keep.add(line);
      }
    }

    if (removed.isNotEmpty) {
      edits.add(_FileEdit(file, removed, '${keep.join('\n')}\n'));
    }
  }

  return edits;
}

/// `feature_auth` -> `FeatureAuthPackageModule`.
String _moduleClass(String packageName) {
  final pascal = packageName
      .split('_')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join();
  return '${pascal}PackageModule';
}

void _snapshotSharedFiles() {
  _snapshots.clear();
  for (final path in _sharedMutatedFiles) {
    final file = File(path);
    _snapshots[path] = file.existsSync() ? file.readAsStringSync() : null;
  }
}

/// Best-effort restore: reports what it could not undo rather than throwing,
/// because it runs while another error is already propagating.
void _rollback() {
  _snapshots.forEach((path, original) {
    try {
      final file = File(path);
      if (original == null) {
        if (file.existsSync()) file.deleteSync();
      } else {
        file.writeAsStringSync(original);
      }
    } catch (e) {
      stderr.writeln('  [WARN] không khôi phục được $path ($e)');
    }
  });
}
