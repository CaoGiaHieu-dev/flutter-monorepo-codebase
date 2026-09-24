import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Shared plumbing for the tool tests.
///
/// Every CI-gating tool is exercised the way CI runs it: as a separate
/// process, against a throwaway workspace built in a temp directory, with
/// its exit code and output asserted. Nothing here touches the real
/// repository — the tools read their root from the working directory (or,
/// for `docs_check`, from their own location), and both point at the temp
/// workspace.
///
/// Each tool is compiled to a kernel snapshot once per test file. Running the
/// `.dill` skips the front end, which is most of a JIT start-up: ~0.5 s a run
/// instead of ~1.7 s, which is what keeps the whole suite well under a minute.

/// The repository root: the nearest ancestor of the working directory that
/// holds `tools/arch_check/check.dart`. `dart test` runs from `tools/`, CI
/// may run from the root; both resolve.
final String repoRoot = () {
  var dir = Directory.current.absolute;
  while (true) {
    if (File(
      p.join(dir.path, 'tools', 'arch_check', 'check.dart'),
    ).existsSync()) {
      return p.normalize(dir.path);
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Run the tool tests from inside the repository (cd tools && dart test).',
      );
    }
    dir = parent;
  }
}();

/// The `dart` executable the tools run under.
///
/// Under `dart test` that is the running VM. Under `flutter test` the running
/// executable is `flutter_tester`, which cannot compile or run a snapshot,
/// so the `dart` on `PATH` is used instead.
final String dartExecutable = () {
  final running = Platform.resolvedExecutable;
  return p.basenameWithoutExtension(running) == 'dart' ? running : 'dart';
}();

/// A tool compiled to kernel, runnable against any working directory.
class CompiledTool {
  CompiledTool._(this.source, this.dill);

  /// Repo-relative path of the tool's entry point, e.g.
  /// `tools/arch_check/check.dart`.
  final String source;

  /// The compiled snapshot.
  final String dill;

  /// Compiles [source] (repo-relative) into a fresh temp directory and
  /// registers its removal with [addTearDown] / [tearDownAll] by the caller.
  static Future<CompiledTool> compile(String source) async {
    final out = await Directory.systemTemp.createTemp('tool_dill_');
    final dill = p.join(out.path, '${p.basenameWithoutExtension(source)}.dill');
    final result = await Process.run(dartExecutable, [
      'compile',
      'kernel',
      p.join(repoRoot, source),
      '-o',
      dill,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Could not compile $source:\n${result.stdout}\n${result.stderr}',
      );
    }
    return CompiledTool._(source, dill);
  }

  /// Runs the tool with [args] in [workingDirectory]. With [scriptPath] the
  /// snapshot is first copied there, so a tool that locates the repository
  /// from its own script location (`docs_check`) finds the temp workspace.
  Future<ToolRun> run(
    List<String> args, {
    required String workingDirectory,
    String? scriptPath,
  }) async {
    var entry = dill;
    if (scriptPath != null) {
      entry = p.join(workingDirectory, scriptPath);
      Directory(p.dirname(entry)).createSync(recursive: true);
      File(dill).copySync(entry);
    }
    final result = await Process.run(
      dartExecutable,
      [entry, ...args],
      workingDirectory: workingDirectory,
    );
    return ToolRun(
      result.exitCode,
      '${result.stdout}',
      '${result.stderr}',
    );
  }

  Future<void> dispose() async {
    final dir = Directory(p.dirname(dill));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// What one tool invocation produced.
class ToolRun {
  ToolRun(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  /// stdout and stderr together, with ANSI colour codes stripped — the tools
  /// print through `OutputFormatter`, which colours rule headers.
  String get output =>
      '$stdout\n$stderr'.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');

  @override
  String toString() => 'exit $exitCode\n$output';
}

/// A throwaway workspace on disk.
class TempWorkspace {
  TempWorkspace._(this.root);

  final String root;

  /// Creates a temp directory holding [files] (repo-relative path ->
  /// content) and deletes it when the current test ends.
  static TempWorkspace create(Map<String, String> files) {
    final dir = Directory.systemTemp.createTempSync('tool_ws_');
    final ws = TempWorkspace._(p.normalize(dir.resolveSymbolicLinksSync()));
    ws.write(files);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return ws;
  }

  /// Writes (or overwrites) [files].
  void write(Map<String, String> files) {
    for (final entry in files.entries) {
      final file = File(p.join(root, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }

  /// Creates an empty directory — a module submodule nobody initialised.
  void mkdir(String relative) =>
      Directory(p.join(root, relative)).createSync(recursive: true);

  String read(String relative) =>
      File(p.join(root, relative)).readAsStringSync();

  bool exists(String relative) =>
      File(p.join(root, relative)).existsSync() ||
      Directory(p.join(root, relative)).existsSync();
}

/// Matches a [ToolRun] by exit code, with the output in the failure message.
Matcher exitsWith(int code) => _ExitsWith(code);

class _ExitsWith extends Matcher {
  _ExitsWith(this.code);

  final int code;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is ToolRun && item.exitCode == code;

  @override
  Description describe(Description description) =>
      description.add('a tool run exiting $code');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) => mismatchDescription.add('was $item');
}
